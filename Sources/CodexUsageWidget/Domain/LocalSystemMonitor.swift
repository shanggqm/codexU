import Combine
import Darwin
import Foundation

enum LocalThermalLevel: Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

struct LocalSystemSnapshot: Equatable {
    let cpuUsagePercent: Double?
    let memoryUsedBytes: UInt64?
    let memoryTotalBytes: UInt64?
    let temperatureCelsius: Double?
    let thermalLevel: LocalThermalLevel
    let sampledAt: Date

    static let empty = LocalSystemSnapshot(
        cpuUsagePercent: nil,
        memoryUsedBytes: nil,
        memoryTotalBytes: nil,
        temperatureCelsius: nil,
        thermalLevel: .unknown,
        sampledAt: Date()
    )
}

private struct LocalCPUTicks {
    let used: UInt64
    let total: UInt64
}

private enum LocalSystemSampler {
    static func cpuTicks() -> LocalCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return LocalCPUTicks(used: user + system + nice, total: user + system + idle + nice)
    }

    static func cpuUsage(previous: LocalCPUTicks?, current: LocalCPUTicks?) -> Double? {
        guard let previous, let current,
              current.total >= previous.total,
              current.used >= previous.used
        else { return nil }
        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return nil }
        let usedDelta = current.used - previous.used
        return min(100, max(0, Double(usedDelta) / Double(totalDelta) * 100))
    }

    static func memoryUsage() -> (used: UInt64, total: UInt64)? {
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let availablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let available = min(total, availablePages * UInt64(pageSize))
        return (total - available, total)
    }

    static func thermalLevel() -> LocalThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .unknown
        }
    }
}

@MainActor
final class LocalSystemMonitor: ObservableObject {
    @Published private(set) var snapshot = LocalSystemSnapshot.empty

    private var timer: Timer?
    private var previousCPUTicks: LocalCPUTicks?

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPUTicks = nil
    }

    private func sample() {
        let currentTicks = LocalSystemSampler.cpuTicks()
        let cpuUsage = LocalSystemSampler.cpuUsage(previous: previousCPUTicks, current: currentTicks)
        previousCPUTicks = currentTicks
        let memory = LocalSystemSampler.memoryUsage()
        snapshot = LocalSystemSnapshot(
            cpuUsagePercent: cpuUsage,
            memoryUsedBytes: memory?.used,
            memoryTotalBytes: memory?.total,
            temperatureCelsius: nil,
            thermalLevel: LocalSystemSampler.thermalLevel(),
            sampledAt: Date()
        )
    }
}

enum LocalSystemMonitorSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        if let ticks = LocalSystemSampler.cpuTicks() {
            if ticks.total == 0 || ticks.used > ticks.total {
                failures.append("CPU ticks were invalid")
            }
        } else {
            failures.append("CPU ticks were unavailable")
        }

        if let memory = LocalSystemSampler.memoryUsage() {
            if memory.total == 0 || memory.used > memory.total {
                failures.append("memory usage was invalid")
            }
        } else {
            failures.append("memory usage was unavailable")
        }

        if failures.isEmpty {
            print("local system monitor self-test passed")
            return true
        }
        failures.forEach { print("local system monitor self-test failed: \($0)") }
        return false
    }
}

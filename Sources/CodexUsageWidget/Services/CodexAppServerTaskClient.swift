import AppKit
import Darwin
import Foundation

enum TaskConnectionReason: Hashable {
    case startup
    case taskUI
    case popover
}

protocol CodexTaskEventClient: AnyObject {
    var onSnapshot: ((CodexTaskLiveSnapshot) -> Void)? { get set }
    func start(reason: TaskConnectionReason)
    func stopIfIdle()
    func stop()
    func refreshThreads()
}

enum POSIXPipeReaderError: Error {
    case duplicateFailed(Int32)
    case readFailed(Int32)
}

enum POSIXPipeReader {
    static func duplicateDescriptor(for handle: FileHandle) throws -> Int32 {
        let descriptor = Darwin.dup(handle.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXPipeReaderError.duplicateFailed(errno) }
        return descriptor
    }

    /// Foundation's `read(upToCount:)` may wait for the full requested length on
    /// a pipe. POSIX read returns as soon as any bytes are available, which is
    /// required for long-lived app-server streams that intentionally keep stdout open.
    static func readChunk(from descriptor: Int32, maximumBytes: Int) throws -> Data? {
        precondition(maximumBytes > 0)
        var bytes = [UInt8](repeating: 0, count: maximumBytes)
        while true {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 { return Data(bytes.prefix(Int(count))) }
            if count == 0 { return nil }
            let code = errno
            if code == EINTR { continue }
            throw POSIXPipeReaderError.readFailed(code)
        }
    }
}

enum POSIXPipeReaderSelfTest {
    static func run() -> Bool {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let writer = pipe.fileHandleForWriting
        guard let descriptor = try? POSIXPipeReader.duplicateDescriptor(for: reader) else {
            print("POSIX pipe reader self-test failed: could not duplicate descriptor")
            return false
        }
        defer {
            Darwin.close(descriptor)
            try? reader.close()
            try? writer.close()
        }

        let payload = Data("partial response\n".utf8)
        do {
            try writer.write(contentsOf: payload)
            let startedAt = Date()
            let result = try POSIXPipeReader.readChunk(from: descriptor, maximumBytes: 64 * 1_024)
            guard result == payload, Date().timeIntervalSince(startedAt) < 1 else {
                print("POSIX pipe reader self-test failed: partial response was not returned promptly")
                return false
            }
            try writer.close()
            guard try POSIXPipeReader.readChunk(from: descriptor, maximumBytes: 64 * 1_024) == nil else {
                print("POSIX pipe reader self-test failed: EOF was not detected")
                return false
            }
        } catch {
            print("POSIX pipe reader self-test failed: \(error)")
            return false
        }

        print("POSIX pipe reader self-test passed")
        return true
    }
}

final class CodexAppServerTaskClient: CodexTaskEventClient {
    var onSnapshot: ((CodexTaskLiveSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "com.codexu.task-app-server", qos: .utility)
    private let readerQueue = DispatchQueue(label: "com.codexu.task-app-server.reader", qos: .utility)
    private let fileManager: FileManager
    private let homeDirectory: URL
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var reducer = TaskRuntimeReducer()
    private var connectionMode: TaskConnectionMode = .disconnected
    private var activeReasons: Set<TaskConnectionReason> = []
    private var nextRequestID: Int64 = 100
    private var pendingThreadListIDs: Set<Int64> = []
    private var pendingThreadListSpans: [Int64: PerformanceSpan] = [:]
    private var pendingThreadListTimeouts: [Int64: DispatchWorkItem] = [:]
    private var initializeTimeout: DispatchWorkItem?
    private var isStopping = false
    private var connectionGeneration: UInt64 = 0

    private let initializeRequestID: Int64 = 1
    private let maximumOutputBufferBytes = 1 * 1_024 * 1_024
    private let maximumReadChunkBytes = 64 * 1_024
    private let threadListTimeoutSeconds: TimeInterval = 10

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func start(reason: TaskConnectionReason) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeReasons.insert(reason)
            if self.process?.isRunning == true {
                if reason != .startup { self.requestThreadList() }
                return
            }

            let sharedDaemonAvailable = self.fileManager.fileExists(atPath: self.defaultDaemonSocket.path)
            guard sharedDaemonAvailable else { return }
            self.launch(mode: .sharedDaemon)
        }
    }

    func stopIfIdle() {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeReasons.remove(.taskUI)
            self.activeReasons.remove(.popover)
            if self.connectionMode == .isolated {
                self.stopProcess()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.activeReasons.removeAll()
            self?.stopProcess()
        }
    }

    func refreshThreads() {
        queue.async { [weak self] in
            self?.requestThreadList()
        }
    }

    private var defaultDaemonSocket: URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock")
    }

    private func launch(mode: TaskConnectionMode) {
        guard let codexURL = resolveCodexExecutableURL() else {
            reducer.disconnect()
            publishSnapshot()
            return
        }

        isStopping = false
        outputBuffer.removeAll(keepingCapacity: true)
        pendingThreadListIDs.removeAll()
        pendingThreadListSpans.removeAll()
        pendingThreadListTimeouts.values.forEach { $0.cancel() }
        pendingThreadListTimeouts.removeAll()
        connectionGeneration &+= 1
        let generation = connectionGeneration
        connectionMode = mode

        let process = Process()
        process.executableURL = codexURL
        process.arguments = mode == .sharedDaemon
            ? ["app-server", "proxy"]
            : ["app-server"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.handleDisconnect(generation: generation)
            }
        }

        do {
            try process.run()
        } catch {
            connectionMode = .disconnected
            reducer.disconnect()
            publishSnapshot()
            return
        }

        self.process = process
        inputHandle = input.fileHandleForWriting
        outputHandle = output.fileHandleForReading
        guard startReadLoop(handle: output.fileHandleForReading, generation: generation) else {
            stopProcess()
            return
        }

        guard writeJSONObject([
            "id": initializeRequestID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codexu",
                    "title": "codexU",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                ],
                "capabilities": [
                    "experimentalApi": false,
                    "optOutNotificationMethods": []
                ]
            ]
        ]) else {
            stopProcess()
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.process?.isRunning == true else { return }
            self.stopProcess()
        }
        initializeTimeout = timeout
        queue.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    private func startReadLoop(handle: FileHandle, generation: UInt64) -> Bool {
        guard let descriptor = try? POSIXPipeReader.duplicateDescriptor(for: handle) else {
            return false
        }
        readerQueue.async { [weak self] in
            defer { Darwin.close(descriptor) }
            while let self {
                let data: Data
                do {
                    guard let next = try POSIXPipeReader.readChunk(
                        from: descriptor,
                        maximumBytes: self.maximumReadChunkBytes
                    ) else { break }
                    data = next
                } catch {
                    break
                }

                var accepted = false
                self.queue.sync {
                    guard self.connectionGeneration == generation,
                          self.process != nil else { return }
                    accepted = self.consume(data)
                }
                if !accepted { break }
            }

            self?.queue.async { [weak self] in
                self?.handleDisconnect(generation: generation)
            }
        }
        return true
    }

    @discardableResult
    private func consume(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard data.count <= maximumOutputBufferBytes,
              outputBuffer.count <= maximumOutputBufferBytes - data.count else {
            stopProcess()
            return false
        }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<newline)
            outputBuffer.removeSubrange(outputBuffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            handle(object)
        }
        if outputBuffer.count > maximumOutputBufferBytes {
            stopProcess()
            return false
        }
        return true
    }

    private func handle(_ object: [String: Any]) {
        if let method = object["method"] as? String {
            guard object["id"] == nil else { return }
            let params = object["params"] as? [String: Any] ?? [:]
            if reducer.applyNotification(method: method, params: params) {
                publishSnapshot()
            }
            return
        }

        guard let responseID = Self.integerID(object["id"]) else { return }
        if responseID == initializeRequestID {
            initializeTimeout?.cancel()
            initializeTimeout = nil
            guard object["error"] == nil else {
                stopProcess()
                return
            }
            _ = writeJSONObject(["method": "initialized"])
            requestThreadList()
            return
        }

        guard pendingThreadListIDs.remove(responseID) != nil else { return }
        pendingThreadListTimeouts.removeValue(forKey: responseID)?.cancel()
        let span = pendingThreadListSpans.removeValue(forKey: responseID)
        guard let result = object["result"] as? [String: Any],
              let threads = result["data"] as? [[String: Any]]
        else {
            if let span {
                PerformanceMonitor.shared.end(span, success: false)
            }
            return
        }

        if let span {
            PerformanceMonitor.shared.end(span)
        }
        reducer.replaceThreads(threads, connectionMode: connectionMode)
        publishSnapshot()
    }

    private func requestThreadList() {
        guard process?.isRunning == true,
              initializeTimeout == nil,
              pendingThreadListIDs.isEmpty else { return }
        let requestID = nextRequestID
        nextRequestID &+= 1
        pendingThreadListIDs.insert(requestID)
        pendingThreadListSpans[requestID] = PerformanceMonitor.shared.begin(.appServerTasks)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingThreadListIDs.remove(requestID) != nil else { return }
            self.pendingThreadListTimeouts.removeValue(forKey: requestID)
            if let span = self.pendingThreadListSpans.removeValue(forKey: requestID) {
                PerformanceMonitor.shared.end(span, success: false)
            }
        }
        pendingThreadListTimeouts[requestID] = timeout
        queue.asyncAfter(deadline: .now() + threadListTimeoutSeconds, execute: timeout)
        let wrote = writeJSONObject([
            "id": requestID,
            "method": "thread/list",
            "params": [
                "limit": 100,
                "sortKey": "recency_at",
                "sortDirection": "desc",
                "useStateDbOnly": true,
                "sourceKinds": ["cli", "vscode", "appServer"]
            ]
        ])
        if !wrote {
            pendingThreadListIDs.remove(requestID)
            pendingThreadListTimeouts.removeValue(forKey: requestID)?.cancel()
            if let span = pendingThreadListSpans.removeValue(forKey: requestID) {
                PerformanceMonitor.shared.end(span, success: false)
            }
            handleDisconnect()
        }
    }

    private func writeJSONObject(_ object: [String: Any]) -> Bool {
        guard let handle = inputHandle,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return false }
        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
            return true
        } catch {
            return false
        }
    }

    private func publishSnapshot() {
        let snapshot = reducer.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    private func handleDisconnect(generation: UInt64? = nil) {
        if let generation, generation != connectionGeneration { return }
        guard connectionMode != .disconnected || process != nil else { return }
        initializeTimeout?.cancel()
        initializeTimeout = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        let disconnectedProcess = process
        inputHandle = nil
        outputHandle = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingThreadListIDs.removeAll()
        pendingThreadListTimeouts.values.forEach { $0.cancel() }
        pendingThreadListTimeouts.removeAll()
        for span in pendingThreadListSpans.values {
            PerformanceMonitor.shared.end(span, success: false)
        }
        pendingThreadListSpans.removeAll()
        connectionMode = .disconnected
        reducer.disconnect()
        publishSnapshot()
        if let disconnectedProcess, disconnectedProcess.isRunning {
            let pid = disconnectedProcess.processIdentifier
            disconnectedProcess.terminate()
            queue.asyncAfter(deadline: .now() + 1) {
                if disconnectedProcess.isRunning { Darwin.kill(pid, SIGKILL) }
            }
        }
    }

    private func stopProcess() {
        guard !isStopping else { return }
        isStopping = true
        initializeTimeout?.cancel()
        initializeTimeout = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        handleDisconnect()
        isStopping = false
    }

    private func resolveCodexExecutableURL() -> URL? {
        CodexExecutableLocator.resolve()
    }

    private static func integerID(_ value: Any?) -> Int64? {
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Int64 { return value }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }
}

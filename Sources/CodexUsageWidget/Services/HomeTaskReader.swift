import Darwin
import Foundation

/// Keeps the legacy filesystem/SQLite task readers outside the home process.
/// The worker returns a bounded display board; it can be killed without leaving
/// a blocked thread in the app or preventing the next task refresh.
enum HomeTaskReader {
    static let maximumBytes = 256 * 1_024
    static let timeout: TimeInterval = 3
    static let timeZoneEnvironmentKey = "CODEXU_HOME_TASKS_TIME_ZONE"
    static let nowEnvironmentKey = "CODEXU_HOME_TASKS_NOW"

    static func read(
        scope: RuntimeScope,
        context: RuntimeLoadContext,
        executableURL: URL? = nil
    ) -> TaskBoard? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        guard let executable = executableURL ?? Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--read-home-tasks", scope.rawValue]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEXU_HOME_OVERRIDE"] = context.homeDirectory.path
        environment["CODEXU_CACHE_OVERRIDE"] = context.cacheDirectory.path
        environment[timeZoneEnvironmentKey] = context.statistics.resolvedIdentifier
        environment[nowEnvironmentKey] = String(context.now.timeIntervalSince1970)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        let handle = output.fileHandleForReading
        defer { try? handle.close() }

        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return nil }
        do {
            try process.run()
        } catch {
            try? output.fileHandleForWriting.close()
            return nil
        }
        try? output.fileHandleForWriting.close()
        let childPID = process.processIdentifier
        var ownsProcessGroup = false

        func rememberProcessGroup() {
            // The CLI branch creates its own group before invoking the provider.
            // Never assume the child belongs to a group safe to kill.
            if getpgid(childPID) == childPID { ownsProcessGroup = true }
        }

        defer {
            rememberProcessGroup()
            // Only this short-lived helper and the descendants in its verified
            // group are targeted. No global process-name matching or blocking join.
            if ownsProcessGroup {
                _ = Darwin.kill(-childPID, SIGTERM)
                // Escalate for the already-expired worker even if TERM caused
                // its leader to exit; SQLite descendants still belong to it.
                _ = Darwin.kill(-childPID, SIGKILL)
            }
            if process.isRunning {
                _ = Darwin.kill(childPID, SIGTERM)
                _ = Darwin.kill(childPID, SIGKILL)
            }
        }

        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 32 * 1_024)
        while ProcessInfo.processInfo.systemUptime < deadline {
            rememberProcessGroup()
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!, buffer.count)
            }
            if count > 0 {
                guard count <= maximumBytes - data.count else { return nil }
                data.append(contentsOf: bytes.prefix(count))
                continue
            }
            if count == 0 {
                // EOF is required: a child that emits partial JSON then hangs
                // must remain subject to the same absolute deadline.
                return HomeSnapshotStore.taskBoard(data: data)
            }
            if errno == EINTR { continue }
            guard errno == EAGAIN || errno == EWOULDBLOCK else { return nil }

            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            var pending = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let milliseconds = Int32(max(1, min(50, remaining * 1_000)))
            let result = Darwin.poll(&pending, 1, milliseconds)
            if result < 0, errno != EINTR { return nil }
            if pending.revents & Int16(POLLNVAL) != 0 { return nil }
        }
        return nil
    }

    /// Called only by the early CLI branch, before UI/services are initialized.
    static func runChild(scope: RuntimeScope) -> Int32 {
        // Refuse to spawn SQLite descendants if the caller could not isolate us.
        guard getpgrp() == getpid() else { return 2 }
        let environment = ProcessInfo.processInfo.environment
        guard let identifier = environment[timeZoneEnvironmentKey],
              identifier.utf8.count <= 128, TimeZone(identifier: identifier) != nil,
              let timestamp = environment[nowEnvironmentKey].flatMap(Double.init),
              timestamp.isFinite else { return 2 }
        let preference = StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: identifier)
        let context = RuntimeLoadContext.live(
            now: Date(timeIntervalSince1970: timestamp), statisticsPreference: preference
        )
        guard let provider = RuntimeProviderRegistry().provider(for: scope),
              let board = provider.loadTaskBoard(context: context),
              let data = HomeSnapshotStore.taskData(board: board),
              data.count <= maximumBytes else { return 1 }
        do {
            try FileHandle.standardOutput.write(contentsOf: data)
            return 0
        } catch {
            return 1
        }
    }

    static func selfTest() -> Bool {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("codexu-home-task-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let now = Date()
            let context = RuntimeLoadContext(
                now: now,
                homeDirectory: root.appendingPathComponent("empty-home", isDirectory: true),
                cacheDirectory: root.appendingPathComponent("empty-cache", isDirectory: true),
                statistics: StatisticsContext(preference: .default, now: now)
            )
            let emptyStart = ProcessInfo.processInfo.systemUptime
            expect(read(scope: .codex, context: context) == nil, "real task helper must keep missing source unavailable")
            expect(ProcessInfo.processInfo.systemUptime - emptyStart < 3.5, "real helper must respect the task deadline")

            // This controlled fixture isolates its own process group and creates
            // a TERM-resistant descendant, exercising timeout cleanup directly.
            let helper = root.appendingPathComponent("fixture-task-helper")
            let silentScript = #"""
            #!/usr/bin/perl
            use strict;
            use POSIX qw(setpgid);
            setpgid(0, 0) == 0 or exit 2;
            $SIG{TERM} = 'IGNORE';
            my $child = fork();
            defined($child) or exit 2;
            if ($child == 0) { sleep 60; exit 0; }
            open(my $marker, '>', "$0.pids") or exit 2;
            print $marker "$$ $child";
            close($marker);
            sleep 60;
            """#
            try Data(silentScript.utf8).write(to: helper)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let timeoutStart = ProcessInfo.processInfo.systemUptime
            let silentResult = read(scope: .codex, context: context, executableURL: helper)
            let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStart
            expect(silentResult == nil, "a stuck task helper must return unavailable")
            expect(elapsed >= 2.8 && elapsed < 3.5, "a stuck task helper must end at the single three-second deadline")
            let marker = try String(contentsOfFile: helper.path + ".pids", encoding: .utf8)
            let pids = marker.split(separator: " ").compactMap { Int32($0) }
            if pids.count == 2 {
                let group = pids[0]
                let descendant = pids[1]
                defer {
                    // If the assertion fails, clean only the fixture's verified group.
                    if getpgid(descendant) == group { _ = Darwin.kill(-group, SIGKILL) }
                }
                let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 1
                while Darwin.kill(descendant, 0) == 0,
                      ProcessInfo.processInfo.systemUptime < cleanupDeadline {
                    usleep(10_000)
                }
                expect(Darwin.kill(descendant, 0) != 0 && errno == ESRCH,
                       "task timeout must clean the helper's TERM-resistant descendant")
            } else {
                failures.append("timeout fixture did not report its own process IDs")
            }

            let board = TaskBoard(refreshedAt: now, columns: [
                TaskColumn(id: .active, title: "Active", count: 40, items: [
                    TaskItem(id: "fixture", code: "T", title: "Task", detail: "", chip: "",
                             updatedAt: now, tokens: nil, kind: .active,
                             sourceKind: .codexThread, displayState: .recentlyActive, stateBasis: .activityWindow)
                ])
            ])
            guard let payload = HomeSnapshotStore.taskData(board: board) else {
                failures.append("bounded task fixture could not be encoded")
                failures.forEach { print("Home task reader self-test failed: \($0)") }
                return false
            }
            try payload.write(to: URL(fileURLWithPath: helper.path + ".data"))
            try Data("#!/bin/sh\nexec /bin/cat \"$0.data\"\n".utf8).write(to: helper)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let retryStart = ProcessInfo.processInfo.systemUptime
            let retried = read(scope: .codex, context: context, executableURL: helper)
            expect(retried?.columns.first?.count == 40 && retried?.columns.first?.items.count == 1,
                   "a new read after timeout must succeed and preserve count independently of displayed cards")
            expect(ProcessInfo.processInfo.systemUptime - retryStart < 2, "a retry must not wait for the previous helper")
        } catch {
            failures.append("fixture failed: \(error)")
        }
        if failures.isEmpty {
            print("Home task reader self-test passed: real child, bounded timeout, descendant cleanup, retry")
            return true
        }
        failures.forEach { print("Home task reader self-test failed: \($0)") }
        return false
    }
}

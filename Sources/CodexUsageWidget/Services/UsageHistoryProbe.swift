import Foundation

/// Exercises the same service used by the installed app. Outputs totals and timing only; never
/// source paths, thread titles, prompt text or account details. The cache override isolates runs.
enum UsageHistoryProbe {
    /// Offline maintenance of derived report output only. The writer lock excludes a running app.
    static func maintainReports() -> Bool {
        let context = RuntimeLoadContext.live(statisticsPreference: StatisticsTimeZonePreferenceStore.load())
        let directory = UsageHistoryService.indexDirectory(context: context)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.sqlite").path) else {
            print("history maintenance: no existing index")
            return false
        }
        let started = ProcessInfo.processInfo.systemUptime
        let timeout = Double(ProcessInfo.processInfo.environment["CODEXU_HISTORY_PROBE_TIMEOUT"] ?? "600") ?? 600
        let now = Date()
        do {
            let store = try UsageIndexStore(directory: directory)
            let before = try store.scalar("SELECT count(*) FROM report_build") ?? 0
            var rows = 0
            var finished = false
            while ProcessInfo.processInfo.systemUptime-started < timeout {
                let removed = try store.collectReportGarbage(now: now)
                if removed == 0 { finished = true; break }
                rows += removed
            }
            try store.checkpointWAL()
            let record: [String: Any] = ["complete": finished, "removedRows": rows,
                "reportsBefore": before, "reportsAfter": try store.scalar("SELECT count(*) FROM report_build") ?? 0,
                "freePages": try store.scalar("PRAGMA freelist_count") ?? 0,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime-started]
            let data = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
            return finished
        } catch {
            print("history maintenance failed: \(error as? UsageIndexError ?? .databaseFailure)")
            return false
        }
    }

    static func run() -> Bool {
        let context = RuntimeLoadContext.live(statisticsPreference: StatisticsTimeZonePreferenceStore.load())
        let started = ProcessInfo.processInfo.systemUptime
        let timeout = Double(ProcessInfo.processInfo.environment["CODEXU_HISTORY_PROBE_TIMEOUT"] ?? "1800") ?? 1800
        let lock = NSLock()
        var complete = Set<String>()
        var latest: [String: [String: Any]] = [:]
        var lastPrint: TimeInterval = -10
        UsageHistoryService.shared.subscribe(context: context) { value in
            lock.lock(); defer { lock.unlock() }
            let runtime = value.scope.runtimeId
            // A cached complete cut predating this run does not certify a fresh backfill.
            if value.complete && value.observedAt >= context.now { complete.insert(runtime) }
            latest[runtime] = ["complete": value.complete, "details": value.hasDetails,
                "tokens": value.local.lifetimeTokens, "todayTokens": value.local.todayTokens,
                "sevenDayTokens": value.local.sevenDayTokens, "sources": value.local.threadCount,
                "revision": value.revision, "fresh": value.observedAt >= context.now]
            let elapsed = ProcessInfo.processInfo.systemUptime-started
            if elapsed-lastPrint>=2 || complete.count==2 {
                lastPrint = elapsed
                if let data = try? JSONSerialization.data(withJSONObject: ["elapsedSeconds":elapsed,"runtimes":latest],options:[.sortedKeys]) {
                    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
                }
            }
        }
        var succeeded = false
        while ProcessInfo.processInfo.systemUptime-started<timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            lock.lock(); succeeded = complete.count==2; lock.unlock()
            if succeeded { break }
        }
        UsageHistoryService.shared.stop()
        // Permit the service to enqueue its drain; process exit closes any remaining helper handles.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if !succeeded { FileHandle.standardError.write(Data("history probe: timed out before complete coverage\n".utf8)) }
        return succeeded
    }
}

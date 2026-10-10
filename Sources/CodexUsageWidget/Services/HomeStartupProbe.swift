import Foundation

/// Read-only live-source diagnostic. Times model availability, not native drawing.
enum HomeStartupProbe {
    static func run() -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        let context = RuntimeLoadContext.live(statisticsPreference: StatisticsTimeZonePreferenceStore.load())
        var loaders = HomeLoaders.live
        loaders.save = { _, _ in }
        let coordinator = UsageRefreshCoordinator(loaders: loaders, historyDelay: 10)
        var latest: HomePresentation?
        var firstDataSeconds: Double?
        coordinator.onChange = { value in
            latest = value
            if firstDataSeconds == nil, value.statuses.values.contains(where: { $0.observedAt != nil }) {
                firstDataSeconds = ProcessInfo.processInfo.systemUptime - start
            }
        }
        coordinator.start(context: context)
        while ProcessInfo.processInfo.systemUptime - start < 4.05 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        coordinator.stop()
        guard let latest else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let waiting = latest.statuses.values.filter(\.isWaiting).count
        let report: [String: Any] = [
            "modelReadyWithinFiveSeconds": elapsed < 5 && waiting == 0,
            "elapsedSeconds": elapsed,
            "firstDataSeconds": firstDataSeconds.map { $0 as Any } ?? NSNull(),
            "waitingSections": waiting,
            "leadershipScore": latest.snapshot.leadership.defaultReport?.score as Any? ?? NSNull(),
            "leadershipAgents": latest.snapshot.leadership.defaultReport?.agentCount as Any? ?? NSNull(),
            "nativeDrawingMeasured": false,
            "runtimes": latest.snapshot.runtimes.map { runtime -> [String: Any] in
                ["runtime": runtime.scope.runtimeId,
                 "quotaAvailable": runtime.snapshot.quotaReadSucceeded,
                 "localSummaryAvailable": runtime.snapshot.local != nil,
                 "lifetimeTokens": runtime.snapshot.local?.detailedUsage?.lifetime.tokens.totalTokens as Any? ?? NSNull(),
                 "tasksAvailable": runtime.snapshot.taskBoard != nil]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return false }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        return elapsed < 5 && waiting == 0
    }
}

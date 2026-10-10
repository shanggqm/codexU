import Foundation

enum HomeSnapshotStoreSelfTest {
    static func run() -> Bool {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("codexu-home-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        let store = HomeSnapshotStore()
        let now = Date(timeIntervalSince1970: 1_788_998_400)
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        func context(_ name: String, date: Date? = nil, zone: String = "UTC", home: String = "home") -> RuntimeLoadContext {
            let date = date ?? now
            return RuntimeLoadContext(
                now: date,
                homeDirectory: root.appendingPathComponent(home, isDirectory: true),
                cacheDirectory: root.appendingPathComponent(name, isDirectory: true),
                statistics: StatisticsContext(
                    preference: StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: zone), now: date
                )
            )
        }
        func file(_ context: RuntimeLoadContext, previous: Bool = false) -> URL {
            context.cacheDirectory.appendingPathComponent(
                previous ? HomeSnapshotStore.previousFileName : HomeSnapshotStore.currentFileName
            )
        }

        do {
            let originalContext = context("round-trip")
            expect(store.read(context: originalContext) == nil, "missing snapshot should be absent")
            let original = fixture(context: originalContext)
            expect(store.write(original, context: originalContext), "valid summary should save")
            let restored = store.read(context: originalContext)
            expect(restored?.refreshedAt == original.refreshedAt, "restore must keep the observation time")
            expect(restored?.statisticsIdentity.now == original.statisticsIdentity.now, "restore must keep the statistics window")
            expect(restored?.leadership.defaultReport?.score == 73,
                   "the leadership summary should restore its previously observed score")
            expect(restored?.leadership.refreshedAt == original.leadership.refreshedAt,
                   "leadership should keep its own observation time")
            expect(restored?.leadership.defaultReport?.dailyPoints.isEmpty == true
                    && restored?.leadership.defaultReport?.projects.isEmpty == true,
                   "leadership details must not enter the home display cache")
            expect(restored?.runtime(for: .codex)?.snapshot.local?.detailedUsage == original.runtime(for: .codex)?.snapshot.local?.detailedUsage,
                   "real today and lifetime values should survive restart")
            expect(restored?.runtime(for: .codex)?.snapshot.fiveHourQuota == nil,
                   "an unverified account must not regain a current quota from disk")
            expect(restored?.runtime(for: .codex)?.snapshot.account == nil, "account information should not persist")
            let board = restored?.runtime(for: .codex)?.snapshot.taskBoard
            expect(board?.totalCount == 400, "truncating cards must not truncate the known task count")
            expect(board?.columns.flatMap(\.items).count == 24, "stored cards should fit the fixed home budget")
            expect(board?.columns.flatMap(\.items).allSatisfy {
                !$0.isRealtime && $0.runtimeState == .recorded && $0.displayState == .unknown
                    && $0.detail == "上次记录" && $0.nextRunAt == nil && $0.rawStatus == nil
            } == true, "old running and scheduled states must be visibly historical")
            expect(board?.refreshedAt == original.runtime(for: .codex)?.snapshot.taskBoard?.refreshedAt,
                   "task board must keep its own observation time")
            let permission = try manager.attributesOfItem(atPath: file(originalContext).path)[.posixPermissions] as? NSNumber
            expect(permission?.intValue == 0o600, "snapshot must be private to its owner")
            let data = try Data(contentsOf: file(originalContext))
            expect(data.count <= HomeSnapshotStore.maximumBytes, "encoded file must fit the hard byte budget")
            let json = String(decoding: data, as: UTF8.self)
            expect(!json.contains("sensitive task detail") && !json.contains("sensitive raw status")
                    && !json.contains("secret-project-path") && !json.contains(root.path),
                   "detail, raw status, historical paths and source paths must not be persisted")

            expect(store.read(context: context("round-trip", date: now.addingTimeInterval(86_400))) == nil,
                   "yesterday must not be shown as today")
            expect(store.read(context: context("round-trip", zone: "Asia/Shanghai")) == nil,
                   "a changed time zone must invalidate day-based statistics")
            expect(store.read(context: context("round-trip", home: "another-home")) == nil,
                   "a different local source must not restore the previous source")
            expect(!store.write(original, context: context("round-trip", date: now.addingTimeInterval(86_400))),
                   "a late result must not save old statistics under a new day")

            let largeContext = context("large-history")
            expect(store.write(fixture(context: largeContext, historyCount: 100_000), context: largeContext),
                   "large historical collections should not enter the home cache")
            let largeData = try Data(contentsOf: file(largeContext))
            expect(largeData.count == data.count, "home bytes must stay constant when history grows to 100,000 items")
            expect(store.read(context: largeContext)?.aggregate.local?.recentThreads.isEmpty == true,
                   "restore should not reconstruct full historical collections")

            let latestContext = context("round-trip", date: now.addingTimeInterval(10))
            let latest = fixture(context: latestContext)
            expect(store.write(latest, context: latestContext), "second valid save should succeed")
            expect(!store.write(original, context: originalContext), "an older completion must not overwrite a newer snapshot")
            let archivedBytes = try Data(contentsOf: file(latestContext, previous: true))
            expect(archivedBytes == data, "backup should be the previous valid snapshot")
            try Data("truncated-json".utf8).write(to: file(latestContext), options: .atomic)
            expect(store.read(context: latestContext)?.refreshedAt == original.refreshedAt,
                   "a corrupt current snapshot should recover the valid backup")
            try Data(repeating: 0, count: HomeSnapshotStore.maximumBytes + 1)
                .write(to: file(latestContext), options: .atomic)
            expect(store.read(context: latestContext)?.refreshedAt == original.refreshedAt,
                   "oversized current files should be rejected before decoding and use the backup")

            let partialVersionContext = context("unsafe-v1")
            expect(store.write(fixture(context: partialVersionContext), context: partialVersionContext), "v1 setup")
            var unsafe = try JSONSerialization.jsonObject(with: Data(contentsOf: file(partialVersionContext))) as! [String: Any]
            unsafe["version"] = 1
            try JSONSerialization.data(withJSONObject: unsafe).write(to: file(partialVersionContext))
            expect(store.read(context: partialVersionContext) == nil,
                   "v1 summaries without completeness guarantees must never restore")

            let futureContext = context("future-schema")
            expect(store.write(fixture(context: futureContext), context: futureContext), "future-schema setup")
            var future = try JSONSerialization.jsonObject(with: Data(contentsOf: file(futureContext))) as! [String: Any]
            future["version"] = 999
            let futureBytes = try JSONSerialization.data(withJSONObject: future, options: .sortedKeys)
            try futureBytes.write(to: file(futureContext), options: .atomic)
            expect(store.read(context: futureContext) == nil, "an unsupported schema must not restore")
            expect(!store.write(fixture(context: futureContext), context: futureContext),
                   "an older application must not overwrite or move a future schema")
            let unchangedFuture = try Data(contentsOf: file(futureContext))
            expect(unchangedFuture == futureBytes, "future-schema bytes must remain untouched")
            expect(!manager.fileExists(atPath: file(futureContext, previous: true).path),
                   "a future schema must not be moved into the backup")

            let malformedContext = context("invalid-fields")
            expect(store.write(fixture(context: malformedContext), context: malformedContext), "field-validation setup")
            var malformed = try JSONSerialization.jsonObject(with: Data(contentsOf: file(malformedContext))) as! [String: Any]
            var runtimes = malformed["runtimes"] as! [[String: Any]]
            var local = runtimes[0]["local"] as! [String: Any]
            local["todayTokens"] = NSNumber(value: Int64.max)
            runtimes[0]["local"] = local
            malformed["runtimes"] = runtimes
            try JSONSerialization.data(withJSONObject: malformed).write(to: file(malformedContext), options: .atomic)
            expect(store.read(context: malformedContext) == nil,
                   "corrupted token counters must not overflow the restored aggregate")

            let symlinkContext = context("symlink")
            try manager.createDirectory(at: symlinkContext.cacheDirectory, withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: file(symlinkContext), withDestinationURL: file(largeContext))
            expect(store.read(context: symlinkContext) == nil, "snapshot reads must not follow substituted symlinks")
        } catch {
            failures.append("fixture I/O failed: \(error)")
        }

        if failures.isEmpty {
            print("Home snapshot store self-test passed")
            return true
        }
        failures.forEach { print("Home snapshot store self-test failed: \($0)") }
        return false
    }

    private static func fixture(context: RuntimeLoadContext, historyCount: Int = 0) -> MultiRuntimeUsageSnapshot {
        let now = context.now
        let usage = PricedTokenUsage(
            tokens: TokenBreakdown(inputTokens: 1_000, cachedInputTokens: 200,
                                   outputTokens: 500, reasoningOutputTokens: 100, totalTokens: 1_500),
            estimatedCostUSD: 0.02
        )
        let local = LocalUsage(
            lifetimeTokens: 6_000, todayTokens: 1_500, sevenDayTokens: 3_000, threadCount: 100,
            lastUpdatedAt: now.addingTimeInterval(-20), dailyBuckets: [],
            recentThreads: Array(repeating: LocalThread(
                id: "historical", title: "historical thread", tokens: 42, updatedAt: now,
                model: nil, cwd: "secret-project-path", archived: false
            ), count: historyCount),
            detailedUsage: DetailedUsage(today: usage, sevenDay: usage, month: usage, lifetime: usage,
                                         parsedFileCount: 100, tokenEventCount: 800),
            usageTrend: nil, inferencePerformance: nil, projectBoard: nil, toolUsages: [], skillUsages: []
        )
        let kinds: [TaskColumnKind] = [.active, .pending, .scheduled, .done]
        let board = TaskBoard(refreshedAt: now.addingTimeInterval(-5), columns: kinds.map { kind in
            TaskColumn(id: kind, title: kind.rawValue, count: 100, items: (0..<100).map { index in
                TaskItem(id: "\(kind.rawValue)-\(index)", code: "CODEX", title: String(repeating: "任务", count: 300),
                         detail: "sensitive task detail", chip: "running", updatedAt: now, tokens: 100,
                         kind: kind, threadID: "thread-\(index)", runtimeState: .running, isRealtime: true,
                         sourceKind: .codexThread, displayState: .running, stateBasis: .activityWindow,
                         rawStatus: "sensitive raw status", nextRunAt: now.addingTimeInterval(60))
            })
        })
        let snapshot = UsageSnapshot(
            refreshedAt: now, account: AccountInfo(type: "chatgpt", planType: "pro", emailPresent: true),
            limitId: "test", limitName: "test", quotaReadSucceeded: true,
            fiveHourQuota: RateWindow(usedPercent: 42, windowDurationMins: 300, resetsAt: now.addingTimeInterval(30)),
            sevenDayQuota: nil, monthlyQuota: nil, credits: nil, cloudLifetimeTokens: 800,
            local: local, taskBoard: board, messages: []
        )
        let runtime = RuntimeUsageSnapshot(scope: .codex, snapshot: snapshot, status: .available,
                                           quotaSourceLabel: "official", usageSourceLabel: "local")
        let report = LeadershipReport(
            period: .twentyEightDays, score: 73, coreScore: 73,
            title: LeadershipTitle(level: 5, name: "硅基统帅", lowerBound: 65, upperBound: 79),
            dimensions: [LeadershipDimension(kind: .span, score: 73, confidence: 0.9, summaryValue: 8)],
            maturity: 0.9, evidenceCoverage: 0.9, activeDayCount: 8, agentCount: 12,
            aiHours: 10, autonomousHours: 4, averageParallelism: 2, peakConcurrency: 3,
            projectCount: 1,
            dailyPoints: [LeadershipDayPoint(day: now, agentCount: 12, aiHours: 10, peakConcurrency: 3)],
            projects: [LeadershipProjectContribution(projectID: "secret-project-path", projectName: "project",
                                                      agentCount: 12, aiHours: 10, autonomousHours: 4)]
        )
        return MultiRuntimeUsageSnapshot(
            refreshedAt: now, runtimes: [runtime], aggregate: snapshot,
            leadership: LeadershipDashboardSnapshot(modelVersion: LeadershipScoreModel.version,
                                                    refreshedAt: now.addingTimeInterval(-10), reports: [report]),
            statisticsIdentity: StatisticsIdentity(preference: context.statistics.preference,
                                                   resolvedIdentifier: context.statistics.resolvedIdentifier,
                                                   generation: 12, now: now)
        )
    }
}

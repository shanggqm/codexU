import Foundation

/// Exercises the actual publishing coordinator with deliberately blocked data sources.
/// This verifies data and waiting-state contracts; native window drawing is a separate check.
enum HomeStartupSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        func status(_ value: HomePresentation?, _ scope: RuntimeScope?, _ kind: HomeDataKind) -> HomeLoadStatus? {
            value?.statuses[HomeDataKey(scope: scope, kind: kind)]
        }

        let context = makeContext()

        // No cache and unresponsive sources must not keep foreground waiting open.
        do {
            let blocked = SourceGate()
            var loaders = emptyLoaders()
            loaders.quota = { _, _ in blocked.wait(); return nil }
            loaders.tasks = { _, _ in blocked.wait(); return nil }
            loaders.local = { _, _ in blocked.wait(); return nil }
            loaders.leadership = { _ in blocked.wait(); return .empty }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.08, historyDelay: 0.2)
            var latest: HomePresentation?
            coordinator.onChange = { latest = $0 }
            let started = ProcessInfo.processInfo.systemUptime
            coordinator.start(context: context)
            defer { coordinator.stop(); blocked.release() }
            expect(waitUntil { latest?.isRefreshing == false && ProcessInfo.processInfo.systemUptime - started >= 0.08 },
                   "cold start must end foreground waiting while sources remain blocked")
            expect(ProcessInfo.processInfo.systemUptime - started < 0.8, "foreground deadline must not join blocked workers")
            for scope in RuntimeScope.allCases {
                expect(status(latest, scope, .quota)?.phase == .unavailable, "cold start must explain missing \(scope) quota")
                expect(status(latest, scope, .tasks)?.phase == .unavailable, "cold start must explain missing \(scope) tasks")
                expect(latest?.snapshot.runtime(for: scope)?.snapshot.local == nil, "missing local data must stay nil, not a zero result")
            }
        }

        // Restoring real values is required: a fast all-unavailable page is not enough.
        do {
            let blocked = SourceGate()
            let observedAt = context.now.addingTimeInterval(-180)
            let cached = makeSnapshot(context: context, runtimes: [makeRuntime(.codex, observedAt: observedAt, tokens: 431)])
            var loaders = emptyLoaders()
            loaders.restore = { _ in cached }
            loaders.quota = { _, _ in blocked.wait(); return nil }
            loaders.local = { _, _ in blocked.wait(); return nil }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.08, historyDelay: 0.12)
            var latest: HomePresentation?
            coordinator.onChange = { latest = $0 }
            coordinator.start(context: context)
            defer { coordinator.stop(); blocked.release() }
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 431 },
                   "cold restart must recover actual cached homepage values")
            expect(status(latest, .codex, .local)?.observedAt == observedAt,
                   "cache restoration must retain the actual observation time")
            expect(status(latest, .codex, .local)?.phase == .cached,
                   "restored statistics must be identified as cached")
            expect(status(latest, .codex, .local)?.hasDetails == false,
                   "a summary-only disk snapshot must not claim historical details are available")
            let partialLocal = makeRuntime(.codex, observedAt: context.now, tokens: 12).snapshot.local!
            let previousLeadership = latest?.snapshot.leadership
            var partial = UsageArchivePresentation(local: partialLocal, observedAt: context.now, complete: false, revision: 1)
            partial.leadership = .empty
            coordinator.acceptHistoryArchive(partial)
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 431,
                   "partial archive must not replace complete cached totals")
            expect(status(latest, .codex, .local)?.observedAt == observedAt,
                   "partial archive must not claim a new complete observation time")
            expect(latest?.snapshot.leadership.defaultReport?.score == previousLeadership?.defaultReport?.score,
                   "partial leadership must not replace the previous score")
            coordinator.acceptHistoryFailure(.diskFull)
            expect(status(latest, .codex, .local)?.historyError == .diskFull,
                   "index storage failure must be visible in home status")
            expect(status(latest, .codex, .local)?.label(.zh, kind: .local).contains("空间不足") == true,
                   "storage failures must not appear as endless preparation")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 431,
                   "history failure must preserve complete cached totals")
            let recovered = UsageArchivePresentation(local: partial.local, observedAt: context.now, complete: true, revision: 2)
            coordinator.acceptHistoryArchive(recovered)
            expect(status(latest, .codex, .local)?.historyError == nil,
                   "a successful complete archive must clear the history error")
            coordinator.acceptHistoryArchive(UsageArchivePresentation(local: makeRuntime(.codex, observedAt: observedAt, tokens: 431).snapshot.local!,
                observedAt: observedAt, complete: true, revision: 3))
            expect(waitUntil { latest?.isRefreshing == false }, "slow quota must not hide a restored homepage")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 431,
                   "deadline must retain valid cached statistics")
        }

        // Full in-memory details remain visible during subsequent refreshes,
        // including a deadline or failed read, until the statistics context changes.
        do {
            let blocked = SourceGate()
            let localCalls = SourceCounter()
            var loaders = emptyLoaders()
            loaders.local = { scope, context in
                if localCalls.next(scope: scope) > 1 {
                    blocked.wait()
                    return nil
                }
                return makeRuntime(scope, observedAt: context.now, tokens: 451)
            }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.08, historyDelay: 0.01)
            var latest: HomePresentation?
            coordinator.onChange = { latest = $0 }
            coordinator.start(context: context)
            defer { coordinator.stop(); blocked.release() }
            expect(waitUntil {
                status(latest, .codex, .local)?.phase == .ready
                    && status(latest, .claudeCode, .local)?.phase == .ready
                    && status(latest, nil, .leadership)?.phase == .unavailable
            }, "details retention test must finish the initial history pass")
            expect(status(latest, .codex, .local)?.hasDetails == true,
                   "a completed full local read must make historical details available")

            coordinator.refresh(context: context)
            expect(status(latest, .codex, .local)?.phase == .refreshing
                    && status(latest, .codex, .local)?.hasDetails == true,
                   "refreshing must retain completed in-memory historical details")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 451,
                   "refreshing must not clear the existing local values")
            expect(waitUntil { blocked.callCount > 0 }, "details retention test must block a subsequent history read")
            expect(waitUntil { status(latest, .codex, .local)?.phase == .cached },
                   "the foreground deadline must end the update without waiting for history")
            expect(status(latest, .codex, .local)?.hasDetails == true
                    && latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 451,
                   "deadline expiry must preserve both details availability and local values")

            blocked.release()
            expect(waitUntil { status(latest, nil, .leadership)?.phase == .unavailable },
                   "the failed history pass must finish after its source is released")
            expect(status(latest, .codex, .local)?.hasDetails == true
                    && status(latest, .codex, .local)?.phase == .cached
                    && latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 451,
                   "a failed subsequent read must not erase previously completed details")

            coordinator.refresh(context: makeContext(zone: "Asia/Shanghai", now: context.now))
            expect(status(latest, .codex, .local)?.hasDetails == false
                    && latest?.snapshot.runtime(for: .codex)?.snapshot.local == nil,
                   "a changed statistics context must clear obsolete details and their values")
        }

        // Each runtime/domain must publish without joining the others; valid late replies still apply.
        do {
            let slowQuota = SourceGate()
            let slowHistory = SourceGate()
            var loaders = emptyLoaders()
            loaders.quota = { scope, context in
                if scope == .claudeCode { slowQuota.wait() }
                return makeRuntime(scope, observedAt: context.now, usedPercent: scope == .codex ? 17 : 63)
            }
            loaders.tasks = { scope, context in makeBoard(scope: scope, now: context.now, count: 1) }
            loaders.local = { scope, context in
                slowHistory.wait()
                return makeRuntime(scope, observedAt: context.now, tokens: scope == .codex ? 111 : 222)
            }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.1, historyDelay: 0.01)
            var latest: HomePresentation?
            coordinator.onChange = { latest = $0 }
            coordinator.start(context: context)
            defer { coordinator.stop(); slowQuota.release(); slowHistory.release() }
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.fiveHourQuota?.usedPercent == 17 },
                   "Codex quota must publish while Claude quota and history are blocked")
            expect(latest?.snapshot.runtime(for: .claudeCode)?.snapshot.fiveHourQuota == nil,
                   "an unresolved runtime must not inherit the other runtime's quota")
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.taskBoard?.totalCount == 1 },
                   "tasks must publish while quota/history remain blocked")
            expect(waitUntil { latest?.isRefreshing == false }, "a blocked runtime must respect the foreground deadline")
            slowQuota.release()
            expect(waitUntil { latest?.snapshot.runtime(for: .claudeCode)?.snapshot.fiveHourQuota?.usedPercent == 63 },
                   "a matching quota reply after the deadline must update the page")
            slowHistory.release()
            expect(waitUntil { latest?.snapshot.runtime(for: .claudeCode)?.snapshot.local?.todayTokens == 222 },
                   "background local results must eventually publish")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 111,
                   "one runtime's local result must not replace the other runtime")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.fiveHourQuota?.usedPercent == 17,
                   "local statistics must preserve already published quota")
            expect(latest?.snapshot.runtime(for: .claudeCode)?.snapshot.fiveHourQuota?.usedPercent == 63,
                   "local statistics must preserve a late quota result")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.taskBoard?.totalCount == 1,
                   "local statistics must preserve independently loaded tasks")
        }

        // Timezone changes must reject the old local generation even if its parser cannot cancel.
        do {
            let oldHistory = SourceGate()
            let firstContext = makeContext(zone: "Asia/Shanghai")
            let nextContext = makeContext(zone: "America/Los_Angeles", now: firstContext.now)
            var loaders = emptyLoaders()
            loaders.quota = { scope, context in makeRuntime(scope, observedAt: context.now, usedPercent: 29) }
            loaders.local = { scope, context in
                if context.statistics.resolvedIdentifier == firstContext.statistics.resolvedIdentifier {
                    oldHistory.wait()
                    return makeRuntime(scope, observedAt: context.now, tokens: 999)
                }
                return makeRuntime(scope, observedAt: context.now, tokens: 73)
            }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.08, historyDelay: 0.01)
            var latest: HomePresentation?
            var switched = false
            var displayedObsoleteValue = false
            coordinator.onChange = { value in
                latest = value
                if switched && value.snapshot.runtimes.contains(where: { $0.snapshot.local?.todayTokens == 999 }) {
                    displayedObsoleteValue = true
                }
            }
            coordinator.start(context: firstContext)
            defer { coordinator.stop(); oldHistory.release() }
            expect(waitUntil { oldHistory.callCount > 0 }, "timezone test must actually have an old parser in flight")
            switched = true
            coordinator.refresh(context: nextContext)
            oldHistory.release()
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.local?.todayTokens == 73 },
                   "the new timezone must load after an obsolete worker finishes")
            expect(!displayedObsoleteValue, "a stale timezone reply must never briefly appear under today's label")
            expect(latest?.snapshot.statisticsIdentity.resolvedIdentifier == nextContext.statistics.resolvedIdentifier,
                   "published statistics must carry the current timezone")
            expect(latest?.snapshot.runtime(for: .codex)?.snapshot.fiveHourQuota?.usedPercent == 29,
                   "timezone changes must not erase valid quota")
        }

        // Explicit task refreshes must remain usable during an unresponsive full history pass.
        do {
            let blocked = SourceGate()
            let taskCalls = SourceCounter()
            var loaders = emptyLoaders()
            loaders.quota = { _, _ in blocked.wait(); return nil }
            loaders.local = { _, _ in blocked.wait(); return nil }
            loaders.tasks = { scope, context in
                let count = taskCalls.next(scope: scope)
                return makeBoard(scope: scope, now: context.now, count: count)
            }
            let coordinator = UsageRefreshCoordinator(loaders: loaders, foregroundDeadline: 0.08, historyDelay: 0.01)
            var latest: HomePresentation?
            coordinator.onChange = { latest = $0 }
            coordinator.start(context: context)
            defer { coordinator.stop(); blocked.release() }
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.taskBoard?.totalCount == 1 },
                   "initial task results need no history base board")
            coordinator.refreshTasks(scope: .codex)
            expect(waitUntil { latest?.snapshot.runtime(for: .codex)?.snapshot.taskBoard?.totalCount == 2 },
                   "manual task refresh must not wait for quota/history")
            coordinator.stop()
            let stoppedValue = latest
            blocked.release()
            pump(for: 0.03)
            expect(latest?.snapshot == stoppedValue?.snapshot,
                   "stopped coordinators must ignore callbacks from outstanding workers")
        }

        // A bounded page must keep visible live states working even when most
        // source records were not materialized. Only visible moves affect counts.
        do {
            let now = Date()
            func item(_ id: String, kind: TaskColumnKind) -> TaskItem {
                TaskItem(id: id, code: "T", title: "Visible task", detail: "", chip: "",
                         updatedAt: now.addingTimeInterval(-10_000), tokens: nil, kind: kind,
                         threadID: id, sourceKind: .codexThread,
                         displayState: .continueLater, stateBasis: .activityWindow)
            }
            let partial = TaskBoard(refreshedAt: now, columns: [
                TaskColumn(id: .active, title: "Active", count: 20, items: [item("visible-active", kind: .active)]),
                TaskColumn(id: .pending, title: "Pending", count: 10, items: [item("visible-pending", kind: .pending)])
            ])
            var records: [String: TaskLiveRecord] = [:]
            for index in 0..<1_000 {
                let id = "outside-page-\(index)"
                records[id] = TaskLiveRecord(threadID: id, name: nil, state: .running,
                                             updatedAt: now, turnID: nil, connectionMode: .sharedDaemon)
            }
            records["visible-active"] = TaskLiveRecord(threadID: "visible-active", name: nil, state: .waitingInput,
                                                        updatedAt: now, turnID: nil, connectionMode: .sharedDaemon)
            records["visible-pending"] = TaskLiveRecord(threadID: "visible-pending", name: nil, state: .running,
                                                         updatedAt: now, turnID: nil, connectionMode: .sharedDaemon)
            let updated = partial.mergingHomeTasks(CodexTaskLiveSnapshot(connectionMode: .sharedDaemon,
                                                                          records: records, refreshedAt: now))
            let active = updated.columns.first { $0.id == .active }
            let pending = updated.columns.first { $0.id == .pending }
            expect(active?.items.first(where: { $0.threadID == "visible-active" })?.runtimeState == .waitingInput,
                   "partial task pages must apply current state to an already visible card")
            expect(active?.items.contains(where: { $0.threadID == "visible-pending" && $0.isRealtime }) == true,
                   "a visible task that resumes must move to the active column")
            expect(active?.count == 21 && pending?.count == 9 && updated.totalCount == 30,
                   "visible task moves must preserve each column's unmaterialized count and the full total")
            expect(updated.columns.flatMap(\.items).allSatisfy { !$0.id.hasPrefix("live-outside-page") },
                   "partial task pages must not double-count live IDs from unmaterialized records")
            expect(updated.columns.allSatisfy { $0.items.count <= 6 },
                   "live updates must preserve the six-card column limit")
        }

        if failures.isEmpty {
            print("Home startup self-test passed: bounded foreground waiting, real cache restore, independent data, late replies, timezone, tasks")
            return true
        }
        failures.forEach { print("Home startup self-test failed: \($0)") }
        return false
    }

    private static func emptyLoaders() -> HomeLoaders {
        HomeLoaders(
            restore: { _ in nil },
            quota: { _, _ in nil },
            tasks: { _, _ in nil },
            local: { _, _ in nil },
            leadership: { _ in .empty },
            save: { _, _ in }
        )
    }

    private static func makeContext(zone: String = "UTC", now: Date = Date()) -> RuntimeLoadContext {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codexu-home-fixture", isDirectory: true)
        return RuntimeLoadContext(
            now: now,
            homeDirectory: root,
            cacheDirectory: root,
            statistics: StatisticsContext(
                preference: StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: zone),
                now: now
            )
        )
    }

    private static func makeRuntime(
        _ scope: RuntimeScope,
        observedAt: Date,
        usedPercent: Double? = nil,
        tokens: Int64? = nil
    ) -> RuntimeUsageSnapshot {
        let local = tokens.map {
            LocalUsage(lifetimeTokens: $0 * 10, todayTokens: $0, sevenDayTokens: $0 * 7,
                       threadCount: 1, lastUpdatedAt: observedAt, dailyBuckets: [], recentThreads: [],
                       detailedUsage: nil, usageTrend: nil, inferencePerformance: nil, projectBoard: nil,
                       toolUsages: [], skillUsages: [])
        }
        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: UsageSnapshot(
                refreshedAt: observedAt, account: nil, limitId: nil, limitName: nil,
                quotaReadSucceeded: usedPercent != nil,
                fiveHourQuota: usedPercent.map { RateWindow(usedPercent: $0, windowDurationMins: 300, resetsAt: nil) },
                sevenDayQuota: nil, monthlyQuota: nil, credits: nil, cloudLifetimeTokens: nil,
                local: local, taskBoard: nil, messages: []
            ),
            status: usedPercent != nil ? .available : .localOnly,
            quotaSourceLabel: "fixture quota", usageSourceLabel: "fixture local"
        )
    }

    private static func makeSnapshot(context: RuntimeLoadContext, runtimes: [RuntimeUsageSnapshot]) -> MultiRuntimeUsageSnapshot {
        MultiRuntimeUsageSnapshot(
            refreshedAt: runtimes.first?.snapshot.refreshedAt ?? context.now,
            runtimes: runtimes, aggregate: AgentUsageAggregator().aggregate(runtimes, at: context.now),
            leadership: .empty,
            statisticsIdentity: StatisticsIdentity(preference: context.statistics.preference,
                                                   resolvedIdentifier: context.statistics.resolvedIdentifier,
                                                   generation: 0, now: context.now)
        )
    }

    private static func makeBoard(scope: RuntimeScope, now: Date, count: Int) -> TaskBoard {
        TaskBoard(refreshedAt: now, columns: [
            TaskColumn(id: .active, title: "Active", count: count, items: [
                TaskItem(id: "fixture-\(scope.rawValue)", code: "T", title: "Fixture task", detail: "",
                         chip: "", updatedAt: now, tokens: nil, kind: .active,
                         sourceKind: scope == .codex ? .codexThread : .claudeTask,
                         displayState: .running, stateBasis: .explicit)
            ])
        ])
    }

    @discardableResult
    private static func waitUntil(timeout: TimeInterval = 0.8, _ condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
        return condition()
    }

    private static func pump(for duration: TimeInterval) {
        let deadline = ProcessInfo.processInfo.systemUptime + duration
        _ = waitUntil(timeout: duration + 0.1) { ProcessInfo.processInfo.systemUptime >= deadline }
    }
}

private final class SourceGate {
    private let condition = NSCondition()
    private var released = false
    private var calls = 0

    var callCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return calls
    }

    func wait() {
        condition.lock()
        defer { condition.unlock() }
        calls += 1
        // A broken implementation must fail promptly instead of hanging the test process.
        let safetyDeadline = Date().addingTimeInterval(3)
        while !released, condition.wait(until: safetyDeadline) {}
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class SourceCounter {
    private let lock = NSLock()
    private var counts: [RuntimeScope: Int] = [:]

    func next(scope: RuntimeScope) -> Int {
        lock.lock()
        defer { lock.unlock() }
        counts[scope, default: 0] += 1
        return counts[scope]!
    }
}

import Foundation

struct HomeLoaders {
    var restore: (RuntimeLoadContext) -> MultiRuntimeUsageSnapshot?
    var quota: (RuntimeScope, RuntimeLoadContext) -> RuntimeUsageSnapshot?
    var tasks: (RuntimeScope, RuntimeLoadContext) -> TaskBoard?
    var local: (RuntimeScope, RuntimeLoadContext) -> RuntimeUsageSnapshot?
    var leadership: (RuntimeLoadContext) -> LeadershipDashboardSnapshot
    var save: (MultiRuntimeUsageSnapshot, RuntimeLoadContext) -> Void
    var usesHistoryIndex = false

    static var live: HomeLoaders {
        HomeLoaders(
            restore: { HomeSnapshotStore().read(context: $0) },
            quota: { MultiRuntimeUsageReader().loadQuota(scope: $0, context: $1) },
            tasks: { HomeTaskReader.read(scope: $0, context: $1) },
            local: { MultiRuntimeUsageReader().loadLocal(scope: $0, context: $1) },
            leadership: { LeadershipDataReader().load(context: $0) },
            save: { _ = HomeSnapshotStore().write($0, context: $1) }, usesHistoryIndex: true
        )
    }
}

// State is owned by the main queue. Each slow source has its own queue; history
// is single-flight and never owns a lock/queue required to display the home.
final class UsageRefreshCoordinator {
    var onChange: ((HomePresentation) -> Void)?
    private let loaders: HomeLoaders
    private let foregroundDeadline: TimeInterval
    private let historyDelay: TimeInterval
    private let restoreQueue = DispatchQueue(label: "codexU.home.restore", qos: .userInitiated)
    private let saveQueue = DispatchQueue(label: "codexU.home.save", qos: .utility)
    private let historyQueue = DispatchQueue(label: "codexU.home.history", qos: .background)
    private var context: RuntimeLoadContext?
    private var epoch: UInt64 = 0
    private var active = false
    private var restorationComplete = false
    private var statuses: [HomeDataKey: HomeLoadStatus] = [:]
    private var runtimes: [RuntimeScope: RuntimeUsageSnapshot] = [:]
    private var leadership: LeadershipDashboardSnapshot = .empty
    private var inFlight = Set<HomeDataKey>()
    private var fastRequestID: UInt64 = 0
    private var fastRequests: [HomeDataKey: UInt64] = [:]
    private var historyRunning = false
    private var historyRequested = false
    private var watchdog: DispatchWorkItem?
    private var historyStart: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?

    init(loaders: HomeLoaders = .live, foregroundDeadline: TimeInterval = 4,
         historyDelay: TimeInterval = 4.1) {
        self.loaders = loaders
        self.foregroundDeadline = foregroundDeadline
        self.historyDelay = historyDelay
    }

    func start(context: RuntimeLoadContext) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !active else { return }
        active = true
        self.context = context
        epoch &+= 1
        let restoreEpoch = epoch
        let restore = loaders.restore
        restoreQueue.async { [weak self] in
            let restored = restore(context)
            DispatchQueue.main.async {
                guard let self, self.active else { return }
                self.restorationComplete = true
                if self.epoch == restoreEpoch, let restored { self.restore(restored) }
                self.publish(save: true)
            }
        }
        refresh(context: context)
    }

    func stop() {
        active = false
        epoch &+= 1
        watchdog?.cancel()
        historyStart?.cancel()
        pendingSave?.cancel()
        if loaders.usesHistoryIndex { UsageHistoryService.shared.stop() }
        onChange = nil
    }

    func refresh(context: RuntimeLoadContext) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard active else { return }
        let previous = self.context
        let changed = previous.map { !sameStatistics($0, context) } ?? false
        self.context = context
        if changed {
            epoch &+= 1
            for scope in RuntimeScope.allCases {
                if let runtime = runtimes[scope] {
                    runtimes[scope] = runtimeWith(runtime, local: nil, taskBoard: nil)
                }
                statuses[.init(scope: scope, kind: .local)] = HomeLoadStatus()
                statuses[.init(scope: scope, kind: .tasks)] = HomeLoadStatus()
            }
            leadership = .empty
            statuses[.init(scope: nil, kind: .leadership)] = HomeLoadStatus()
        }
        // Repeated clicks never postpone an existing deadline or enqueue a
        // second expensive read behind the one already running.
        if watchdog == nil {
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, self.active else { return }
                for key in self.statuses.keys where self.statuses[key]?.isWaiting == true {
                    self.statuses[key]?.finish(at: nil)
                    if (key.kind == .local || key.kind == .leadership), self.statuses[key]?.observedAt == nil {
                        self.statuses[key]?.phase = .background
                    }
                }
                self.watchdog = nil
                self.publish()
            }
            watchdog = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + foregroundDeadline, execute: deadline)
        }
        for scope in RuntimeScope.allCases {
            launchFast(scope: scope, kind: .quota)
            launchFast(scope: scope, kind: .tasks)
            let key = HomeDataKey(scope: scope, kind: .local)
            if !historyRunning { statuses[key, default: HomeLoadStatus()].begin() }
        }
        let leaderKey = HomeDataKey(scope: nil, kind: .leadership)
        if !historyRunning { statuses[leaderKey, default: HomeLoadStatus()].begin() }
        if !historyRunning || changed { historyRequested = true }
        scheduleHistory()
        publish()
    }

    func refreshTasks(scope: RuntimeScope) {
        guard active else { return }
        launchFast(scope: scope, kind: .tasks)
    }

    private func sameStatistics(_ a: RuntimeLoadContext, _ b: RuntimeLoadContext) -> Bool {
        a.homeDirectory == b.homeDirectory
            && a.statistics.resolvedIdentifier == b.statistics.resolvedIdentifier
            && a.statistics.dayKey(for: a.now) == b.statistics.dayKey(for: b.now)
    }

    private func launchFast(scope: RuntimeScope, kind: HomeDataKind) {
        let key = HomeDataKey(scope: scope, kind: kind)
        guard let context, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        fastRequestID &+= 1
        let requestID = fastRequestID
        fastRequests[key] = requestID
        statuses[key, default: HomeLoadStatus()].begin()
        let requestEpoch = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + foregroundDeadline) { [weak self] in
            guard let self, self.active, self.epoch == requestEpoch,
                  self.fastRequests[key] == requestID, self.inFlight.contains(key) else { return }
            self.statuses[key]?.finish(at: nil)
            self.publish()
        }
        let loaders = loaders
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let quota = kind == .quota ? loaders.quota(scope, context) : nil
            let tasks = kind == .tasks ? loaders.tasks(scope, context) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(key)
                guard self.active else { return }
                guard requestEpoch == self.epoch else {
                    self.launchFast(scope: scope, kind: kind)
                    return
                }
                if kind == .quota { self.acceptQuota(quota, scope: scope) }
                else { self.acceptTasks(tasks, scope: scope) }
                self.publish(save: true)
            }
        }
    }

    private func acceptQuota(_ next: RuntimeUsageSnapshot?, scope: RuntimeScope) {
        let key = HomeDataKey(scope: scope, kind: .quota)
        guard let next else {
            statuses[key, default: HomeLoadStatus()].finish(at: nil)
            return
        }
        let old = runtimes[scope]
        // AccountInfo has no stable account ID. Never carry old quota windows
        // across a failed read: they cannot be safely attributed to this account.
        let value = UsageSnapshot(
            refreshedAt: old?.snapshot.refreshedAt ?? next.snapshot.refreshedAt,
            account: next.snapshot.account, limitId: next.snapshot.limitId, limitName: next.snapshot.limitName,
            quotaReadSucceeded: next.snapshot.quotaReadSucceeded,
            fiveHourQuota: next.snapshot.fiveHourQuota, sevenDayQuota: next.snapshot.sevenDayQuota,
            monthlyQuota: next.snapshot.monthlyQuota, credits: next.snapshot.credits,
            cloudLifetimeTokens: next.snapshot.cloudLifetimeTokens,
            local: old?.snapshot.local, taskBoard: old?.snapshot.taskBoard,
            messages: next.snapshot.messages
        )
        runtimes[scope] = RuntimeUsageSnapshot(
            scope: scope, snapshot: value,
            status: next.snapshot.quotaReadSucceeded ? next.status : (value.local == nil ? .unavailable : .localOnly),
            quotaSourceLabel: next.quotaSourceLabel, usageSourceLabel: old?.usageSourceLabel ?? next.usageSourceLabel
        )
        statuses[key] = HomeLoadStatus(phase: next.snapshot.quotaReadSucceeded ? (next.status == .stale ? .cached : .ready) : .unavailable,
                                      observedAt: next.snapshot.quotaReadSucceeded ? next.snapshot.refreshedAt : nil)
    }

    private func acceptTasks(_ board: TaskBoard?, scope: RuntimeScope) {
        let key = HomeDataKey(scope: scope, kind: .tasks)
        if let board {
            let old = runtimes[scope] ?? emptyRuntime(scope)
            runtimes[scope] = old.replacingTaskBoard(board)
        }
        statuses[key, default: HomeLoadStatus()].finish(at: board?.refreshedAt)
    }

    private func scheduleHistory() {
        guard historyRequested, !historyRunning, historyStart == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.historyStart = nil
            self?.startHistory()
        }
        historyStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + historyDelay, execute: work)
    }

    // Only complete archive cuts may replace last-known complete display data.
    func acceptHistoryFailure(_ error: UsageIndexError) {
        let keys = RuntimeScope.allCases.map { HomeDataKey(scope: $0, kind: .local) }
            + [HomeDataKey(scope: nil, kind: .leadership)]
        guard keys.contains(where: { statuses[$0]?.historyError != error }) else { return }
        for key in keys {
            statuses[key, default: HomeLoadStatus()].historyError = error
            statuses[key, default: HomeLoadStatus()].phase = .background
        }
        publish()
    }

    func acceptHistoryArchive(_ result: UsageArchivePresentation) {
        let scope = result.scope
        let key = HomeDataKey(scope: scope, kind: .local)
        if result.complete {
            let old = runtimes[scope] ?? emptyRuntime(scope)
            let local = result.local.preservingDetails(from: old.snapshot.local, when: !result.hasDetails)
            runtimes[scope] = runtimeWith(old, local: local, taskBoard: old.snapshot.taskBoard, observedAt: result.observedAt)
            statuses[key] = HomeLoadStatus(phase: .ready, observedAt: result.observedAt,
                hasDetails: result.hasDetails || statuses[key]?.hasDetails == true)
        } else {
            statuses[key, default: HomeLoadStatus()].phase = .background
        }
        let leadershipKey = HomeDataKey(scope: nil, kind: .leadership)
        if let value = result.leadership, result.leadershipComplete {
            leadership = value
            statuses[leadershipKey] = HomeLoadStatus(phase: .ready, observedAt: value.refreshedAt, hasDetails: true)
        } else if !result.complete && statuses[leadershipKey]?.phase != .ready {
            statuses[leadershipKey, default: HomeLoadStatus()].phase = .background
        }
        publish(save: true)
    }

    private func startHistory() {
        guard active, let context, !historyRunning else { return }
        if loaders.usesHistoryIndex {
            historyRequested = false
            let requestEpoch = epoch
            UsageHistoryService.shared.subscribe(context: context, onFailure: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.active, self.epoch == requestEpoch else { return }
                    self.acceptHistoryFailure(error)
                }
            }) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.active, self.epoch == requestEpoch else { return }
                    self.acceptHistoryArchive(result)
                }
            }
            return
        }
        historyRunning = true
        historyRequested = false
        let requestEpoch = epoch
        let loaders = loaders
        historyQueue.async { [weak self] in
            for scope in RuntimeScope.allCases {
                let local = loaders.local(scope, context)
                DispatchQueue.main.async {
                    guard let self, self.active, self.epoch == requestEpoch else { return }
                    let key = HomeDataKey(scope: scope, kind: .local)
                    if let local, let value = local.snapshot.local {
                        let old = self.runtimes[scope] ?? self.emptyRuntime(scope)
                        let merged = old.snapshot.replacingLocal(value, observedAt: local.snapshot.refreshedAt)
                        self.runtimes[scope] = RuntimeUsageSnapshot(
                            scope: scope, snapshot: merged,
                            status: merged.quotaReadSucceeded ? old.status : .localOnly,
                            quotaSourceLabel: old.quotaSourceLabel, usageSourceLabel: local.usageSourceLabel
                        )
                        self.statuses[key, default: HomeLoadStatus()].hasDetails = true
                    }
                    self.statuses[key, default: HomeLoadStatus()].finish(
                        at: local?.snapshot.local == nil ? nil : local?.snapshot.refreshedAt
                    )
                    self.publish(save: true)
                }
            }
            let leadership = loaders.leadership(context)
            DispatchQueue.main.async {
                guard let self else { return }
                self.historyRunning = false
                guard self.active else { return }
                if self.epoch == requestEpoch {
                    let key = HomeDataKey(scope: nil, kind: .leadership)
                    if leadership.defaultReport != nil {
                        self.leadership = leadership
                        self.statuses[key, default: HomeLoadStatus()].hasDetails = true
                    }
                    self.statuses[key, default: HomeLoadStatus()].finish(
                        at: leadership.defaultReport == nil ? nil : context.now
                    )
                    self.publish(save: true)
                }
                self.scheduleHistory()
            }
        }
    }

    private func restore(_ saved: MultiRuntimeUsageSnapshot) {
        for runtime in saved.runtimes {
            let scope = runtime.scope
            let localKey = HomeDataKey(scope: scope, kind: .local)
            if statuses[localKey]?.observedAt == nil, let local = runtime.snapshot.local {
                let old = runtimes[scope] ?? emptyRuntime(scope)
                runtimes[scope] = runtimeWith(old, local: local, taskBoard: old.snapshot.taskBoard,
                                              observedAt: runtime.snapshot.refreshedAt)
                statuses[localKey] = HomeLoadStatus(phase: .cached, observedAt: runtime.snapshot.refreshedAt)
            }
            let taskKey = HomeDataKey(scope: scope, kind: .tasks)
            if statuses[taskKey]?.observedAt == nil, let board = runtime.snapshot.taskBoard {
                runtimes[scope] = (runtimes[scope] ?? emptyRuntime(scope)).replacingTaskBoard(board)
                statuses[taskKey] = HomeLoadStatus(phase: .cached, observedAt: board.refreshedAt)
            }
        }
        let key = HomeDataKey(scope: nil, kind: .leadership)
        if statuses[key]?.observedAt == nil, saved.leadership.defaultReport != nil {
            leadership = saved.leadership
            statuses[key] = HomeLoadStatus(phase: .cached, observedAt: saved.leadership.refreshedAt)
        }
        publish()
    }

    private func emptyRuntime(_ scope: RuntimeScope) -> RuntimeUsageSnapshot {
        RuntimeUsageSnapshot(scope: scope, snapshot: .empty, status: .localOnly,
                             quotaSourceLabel: "", usageSourceLabel: "Local records")
    }

    private func runtimeWith(_ old: RuntimeUsageSnapshot, local: LocalUsage?, taskBoard: TaskBoard?,
                             observedAt: Date? = nil) -> RuntimeUsageSnapshot {
        RuntimeUsageSnapshot(scope: old.scope,
                             snapshot: old.snapshot.replacingLocal(local, observedAt: observedAt).replacingTaskBoard(taskBoard),
                             status: old.status, quotaSourceLabel: old.quotaSourceLabel, usageSourceLabel: old.usageSourceLabel)
    }

    private func publish(save: Bool = false) {
        guard active, let context else { return }
        let values = RuntimeScope.allCases.map { runtimes[$0] ?? emptyRuntime($0) }
        let summaries = values.map { runtimeWith($0, local: $0.snapshot.local?.homeSummary, taskBoard: nil) }
        let observedAt = statuses.values.compactMap(\.observedAt).max() ?? context.now
        let snapshot = MultiRuntimeUsageSnapshot(
            refreshedAt: observedAt, runtimes: values,
            aggregate: AgentUsageAggregator().aggregate(summaries, at: observedAt),
            leadership: leadership,
            statisticsIdentity: StatisticsIdentity(preference: context.statistics.preference,
                                                   resolvedIdentifier: context.statistics.resolvedIdentifier,
                                                   generation: epoch, now: context.now)
        )
        let waiting = statuses.contains { $0.key.kind == .quota && $0.value.isWaiting }
        onChange?(HomePresentation(snapshot: snapshot, statuses: statuses, isRefreshing: waiting))
        // Do not let a fast quota-only result erase a valid local snapshot
        // before the independent restoration queue has had a chance to read it.
        if save && restorationComplete {
            pendingSave?.cancel()
            let save = loaders.save
            let work = DispatchWorkItem { save(snapshot, context) }
            pendingSave = work
            saveQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
}

private extension LocalUsage {
    func preservingDetails(from previous: LocalUsage?, when preserve: Bool) -> LocalUsage {
        guard preserve, let previous else { return self }
        return LocalUsage(lifetimeTokens: lifetimeTokens, todayTokens: todayTokens, sevenDayTokens: sevenDayTokens,
            threadCount: threadCount, lastUpdatedAt: lastUpdatedAt, dailyBuckets: dailyBuckets, recentThreads: recentThreads,
            detailedUsage: detailedUsage, usageTrend: usageTrend, inferencePerformance: previous.inferencePerformance,
            projectBoard: previous.projectBoard, toolUsages: previous.toolUsages, skillUsages: previous.skillUsages)
    }
}

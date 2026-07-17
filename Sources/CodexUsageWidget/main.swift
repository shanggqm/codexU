import Cocoa
import Carbon.HIToolbox
import Combine
import SwiftUI

struct RateWindow: Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CreditsInfo: Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
    let resetCredits: Int?
}

struct AccountInfo: Equatable {
    let type: String
    let planType: String?
    let emailPresent: Bool
}

struct LocalThread: Identifiable, Equatable {
    let id: String
    let title: String
    let tokens: Int64
    let updatedAt: Date?
    let model: String?
    let cwd: String
    let archived: Bool
}

struct DailyTokenBucket: Identifiable, Equatable {
    let id: String
    let label: String
    let tokens: Int64
}

enum UsageSourceQuality: String, Equatable, Codable {
    case official
    case detailed
    case approximate
}

struct TokenBreakdown: Equatable, Codable {
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64

    static let zero = TokenBreakdown(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    var billableCachedInputTokens: Int64 {
        min(max(cachedInputTokens, 0), max(inputTokens, 0))
    }

    var uncachedInputTokens: Int64 {
        max(0, inputTokens - billableCachedInputTokens)
    }

    var visibleTotalTokens: Int64 {
        max(totalTokens, inputTokens + outputTokens)
    }

    var splitTotalTokens: Int64 {
        max(uncachedInputTokens + billableCachedInputTokens + max(outputTokens, 0), 0)
    }

    var isZero: Bool {
        inputTokens == 0
            && cachedInputTokens == 0
            && outputTokens == 0
            && reasoningOutputTokens == 0
            && totalTokens == 0
    }

    var hasNegativeValue: Bool {
        inputTokens < 0
            || cachedInputTokens < 0
            || outputTokens < 0
            || reasoningOutputTokens < 0
            || totalTokens < 0
    }

    mutating func add(_ other: TokenBreakdown) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    func delta(from previous: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            inputTokens: inputTokens - previous.inputTokens,
            cachedInputTokens: cachedInputTokens - previous.cachedInputTokens,
            outputTokens: outputTokens - previous.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens - previous.reasoningOutputTokens,
            totalTokens: totalTokens - previous.totalTokens
        )
    }
}

struct PricedTokenUsage: Equatable, Codable {
    var tokens: TokenBreakdown
    var estimatedCostUSD: Double

    static let zero = PricedTokenUsage(tokens: .zero, estimatedCostUSD: 0)

    mutating func add(tokens addedTokens: TokenBreakdown, costUSD: Double) {
        tokens.add(addedTokens)
        estimatedCostUSD += costUSD
    }
}

struct UsageDayBucket: Identifiable, Equatable, Codable {
    let id: String
    let date: Date
    let usage: PricedTokenUsage
    let sourceQuality: UsageSourceQuality

    var tokens: Int64 {
        usage.tokens.visibleTotalTokens
    }
}

struct UsageHeatmapDay: Identifiable, Equatable, Codable {
    let id: String
    let date: Date
    let usage: PricedTokenUsage?
    let isFuture: Bool

    var tokens: Int64 {
        usage?.tokens.visibleTotalTokens ?? 0
    }
}

struct UsageTrendSummary: Equatable, Codable {
    let sevenDay: PricedTokenUsage
    let dailyAverageTokens: Int64
    let peakDay: UsageDayBucket?
    let changePercent: Double?
    let isNewActivity: Bool
}

struct UsageTrend: Equatable, Codable {
    let dayBuckets: [UsageDayBucket]
    let heatmapWeeks: [[UsageHeatmapDay]]
    let heatmapThresholds: [Int64]
    let summary: UsageTrendSummary
    let month: PricedTokenUsage
    let projectedMonthCostUSD: Double?
    let activeDayCount: Int
    let sourceQuality: UsageSourceQuality
}

struct DetailedUsage: Equatable, Codable {
    let today: PricedTokenUsage
    let sevenDay: PricedTokenUsage
    let month: PricedTokenUsage
    let lifetime: PricedTokenUsage
    let parsedFileCount: Int
    let tokenEventCount: Int
}

struct ProjectUsage: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let fullPath: String
    let tokens: Int64
    let estimatedCostUSD: Double?
    let threadCount: Int
    let lastActiveAt: Date?
    let sourceQuality: UsageSourceQuality
}

struct ProjectBoard: Equatable {
    let recentProjects: [ProjectUsage]
    let allProjects: [ProjectUsage]
}

struct ToolUsage: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let category: String
    let callCount: Int
    let estimatedTokens: Int64?
    let estimatedCostUSD: Double?
}

struct SkillUsage: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let path: String
    let sourceLabel: String
    let loadCount: Int
    let threadCount: Int
    let staticTokenEstimate: Int64?
    let staticByteCount: Int64?
    let lastLoadedAt: Date?
}

struct LocalUsage: Equatable {
    let lifetimeTokens: Int64
    let todayTokens: Int64
    let sevenDayTokens: Int64
    let threadCount: Int
    let lastUpdatedAt: Date?
    let dailyBuckets: [DailyTokenBucket]
    let recentThreads: [LocalThread]
    let detailedUsage: DetailedUsage?
    let usageTrend: UsageTrend?
    let projectBoard: ProjectBoard?
    let toolUsages: [ToolUsage]
    let skillUsages: [SkillUsage]
}

enum TaskColumnKind: String, Equatable {
    case active
    case pending
    case scheduled
    case done
}

struct TaskTiming: Equatable {
    let createdAt: Date?
    let createdHasTime: Bool
    let deadlineAt: Date?
    let deadlineHasTime: Bool
}

enum TaskProgressOrigin: String, Equatable {
    case explicit
    case completedStatus
}

struct TaskProgress: Equatable {
    let percent: Double
    let origin: TaskProgressOrigin
}

struct TaskItem: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let chip: String
    let updatedAt: Date?
    let tokens: Int64?
    let kind: TaskColumnKind
    let source: RuntimeScope
    let summary: String?
    let recentReply: String?
    let timing: TaskTiming?
    let progress: TaskProgress?
    let navigationTarget: TaskNavigationTarget?
}

struct TaskColumn: Identifiable, Equatable {
    let id: TaskColumnKind
    let title: String
    let count: Int
    let items: [TaskItem]
}

struct TaskBoard: Equatable {
    let refreshedAt: Date
    let columns: [TaskColumn]

    var totalCount: Int {
        columns.reduce(0) { $0 + $1.count }
    }
}

struct UsageSnapshot: Equatable {
    let refreshedAt: Date
    let account: AccountInfo?
    let limitId: String?
    let limitName: String?
    let quotaReadSucceeded: Bool
    let fiveHourQuota: RateWindow?
    let sevenDayQuota: RateWindow?
    let credits: CreditsInfo?
    let cloudLifetimeTokens: Int64?
    let cloudUsageTrend: UsageTrend?
    let local: LocalUsage?
    let taskBoard: TaskBoard?
    let messages: [String]

    static let empty = UsageSnapshot(
        refreshedAt: Date(),
        account: nil,
        limitId: nil,
        limitName: nil,
        quotaReadSucceeded: false,
        fiveHourQuota: nil,
        sevenDayQuota: nil,
        credits: nil,
        cloudLifetimeTokens: nil,
        cloudUsageTrend: nil,
        local: nil,
        taskBoard: nil,
        messages: ["正在读取 codexU 数据"]
    )

    func replacingTaskBoard(_ taskBoard: TaskBoard?) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: refreshedAt,
            account: account,
            limitId: limitId,
            limitName: limitName,
            quotaReadSucceeded: quotaReadSucceeded,
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
            cloudUsageTrend: cloudUsageTrend,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )
    }

    func replacingLocalUsage(_ local: LocalUsage?, messages additionalMessages: [String] = []) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: refreshedAt,
            account: account,
            limitId: limitId,
            limitName: limitName,
            quotaReadSucceeded: quotaReadSucceeded,
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
            cloudUsageTrend: cloudUsageTrend,
            local: local,
            taskBoard: taskBoard,
            messages: messages + additionalMessages
        )
    }

    func replacingQuotaWindows(
        fiveHourQuota: RateWindow?,
        sevenDayQuota: RateWindow?,
        quotaReadSucceeded: Bool
    ) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: refreshedAt,
            account: account,
            limitId: limitId,
            limitName: limitName,
            quotaReadSucceeded: quotaReadSucceeded,
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
            cloudUsageTrend: cloudUsageTrend,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )
    }
}

struct DiagnosticItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemName: String
    let tint: Color
}

private struct ModelTokenPrice {
    let model: String
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double
}

private struct SessionUsageSource {
    let threadId: String
    let rolloutPath: String
    let model: String?
    let cwd: String
    let updatedAt: Date?
}

private struct SessionUsageDelta: Codable {
    let date: Date
    let tokens: TokenBreakdown
}

private struct SkillLoadEvent: Codable {
    let path: String
    let date: Date?
}

private struct SessionUsageCacheEntry: Codable {
    let fileSize: Int64
    let modificationDate: Date?
    let hasTokenEvents: Bool
    let tokenEventCount: Int
    let deltas: [SessionUsageDelta]
    let toolCalls: [String: Int]
    let skillLoads: [SkillLoadEvent]
}

private struct SessionUsageDiskCache: Codable {
    let version: Int
    let entries: [String: SessionUsageCacheEntry]
}

private struct DetailedUsageAccumulator {
    var today = PricedTokenUsage.zero
    var sevenDay = PricedTokenUsage.zero
    var month = PricedTokenUsage.zero
    var lifetime = PricedTokenUsage.zero
    var parsedFileCount = 0
    var tokenEventCount = 0

    mutating func add(
        _ tokens: TokenBreakdown,
        at date: Date,
        price: ModelTokenPrice,
        dayStart: Date,
        sevenDayStart: Date,
        monthStart: Date
    ) {
        let cost = estimatedCostUSD(tokens: tokens, price: price)
        lifetime.add(tokens: tokens, costUSD: cost)
        if date >= monthStart {
            month.add(tokens: tokens, costUSD: cost)
        }
        if date >= sevenDayStart {
            sevenDay.add(tokens: tokens, costUSD: cost)
        }
        if date >= dayStart {
            today.add(tokens: tokens, costUSD: cost)
        }
    }

    func makeUsage() -> DetailedUsage {
        DetailedUsage(
            today: today,
            sevenDay: sevenDay,
            month: month,
            lifetime: lifetime,
            parsedFileCount: parsedFileCount,
            tokenEventCount: tokenEventCount
        )
    }
}

private struct ProjectUsageAccumulator {
    let name: String
    let fullPath: String
    var tokens = TokenBreakdown.zero
    var estimatedCostUSD: Double = 0
    var threadIds = Set<String>()
    var lastActiveAt: Date?
    var sourceQuality: UsageSourceQuality = .detailed

    mutating func add(threadId: String, tokens addedTokens: TokenBreakdown, costUSD: Double, at date: Date) {
        tokens.add(addedTokens)
        estimatedCostUSD += costUSD
        threadIds.insert(threadId)
        if lastActiveAt == nil || date > (lastActiveAt ?? .distantPast) {
            lastActiveAt = date
        }
    }

    func makeUsage() -> ProjectUsage {
        ProjectUsage(
            id: fullPath.isEmpty ? name : fullPath,
            name: name,
            fullPath: fullPath,
            tokens: tokens.visibleTotalTokens,
            estimatedCostUSD: estimatedCostUSD,
            threadCount: max(threadIds.count, 1),
            lastActiveAt: lastActiveAt,
            sourceQuality: sourceQuality
        )
    }
}

private struct ToolUsageAccumulator {
    let name: String
    var callCount: Int = 0
    var estimatedTokens: Int64 = 0
    var estimatedCostUSD: Double = 0

    mutating func addCalls(_ calls: Int, estimatedTokens tokens: Int64, estimatedCostUSD cost: Double) {
        callCount += calls
        estimatedTokens += tokens
        estimatedCostUSD += cost
    }

    func makeUsage() -> ToolUsage {
        ToolUsage(
            id: name,
            name: name,
            category: toolCategory(for: name),
            callCount: callCount,
            estimatedTokens: estimatedTokens > 0 ? estimatedTokens : nil,
            estimatedCostUSD: estimatedCostUSD > 0 ? estimatedCostUSD : nil
        )
    }
}

private struct SkillStaticInfo {
    let tokenEstimate: Int64?
    let byteCount: Int64?
}

private struct SkillUsageAccumulator {
    let path: String
    var loadCount: Int = 0
    var threadIds = Set<String>()
    var lastLoadedAt: Date?

    mutating func addLoad(threadId: String, at date: Date?) {
        loadCount += 1
        threadIds.insert(threadId)
        guard let date else { return }
        if lastLoadedAt == nil || date > (lastLoadedAt ?? .distantPast) {
            lastLoadedAt = date
        }
    }

    func makeUsage(staticInfo: SkillStaticInfo) -> SkillUsage {
        return SkillUsage(
            id: path,
            name: skillName(from: path),
            path: path,
            sourceLabel: skillSourceLabel(from: path),
            loadCount: loadCount,
            threadCount: max(threadIds.count, 1),
            staticTokenEstimate: staticInfo.tokenEstimate,
            staticByteCount: staticInfo.byteCount,
            lastLoadedAt: lastLoadedAt
        )
    }
}

private struct LocalAnalytics: Equatable, Codable {
    let detailedUsage: DetailedUsage?
    let usageTrend: UsageTrend?
    let recentProjects: [ProjectUsage]
    let toolUsages: [ToolUsage]
    let skillUsages: [SkillUsage]
}

private struct LocalAnalyticsCacheEntry: Codable {
    let version: Int
    let dayKey: String
    let timeZoneIdentifier: String
    let sourceFingerprint: String
    let analytics: LocalAnalytics
}

enum VisualEnergyMode: Equatable {
    // This describes visibility and system energy pressure. Components that
    // animate must still gate on their own focus and interaction state.
    case suspended
    case constrained
    case normal
}

final class UsageStore: ObservableObject {
    private struct StatisticsSnapshotCacheEntry {
        let snapshot: MultiRuntimeUsageSnapshot
        let cachedAt: Date
    }

    @Published var snapshot: UsageSnapshot = .empty
    @Published var multiRuntimeSnapshot: MultiRuntimeUsageSnapshot = .empty
    @Published var runtimeSnapshots: [RuntimeUsageSnapshot] = []
    @Published var selectedRuntimeScope: RuntimeScope = .codex
    @Published var visibleRuntimeScopes: [RuntimeScope] = [.codex, .openClaw]
    @Published var isRefreshing = false
    @Published private(set) var statisticsPreference = StatisticsTimeZonePreferenceStore.load()
    @Published private(set) var statisticsTransitionMessage: String?
    @Published private(set) var isSwitchingStatisticsTimeZone = false
    @Published private(set) var visualEnergyMode: VisualEnergyMode = .suspended

    private var fullTimer: Timer?
    private var taskBoardTimer: Timer?
    private var statisticsRolloverTimer: Timer?
    private var systemTimeZoneObserver: NSObjectProtocol?
    private var powerStateObserver: NSObjectProtocol?
    private var thermalStateObserver: NSObjectProtocol?
    private var isRefreshingTaskBoard = false
    private var refreshGeneration: UInt64 = 0
    private var hasPendingRefresh = false
    private var statisticsSnapshotCache: [String: StatisticsSnapshotCacheEntry] = [:]
    private var statisticsSnapshotCacheOrder: [String] = []
    private var statisticsFeedbackTimer: Timer?
    private var hasStarted = false
    private var isMainWindowActive = false
    private var isTaskBoardSelected = false
    private var lastFullRefreshCompletedAt: Date?
    private let statisticsSnapshotCacheLimit = 4
    private let statisticsSnapshotCacheTTL: TimeInterval = 3 * 60
    private let taskBoardRefreshInterval: TimeInterval = 60
    private let foregroundFullRefreshInterval: TimeInterval = 5 * 60
    private let backgroundFullRefreshInterval: TimeInterval = 15 * 60

    var runtimeSummaries: [RuntimeMenuSummary] {
        RuntimeScope.allCases.compactMap { scope in
            runtimeSnapshot(for: scope)?.summary
        }
    }

    var totalTodayTokens: Int64 {
        multiRuntimeSnapshot.totalTodayTokens
    }

    func totalTodayTokens(for scopes: [RuntimeScope]) -> Int64 {
        scopes.reduce(Int64(0)) { total, scope in
            total + (runtimeSnapshot(for: scope)?.todayTokens ?? 0)
        }
    }

    func start() {
        hasStarted = true
        refresh()
        systemTimeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.statisticsPreference.selection == .system else { return }
            self.scheduleStatisticsRollover()
            self.refresh(queueIfBusy: true)
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVisualEnergyMode()
        }
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVisualEnergyMode()
        }
        updateVisualEnergyMode()
        scheduleStatisticsRollover()
        scheduleFullRefreshTimer()
        updateTaskBoardPollingState(refreshImmediately: false)
    }

    func stop() {
        hasStarted = false
        fullTimer?.invalidate()
        taskBoardTimer?.invalidate()
        statisticsRolloverTimer?.invalidate()
        statisticsFeedbackTimer?.invalidate()
        if let systemTimeZoneObserver {
            NotificationCenter.default.removeObserver(systemTimeZoneObserver)
            self.systemTimeZoneObserver = nil
        }
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
        if let thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
            self.thermalStateObserver = nil
        }
        visualEnergyMode = .suspended
    }

    func refresh(queueIfBusy: Bool = false) {
        guard !isRefreshing, !isRefreshingTaskBoard else {
            if queueIfBusy || isRefreshingTaskBoard {
                hasPendingRefresh = true
            }
            return
        }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let preference = statisticsPreference
        let scopes = visibleRuntimeScopes
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let multiSnapshot = MultiRuntimeUsageReader().load(
                scopes: scopes,
                statisticsPreference: preference,
                generation: generation
            )
            DispatchQueue.main.async {
                if generation == self.refreshGeneration,
                   multiSnapshot.statisticsIdentity.preference == self.statisticsPreference {
                    self.apply(multiSnapshot)
                    self.cacheStatisticsSnapshot(multiSnapshot)
                    if self.isSwitchingStatisticsTimeZone {
                        self.finishStatisticsTimeZoneSwitch()
                    }
                }
                self.isRefreshing = false
                self.lastFullRefreshCompletedAt = Date()
                self.scheduleFullRefreshTimer()
                if self.hasPendingRefresh {
                    self.hasPendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    func updateStatisticsTimeZone(_ preference: StatisticsTimeZonePreference) {
        let repaired = preference.repaired()
        guard repaired != statisticsPreference else { return }
        refreshGeneration &+= 1
        statisticsPreference = repaired
        StatisticsTimeZonePreferenceStore.save(repaired)
        scheduleStatisticsRollover()
        isSwitchingStatisticsTimeZone = true
        statisticsTransitionMessage = statisticsSwitchingMessage(for: repaired)

        let key = statisticsCacheKey(for: repaired)
        if let cached = validCachedStatisticsSnapshot(forKey: key) {
            let identity = StatisticsIdentity(
                preference: repaired,
                resolvedIdentifier: StatisticsContext(preference: repaired, now: Date()).resolvedIdentifier,
                generation: refreshGeneration,
                now: Date()
            )
            let rebound = MultiRuntimeUsageSnapshot(
                refreshedAt: cached.refreshedAt,
                runtimes: cached.runtimes,
                aggregate: cached.aggregate,
                statisticsIdentity: identity
            )
            apply(rebound)
            cacheStatisticsSnapshot(rebound)
            finishStatisticsTimeZoneSwitch(cached: true)
            return
        }
        refresh(queueIfBusy: true)
    }

    private func statisticsCacheKey(for preference: StatisticsTimeZonePreference) -> String {
        let timeZone = StatisticsContext(preference: preference, now: Date()).resolvedIdentifier
        let runtimes = visibleRuntimeScopes.map(\.runtimeId).joined(separator: ",")
        return "\(timeZone)|\(runtimes)"
    }

    private func validCachedStatisticsSnapshot(forKey key: String) -> MultiRuntimeUsageSnapshot? {
        guard let entry = statisticsSnapshotCache[key],
              Date().timeIntervalSince(entry.cachedAt) <= statisticsSnapshotCacheTTL else {
            statisticsSnapshotCache.removeValue(forKey: key)
            statisticsSnapshotCacheOrder.removeAll { $0 == key }
            return nil
        }
        statisticsSnapshotCacheOrder.removeAll { $0 == key }
        statisticsSnapshotCacheOrder.append(key)
        return entry.snapshot
    }

    private func cacheStatisticsSnapshot(_ snapshot: MultiRuntimeUsageSnapshot) {
        let key = statisticsCacheKey(for: snapshot.statisticsIdentity.preference)
        statisticsSnapshotCache[key] = StatisticsSnapshotCacheEntry(snapshot: snapshot, cachedAt: Date())
        statisticsSnapshotCacheOrder.removeAll { $0 == key }
        statisticsSnapshotCacheOrder.append(key)
        while statisticsSnapshotCacheOrder.count > statisticsSnapshotCacheLimit {
            let evicted = statisticsSnapshotCacheOrder.removeFirst()
            statisticsSnapshotCache.removeValue(forKey: evicted)
        }
    }

    private func statisticsSwitchingMessage(for preference: StatisticsTimeZonePreference) -> String {
        let identifier = StatisticsContext(preference: preference, now: Date()).resolvedIdentifier
        return "正在切换到 \(identifier)…"
    }

    private func finishStatisticsTimeZoneSwitch(cached: Bool = false) {
        isSwitchingStatisticsTimeZone = false
        let identifier = multiRuntimeSnapshot.statisticsIdentity.resolvedIdentifier
        statisticsTransitionMessage = cached ? "已切换到 \(identifier) · 缓存" : "已切换到 \(identifier)"
        statisticsFeedbackTimer?.invalidate()
        statisticsFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.statisticsTransitionMessage = nil
        }
    }

    private func scheduleStatisticsRollover() {
        statisticsRolloverTimer?.invalidate()
        let context = StatisticsContext(preference: statisticsPreference, now: Date())
        let start = context.calendar.startOfDay(for: context.now)
        guard let nextDay = context.calendar.date(byAdding: .day, value: 1, to: start) else { return }
        statisticsRolloverTimer = Timer(fire: nextDay.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            self?.scheduleStatisticsRollover()
            self?.refresh(queueIfBusy: true)
        }
        if let statisticsRolloverTimer {
            RunLoop.main.add(statisticsRolloverTimer, forMode: .common)
        }
    }

    func selectRuntime(_ scope: RuntimeScope) {
        let nextScope = visibleRuntimeScopes.contains(scope) ? scope : (visibleRuntimeScopes.first ?? scope)
        selectedRuntimeScope = nextScope
        snapshot = multiRuntimeSnapshot.displaySnapshot(for: nextScope)
    }

    func runtimeSnapshot(for scope: RuntimeScope) -> RuntimeUsageSnapshot? {
        runtimeSnapshots.first { $0.scope == scope }
    }

    func updateVisibleRuntimeScopes(_ scopes: [RuntimeScope]) {
        let normalized = scopes.isEmpty ? [.codex, .openClaw] : scopes
        guard normalized != visibleRuntimeScopes else { return }
        refreshGeneration &+= 1
        visibleRuntimeScopes = normalized
        statisticsSnapshotCache.removeAll()
        statisticsSnapshotCacheOrder.removeAll()
        if !visibleRuntimeScopes.contains(selectedRuntimeScope) {
            selectRuntime(visibleRuntimeScopes.first ?? selectedRuntimeScope)
        }
        if hasStarted {
            refresh(queueIfBusy: true)
        }
    }

    func setMainWindowActive(_ isActive: Bool) {
        guard isMainWindowActive != isActive else { return }
        isMainWindowActive = isActive
        updateVisualEnergyMode()
        guard hasStarted else { return }
        scheduleFullRefreshTimer()
        if isActive {
            refreshIfStale(maximumAge: foregroundFullRefreshInterval)
        }
        updateTaskBoardPollingState(refreshImmediately: isTaskBoardPollingEnabled)
    }

    private func updateVisualEnergyMode() {
        guard isMainWindowActive else {
            visualEnergyMode = .suspended
            return
        }

        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled || processInfo.thermalState != .nominal {
            visualEnergyMode = .constrained
        } else {
            visualEnergyMode = .normal
        }
    }

    func refreshIfStale(maximumAge: TimeInterval) {
        // An in-flight full refresh will make the snapshot fresh; queueing a
        // second one here commonly doubles startup work when occlusion state
        // arrives just after the initial load begins.
        guard !isRefreshing else { return }
        guard let lastFullRefreshCompletedAt else {
            refresh(queueIfBusy: true)
            return
        }
        guard Date().timeIntervalSince(lastFullRefreshCompletedAt) >= maximumAge else { return }
        refresh(queueIfBusy: true)
    }

    func setTaskBoardSelected(_ isSelected: Bool) {
        guard isTaskBoardSelected != isSelected else { return }
        isTaskBoardSelected = isSelected
        guard hasStarted else { return }
        updateTaskBoardPollingState(refreshImmediately: isTaskBoardPollingEnabled)
    }

    private var isTaskBoardPollingEnabled: Bool {
        isMainWindowActive && isTaskBoardSelected
    }

    private func scheduleFullRefreshTimer() {
        fullTimer?.invalidate()
        fullTimer = nil
        guard hasStarted else { return }

        let interval = isMainWindowActive
            ? foregroundFullRefreshInterval
            : backgroundFullRefreshInterval
        let elapsed = lastFullRefreshCompletedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let nextDelay = max(1, interval - elapsed)
        let timer = Timer(
            fire: Date().addingTimeInterval(nextDelay),
            interval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        fullTimer = timer
    }

    private func updateTaskBoardPollingState(refreshImmediately: Bool) {
        taskBoardTimer?.invalidate()
        taskBoardTimer = nil
        guard hasStarted, isTaskBoardPollingEnabled else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: taskBoardRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshTaskBoard()
        }
        timer.tolerance = 12
        taskBoardTimer = timer
        if refreshImmediately {
            refreshTaskBoard()
        }
    }

    private func refreshTaskBoard() {
        guard !isRefreshing, !isRefreshingTaskBoard else { return }
        isRefreshingTaskBoard = true
        let scopes = visibleRuntimeScopes
        let preference = statisticsPreference

        DispatchQueue.global(qos: .utility).async {
            let reader = MultiRuntimeUsageReader()
            let taskBoards = scopes.map { scope in
                (scope, reader.loadTaskBoard(scope: scope, statisticsPreference: preference))
            }
            DispatchQueue.main.async {
                for (scope, taskBoard) in taskBoards {
                    self.applyTaskBoard(taskBoard, for: scope)
                }
                self.isRefreshingTaskBoard = false
                if self.hasPendingRefresh {
                    self.hasPendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    private func apply(_ multiSnapshot: MultiRuntimeUsageSnapshot) {
        let reconciledRuntimes = RuntimeQuotaContinuity.reconcile(
            previous: runtimeSnapshots,
            incoming: multiSnapshot.runtimes
        )
        let reconciledSnapshot = MultiRuntimeUsageSnapshot(
            refreshedAt: multiSnapshot.refreshedAt,
            runtimes: reconciledRuntimes,
            aggregate: multiSnapshot.aggregate,
            statisticsIdentity: multiSnapshot.statisticsIdentity
        )
        let nextScope = reconciledSnapshot.defaultScope(
            preferred: selectedRuntimeScope,
            allowedScopes: visibleRuntimeScopes
        )
        multiRuntimeSnapshot = reconciledSnapshot
        runtimeSnapshots = reconciledRuntimes
        selectedRuntimeScope = nextScope
        snapshot = reconciledSnapshot.displaySnapshot(for: nextScope)
    }

    private func applyTaskBoard(_ taskBoard: TaskBoard?, for scope: RuntimeScope) {
        guard let index = runtimeSnapshots.firstIndex(where: { $0.scope == scope }) else {
            guard snapshot.taskBoard?.columns != taskBoard?.columns else { return }
            snapshot = snapshot.replacingTaskBoard(taskBoard)
            return
        }

        guard runtimeSnapshots[index].snapshot.taskBoard?.columns != taskBoard?.columns else { return }
        runtimeSnapshots[index] = runtimeSnapshots[index].replacingTaskBoard(taskBoard)
        let aggregate = AgentUsageAggregator().aggregate(runtimeSnapshots, at: multiRuntimeSnapshot.refreshedAt)
        multiRuntimeSnapshot = MultiRuntimeUsageSnapshot(
            refreshedAt: multiRuntimeSnapshot.refreshedAt,
            runtimes: runtimeSnapshots,
            aggregate: aggregate,
            statisticsIdentity: multiRuntimeSnapshot.statisticsIdentity
        )
        if selectedRuntimeScope == scope {
            snapshot = runtimeSnapshots[index].snapshot
        }
    }
}

final class CodexUsageReader {
    private let fileManager = FileManager.default
    private let localAnalyticsCacheVersion = 9
    private let sessionUsageCacheVersion = 5
    private static let sessionUsageCacheLimit = 1_024
    private static let persistentSessionUsageCacheWriteInterval: TimeInterval = 15 * 60
    private static var sessionUsageCache: [String: SessionUsageCacheEntry] = [:]
    private static var sessionUsageCacheOrder: [String] = []
    private static var persistentSessionUsageCache: [String: SessionUsageCacheEntry]?
    private static var persistentSessionUsageCacheIsDirty = false
    private static var lastPersistentSessionUsageCacheWriteAt: Date?
    private static var localAnalyticsCache: LocalAnalyticsCacheEntry?

    func load(context: RuntimeLoadContext) -> UsageSnapshot {
        var messages: [String] = []
        let appServer = readAppServer(messages: &messages)
        let local = readLocalUsage(context: context, messages: &messages)
        let taskBoard = readTaskBoard(context: context, messages: &messages)
        let cloudUsageTrend = makeCloudUsageTrend(appServer.cloudDailyUsageBuckets, context: context)

        return UsageSnapshot(
            refreshedAt: context.now,
            account: appServer.account,
            limitId: appServer.limitId,
            limitName: appServer.limitName,
            quotaReadSucceeded: appServer.quotaReadSucceeded,
            fiveHourQuota: appServer.fiveHourQuota,
            sevenDayQuota: appServer.sevenDayQuota,
            credits: appServer.credits,
            cloudLifetimeTokens: appServer.cloudLifetimeTokens,
            cloudUsageTrend: cloudUsageTrend,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        var messages: [String] = []
        return readTaskBoard(context: context, messages: &messages)
    }

    private struct AppServerSnapshot {
        var account: AccountInfo?
        var limitId: String?
        var limitName: String?
        var quotaReadSucceeded = false
        var fiveHourQuota: RateWindow?
        var sevenDayQuota: RateWindow?
        var rateLimitDiagnostics: [String] = []
        var credits: CreditsInfo?
        var cloudLifetimeTokens: Int64?
        var cloudDailyUsageBuckets: [DailyTokenBucket] = []
    }

    private func readAppServer(messages: inout [String]) -> AppServerSnapshot {
        guard let codexPath = resolveCodexExecutablePath() else {
            messages.append("未找到 codex 可执行文件")
            return AppServerSnapshot()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            messages.append("app-server 启动失败")
            return AppServerSnapshot()
        }

        func writeMessage(_ request: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: request) {
                input.fileHandleForWriting.write(data)
                input.fileHandleForWriting.write(Data("\n".utf8))
            }
        }

        let responseGroup = DispatchGroup()
        [2, 3, 4].forEach { _ in responseGroup.enter() }

        let lock = NSLock()
        var buffer = Data()
        var snapshot = AppServerSnapshot()
        var completed = Set<Int>()
        var sentAccountRequests = false
        var appServerMessages: [String] = []

        func markComplete(_ id: Int) {
            lock.lock()
            let inserted = completed.insert(id).inserted
            lock.unlock()
            if inserted {
                responseGroup.leave()
            }
        }

        func parseLine(_ lineData: Data) {
            guard
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let id = object["id"] as? Int
            else { return }

            if id == 1 {
                lock.lock()
                let shouldSend = !sentAccountRequests
                sentAccountRequests = true
                lock.unlock()

                if shouldSend {
                    writeMessage(["method": "initialized"])
                    writeMessage(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
                    writeMessage(["id": 3, "method": "account/rateLimits/read"])
                    writeMessage(["id": 4, "method": "account/usage/read"])
                }
                return
            }

            if let errorObject = object["error"] as? [String: Any] {
                let message = errorObject["message"] as? String ?? "未知错误"
                lock.lock()
                appServerMessages.append("app-server \(id): \(message)")
                lock.unlock()
                markComplete(id)
                return
            }

            guard let result = object["result"] as? [String: Any] else {
                markComplete(id)
                return
            }

            lock.lock()
            switch id {
            case 2:
                snapshot.account = parseAccount(result)
            case 3:
                parseRateLimits(result, into: &snapshot)
            case 4:
                snapshot.cloudLifetimeTokens = parseCloudLifetimeTokens(result)
                snapshot.cloudDailyUsageBuckets = parseCloudDailyUsageBuckets(result)
            default:
                break
            }
            lock.unlock()

            if [2, 3, 4].contains(id) {
                markComplete(id)
            }
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            lock.lock()
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 10) {
                lines.append(buffer.subdata(in: buffer.startIndex..<newline))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            lock.unlock()

            for line in lines where !line.isEmpty {
                parseLine(line)
            }
        }

        writeMessage([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codexu",
                    "title": "codexU",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.1"
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "optOutNotificationMethods": []
                ]
            ]
        ])

        if responseGroup.wait(timeout: .now() + 12) == .timedOut {
            lock.lock()
            appServerMessages.append("app-server 响应超时")
            lock.unlock()
        }

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
            }
        }

        lock.lock()
        let finalSnapshot = snapshot
        let finalAppServerMessages = appServerMessages
        lock.unlock()

        messages.append(contentsOf: finalAppServerMessages)
        messages.append(contentsOf: finalSnapshot.rateLimitDiagnostics)

        return finalSnapshot
    }

    private func parseAccount(_ result: [String: Any]) -> AccountInfo? {
        guard let account = result["account"] as? [String: Any],
              let type = account["type"] as? String else { return nil }

        return AccountInfo(
            type: type,
            planType: account["planType"] as? String,
            emailPresent: account["email"] != nil && !(account["email"] is NSNull)
        )
    }

    private func parseRateLimits(_ result: [String: Any], into snapshot: inout AppServerSnapshot) {
        let selected: [String: Any]?
        if let byId = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byId["codex"] as? [String: Any] {
            selected = codex
        } else {
            selected = result["rateLimits"] as? [String: Any]
        }

        guard let limits = selected else { return }
        snapshot.limitId = limits["limitId"] as? String
        snapshot.limitName = limits["limitName"] as? String
        let rawWindows = [limits["primary"], limits["secondary"]]
        let parsedWindows = rawWindows.map(parseRateWindow)
        let normalized = CodexRateLimitNormalizer.normalize(parsedWindows)
        let hasWindowFields = limits.keys.contains("primary") || limits.keys.contains("secondary")
        let hasMalformedWindow = zip(rawWindows, parsedWindows).contains { raw, parsed in
            guard let raw, !(raw is NSNull) else { return false }
            return parsed == nil
        }
        let quotaReadSucceeded = CodexRateLimitNormalizer.isAuthoritative(
            hasWindowFields: hasWindowFields,
            hasMalformedWindow: hasMalformedWindow,
            normalized: normalized
        )
        snapshot.quotaReadSucceeded = quotaReadSucceeded
        // Quota topology is committed atomically. A partly understood payload must
        // never make a confirmed dual-window layout collapse into a misleading
        // single-window layout; continuity will keep the last confirmed topology.
        snapshot.fiveHourQuota = quotaReadSucceeded ? normalized.fiveHour : nil
        snapshot.sevenDayQuota = quotaReadSucceeded ? normalized.sevenDay : nil
        var diagnostics = rateLimitDiagnostics(for: normalized)
        if !hasWindowFields {
            diagnostics.append("Codex 额度响应缺少窗口字段，未将其视为当前无限制")
        }
        if hasMalformedWindow {
            diagnostics.append("Codex 额度窗口格式无法解析，未将其视为当前无限制")
        }
        snapshot.rateLimitDiagnostics = diagnostics

        var resetCredits: Int?
        if let reset = result["rateLimitResetCredits"] as? [String: Any] {
            resetCredits = intValue(reset["availableCount"])
        }

        if let credits = limits["credits"] as? [String: Any] {
            snapshot.credits = CreditsInfo(
                hasCredits: credits["hasCredits"] as? Bool ?? false,
                unlimited: credits["unlimited"] as? Bool ?? false,
                balance: stringValue(credits["balance"]),
                resetCredits: resetCredits
            )
        } else if resetCredits != nil {
            snapshot.credits = CreditsInfo(hasCredits: false, unlimited: false, balance: nil, resetCredits: resetCredits)
        }
    }

    private func parseRateWindow(_ value: Any?) -> RateWindow? {
        guard let object = value as? [String: Any],
              let used = doubleValue(object["usedPercent"])
        else { return nil }

        let resetDate: Date?
        if let timestamp = doubleValue(object["resetsAt"]) {
            resetDate = Date(timeIntervalSince1970: timestamp)
        } else {
            resetDate = nil
        }

        return RateWindow(
            usedPercent: used,
            windowDurationMins: intValue(object["windowDurationMins"]),
            resetsAt: resetDate
        )
    }

    private func rateLimitDiagnostics(for windows: CodexNormalizedRateWindows) -> [String] {
        var messages: [String] = []

        if windows.fiveHourMatchCount > 1 {
            messages.append("Codex 返回了重复的 5 小时额度窗口，已停止显示该窗口")
        }
        if windows.sevenDayMatchCount > 1 {
            messages.append("Codex 返回了重复的 7 天额度窗口，已停止显示该窗口")
        }

        let missingDurationCount = windows.unclassified.filter {
            $0.windowDurationMins == nil
        }.count
        if missingDurationCount > 0 {
            messages.append("Codex 返回了缺少时长的额度窗口，未将其标注为 5 小时或 7 天")
        }

        let unknownDurations = Set(windows.unclassified.compactMap(\.windowDurationMins)).sorted()
        if !unknownDurations.isEmpty {
            let values = unknownDurations.map(String.init).joined(separator: "、")
            messages.append("Codex 返回了未识别的额度窗口（\(values) 分钟），未将其标注为 5 小时或 7 天")
        }

        return messages
    }

    private func parseCloudLifetimeTokens(_ result: [String: Any]) -> Int64? {
        guard let summary = result["summary"] as? [String: Any] else { return nil }
        return int64Value(summary["lifetimeTokens"])
    }

    private func parseCloudDailyUsageBuckets(_ result: [String: Any]) -> [DailyTokenBucket] {
        guard let rows = result["dailyUsageBuckets"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let startDate = row["startDate"] as? String,
                  startDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  let tokens = int64Value(row["tokens"]),
                  tokens >= 0
            else { return nil }
            return DailyTokenBucket(id: startDate, label: startDate, tokens: tokens)
        }
        .sorted { $0.id < $1.id }
    }

    private func makeCloudUsageTrend(
        _ buckets: [DailyTokenBucket],
        context: RuntimeLoadContext
    ) -> UsageTrend? {
        guard !buckets.isEmpty else { return nil }
        let calendar = context.statistics.calendar
        let dayStart = calendar.startOfDay(for: context.now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? sevenDayStart
        var monthComponents = calendar.dateComponents([.year, .month], from: dayStart)
        monthComponents.day = 1
        monthComponents.hour = 0
        monthComponents.minute = 0
        monthComponents.second = 0
        let monthStart = calendar.date(from: monthComponents) ?? dayStart

        var dailyUsage: [String: PricedTokenUsage] = [:]
        for bucket in buckets {
            dailyUsage[bucket.id] = PricedTokenUsage(
                tokens: TokenBreakdown(
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: bucket.tokens
                ),
                estimatedCostUSD: 0
            )
        }

        return makeUsageTrend(
            dailyUsage: dailyUsage,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            trendStart: trendStart,
            monthStart: monthStart,
            sourceQuality: .official,
            calendar: calendar
        )
    }

    private func codexDatabasePaths(context: RuntimeLoadContext) -> [String] {
        let home = context.homeDirectory.path
        let candidates = [
            [
                home + "/.codex/state_5.sqlite",
                home + "/.codex/sqlite/state_5.sqlite"
            ],
            [
                home + "/.openclaw/agents/codex/agent/codex-home/state_5.sqlite",
                home + "/.openclaw/agents/codex/agent/codex-home/sqlite/state_5.sqlite"
            ]
        ]
        var seen = Set<String>()
        return candidates.compactMap(firstExistingPath).filter { seen.insert($0).inserted }
    }

    private func readLocalUsage(context: RuntimeLoadContext, messages: inout [String]) -> LocalUsage? {
        let dbPaths = codexDatabasePaths(context: context)
        guard !dbPaths.isEmpty else {
            messages.append("未找到 Codex state_5.sqlite")
            return nil
        }

        guard let sqlitePath = firstExistingPath([
            "/usr/bin/sqlite3",
            "/opt/homebrew/bin/sqlite3",
            "/opt/homebrew/share/android-commandlinetools/platform-tools/sqlite3"
        ]) else {
            messages.append("未找到 sqlite3")
            return nil
        }

        let calendar = context.statistics.calendar
        let now = context.now
        let dayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "zh_CN")
        labelFormatter.dateFormat = "M/d"

        let totalsQuery = """
        SELECT
          COALESCE(SUM(tokens_used), 0) AS lifetimeTokens,
          COALESCE(SUM(CASE WHEN updated_at >= \(Int(dayStart.timeIntervalSince1970)) THEN tokens_used ELSE 0 END), 0) AS todayTokens,
          COALESCE(SUM(CASE WHEN updated_at >= \(Int(sevenDayStart.timeIntervalSince1970)) THEN tokens_used ELSE 0 END), 0) AS sevenDayTokens,
          COUNT(*) AS threadCount,
          COALESCE(MAX(updated_at), 0) AS lastUpdatedAt
        FROM threads;
        """

        let recentQuery = """
        SELECT id, title, tokens_used AS tokens, updated_at AS updatedAt, model, cwd, archived
        FROM threads
        ORDER BY updated_at DESC
        LIMIT 5;
        """

        let dailyQuery = """
        SELECT updated_at AS updatedAt, tokens_used AS tokens
        FROM threads
        WHERE updated_at >= \(Int(sevenDayStart.timeIntervalSince1970))
        ORDER BY updated_at ASC;
        """

        let totalsObjects = dbPaths.compactMap {
            runSQLiteJSON(sqlitePath: sqlitePath, dbPath: $0, query: totalsQuery).first
        }
        guard !totalsObjects.isEmpty else {
            messages.append("SQLite 查询失败")
            return nil
        }
        let recentObjects = dbPaths
            .flatMap { runSQLiteJSON(sqlitePath: sqlitePath, dbPath: $0, query: recentQuery) }
            .sorted { (dateFromEpoch($0["updatedAt"]) ?? .distantPast) > (dateFromEpoch($1["updatedAt"]) ?? .distantPast) }
            .prefix(5)
        let dailyObjects = dbPaths.flatMap {
            runSQLiteJSON(sqlitePath: sqlitePath, dbPath: $0, query: dailyQuery)
        }

        let recent = recentObjects.map { object in
            LocalThread(
                id: object["id"] as? String ?? UUID().uuidString,
                title: object["title"] as? String ?? "Untitled",
                tokens: int64Value(object["tokens"]) ?? 0,
                updatedAt: dateFromEpoch(object["updatedAt"]),
                model: object["model"] as? String,
                cwd: object["cwd"] as? String ?? "",
                archived: (intValue(object["archived"]) ?? 0) != 0
            )
        }

        var tokensByDay: [String: Int64] = [:]
        for object in dailyObjects {
            guard let updatedAt = dateFromEpoch(object["updatedAt"]) else { continue }
            let key = context.statistics.dayKey(for: updatedAt)
            tokensByDay[key, default: 0] += int64Value(object["tokens"]) ?? 0
        }

        let dailyBuckets = (0..<7).compactMap { index -> DailyTokenBucket? in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: dayStart) else { return nil }
            let key = dayFormatter.string(from: date)
            return DailyTokenBucket(
                id: key,
                label: index == 6 ? "今天" : labelFormatter.string(from: date),
                tokens: tokensByDay[key] ?? 0
            )
        }

        let analytics = readLocalAnalytics(
            sqlitePath: sqlitePath,
            dbPaths: dbPaths,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            statistics: context.statistics,
            messages: &messages
        )
        let allProjects = readAllTimeProjects(sqlitePath: sqlitePath, dbPaths: dbPaths)
        let projectBoard = ProjectBoard(
            recentProjects: analytics.recentProjects.isEmpty
                ? readApproximateRecentProjects(sqlitePath: sqlitePath, dbPaths: dbPaths, sevenDayStart: sevenDayStart)
                : analytics.recentProjects,
            allProjects: allProjects
        )

        let lifetimeTokens = totalsObjects.reduce(Int64(0)) { $0 + (int64Value($1["lifetimeTokens"]) ?? 0) }
        let todayTokens = totalsObjects.reduce(Int64(0)) { $0 + (int64Value($1["todayTokens"]) ?? 0) }
        let sevenDayTokens = totalsObjects.reduce(Int64(0)) { $0 + (int64Value($1["sevenDayTokens"]) ?? 0) }
        let threadCount = totalsObjects.reduce(0) { $0 + (intValue($1["threadCount"]) ?? 0) }
        let lastUpdatedAt = totalsObjects.compactMap { dateFromEpoch($0["lastUpdatedAt"]) }.max()
        if dbPaths.contains(where: { $0.contains("/.openclaw/agents/codex/") }) {
            messages.append("Codex 用量已包含 OpenClaw 调用 Codex 产生的本机记录")
        }

        return LocalUsage(
            lifetimeTokens: lifetimeTokens,
            todayTokens: todayTokens,
            sevenDayTokens: sevenDayTokens,
            threadCount: threadCount,
            lastUpdatedAt: lastUpdatedAt,
            dailyBuckets: dailyBuckets,
            recentThreads: recent,
            detailedUsage: analytics.detailedUsage,
            usageTrend: analytics.usageTrend ?? readApproximateUsageTrend(
                sqlitePath: sqlitePath,
                dbPaths: dbPaths,
                dayStart: dayStart,
                sevenDayStart: sevenDayStart,
                calendar: calendar
            ),
            projectBoard: projectBoard,
            toolUsages: analytics.toolUsages,
            skillUsages: analytics.skillUsages
        )
    }

    private func readLocalAnalytics(
        sqlitePath: String,
        dbPaths: [String],
        dayStart: Date,
        sevenDayStart: Date,
        statistics: StatisticsContext,
        messages: inout [String]
    ) -> LocalAnalytics {
        let calendar = statistics.calendar
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? sevenDayStart
        let sourceQuery = """
        SELECT id, rollout_path AS rolloutPath, model, cwd, updated_at AS updatedAt
        FROM threads
        WHERE rollout_path IS NOT NULL
          AND rollout_path <> ''
          AND tokens_used > 0
        ORDER BY updated_at ASC;
        """

        var seenPaths = Set<String>()
        let sources = dbPaths
            .flatMap { runSQLiteJSON(sqlitePath: sqlitePath, dbPath: $0, query: sourceQuery) }
            .compactMap { object -> SessionUsageSource? in
            guard let path = object["rolloutPath"] as? String, !path.isEmpty, seenPaths.insert(path).inserted else {
                return nil
            }
            return SessionUsageSource(
                threadId: object["id"] as? String ?? path,
                rolloutPath: path,
                model: object["model"] as? String,
                cwd: object["cwd"] as? String ?? "",
                updatedAt: dateFromEpoch(object["updatedAt"])
            )
            }

        guard !sources.isEmpty else {
            messages.append("未找到 Codex session 日志")
            return LocalAnalytics(detailedUsage: nil, usageTrend: nil, recentProjects: [], toolUsages: [], skillUsages: [])
        }

        let dayKey = statistics.dayKey(for: dayStart)
        let sourceFingerprint = sessionSourcesFingerprint(sources)

        if let cached = Self.localAnalyticsCache,
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.timeZoneIdentifier == statistics.resolvedIdentifier,
           cached.sourceFingerprint == sourceFingerprint {
            writePersistentSessionUsageCache()
            return cached.analytics
        }

        if let cached = readPersistentLocalAnalyticsCache(),
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.timeZoneIdentifier == statistics.resolvedIdentifier,
           cached.sourceFingerprint == sourceFingerprint {
            Self.localAnalyticsCache = cached
            writePersistentSessionUsageCache()
            return cached.analytics
        }

        var monthComponents = calendar.dateComponents([.year, .month], from: dayStart)
        monthComponents.day = 1
        monthComponents.hour = 0
        monthComponents.minute = 0
        monthComponents.second = 0
        let monthStart = calendar.date(from: monthComponents) ?? dayStart

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]

        var accumulator = DetailedUsageAccumulator()
        var dailyUsage: [String: PricedTokenUsage] = [:]
        var recentProjectUsage: [String: ProjectUsageAccumulator] = [:]
        var toolUsage: [String: ToolUsageAccumulator] = [:]
        var skillUsage: [String: SkillUsageAccumulator] = [:]
        for source in sources {
            guard let entry = cachedSessionUsage(
                source: source,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter
            ) else { continue }

            if entry.hasTokenEvents {
                accumulator.parsedFileCount += 1
                accumulator.tokenEventCount += entry.tokenEventCount
            }

            let price = modelTokenPrice(for: source.model)
            var sessionUsage = PricedTokenUsage.zero
            for delta in entry.deltas {
                let cost = estimatedCostUSD(tokens: delta.tokens, price: price)
                sessionUsage.add(tokens: delta.tokens, costUSD: cost)
                accumulator.add(
                    delta.tokens,
                    at: delta.date,
                    price: price,
                    dayStart: dayStart,
                    sevenDayStart: sevenDayStart,
                    monthStart: monthStart
                )

                if delta.date >= trendStart {
                    let key = statistics.dayKey(for: delta.date)
                    var usage = dailyUsage[key] ?? .zero
                    usage.add(tokens: delta.tokens, costUSD: cost)
                    dailyUsage[key] = usage
                }

                if delta.date >= sevenDayStart {
                    let projectKey = source.cwd.isEmpty ? "未归类" : source.cwd
                    let projectName = source.cwd.isEmpty ? "未归类" : shortWorkspaceName(source.cwd)
                    var project = recentProjectUsage[projectKey] ?? ProjectUsageAccumulator(
                        name: projectName,
                        fullPath: source.cwd
                    )
                    project.add(threadId: source.threadId, tokens: delta.tokens, costUSD: cost, at: delta.date)
                    recentProjectUsage[projectKey] = project
                }
            }

            let totalToolCalls = entry.toolCalls.values.reduce(0, +)
            if totalToolCalls > 0, sessionUsage.tokens.visibleTotalTokens > 0 {
                for (name, count) in entry.toolCalls {
                    let share = Double(count) / Double(totalToolCalls)
                    let estimatedTokens = Int64((Double(sessionUsage.tokens.visibleTotalTokens) * share).rounded())
                    let estimatedCost = sessionUsage.estimatedCostUSD * share
                    var usage = toolUsage[name] ?? ToolUsageAccumulator(name: name)
                    usage.addCalls(count, estimatedTokens: estimatedTokens, estimatedCostUSD: estimatedCost)
                    toolUsage[name] = usage
                }
            } else {
                for (name, count) in entry.toolCalls {
                    var usage = toolUsage[name] ?? ToolUsageAccumulator(name: name)
                    usage.addCalls(count, estimatedTokens: 0, estimatedCostUSD: 0)
                    toolUsage[name] = usage
                }
            }

            for event in entry.skillLoads {
                var usage = skillUsage[event.path] ?? SkillUsageAccumulator(path: event.path)
                usage.addLoad(threadId: source.threadId, at: event.date ?? source.updatedAt)
                skillUsage[event.path] = usage
            }
        }

        writePersistentSessionUsageCache()
        let skillUsages = makeSkillUsages(from: skillUsage)

        guard accumulator.parsedFileCount > 0, accumulator.tokenEventCount > 0 else {
            messages.append("未找到 Codex token_count 事件")
            let analytics = LocalAnalytics(
                detailedUsage: nil,
                usageTrend: nil,
                recentProjects: [],
                toolUsages: toolUsage.values
                    .map { $0.makeUsage() }
                    .sorted { $0.callCount == $1.callCount ? $0.name < $1.name : $0.callCount > $1.callCount },
                skillUsages: skillUsages
            )
            Self.localAnalyticsCache = LocalAnalyticsCacheEntry(
                version: localAnalyticsCacheVersion,
                dayKey: dayKey,
                timeZoneIdentifier: statistics.resolvedIdentifier,
                sourceFingerprint: sourceFingerprint,
                analytics: analytics
            )
            writePersistentLocalAnalyticsCache(Self.localAnalyticsCache)
            return analytics
        }

        let analytics = LocalAnalytics(
            detailedUsage: accumulator.makeUsage(),
            usageTrend: makeUsageTrend(
                dailyUsage: dailyUsage,
                dayStart: dayStart,
                sevenDayStart: sevenDayStart,
                trendStart: trendStart,
                monthStart: monthStart,
                sourceQuality: .detailed,
                calendar: calendar
            ),
            recentProjects: recentProjectUsage.values
                .map { $0.makeUsage() }
                .filter { $0.tokens > 0 }
                .sorted { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens },
            toolUsages: toolUsage.values
                .map { $0.makeUsage() }
                .sorted { $0.callCount == $1.callCount ? $0.name < $1.name : $0.callCount > $1.callCount },
            skillUsages: skillUsages
        )
        Self.localAnalyticsCache = LocalAnalyticsCacheEntry(
            version: localAnalyticsCacheVersion,
            dayKey: dayKey,
            timeZoneIdentifier: statistics.resolvedIdentifier,
            sourceFingerprint: sourceFingerprint,
            analytics: analytics
        )
        writePersistentLocalAnalyticsCache(Self.localAnalyticsCache)
        return analytics
    }

    private func makeUsageTrend(
        dailyUsage: [String: PricedTokenUsage],
        dayStart: Date,
        sevenDayStart: Date,
        trendStart: Date,
        monthStart: Date,
        sourceQuality: UsageSourceQuality,
        calendar: Calendar
    ) -> UsageTrend {
        var buckets: [UsageDayBucket] = []
        var cursor = calendar.startOfDay(for: trendStart)
        let end = calendar.startOfDay(for: dayStart)

        while cursor <= end {
            let key = localDayKey(cursor, calendar: calendar)
            buckets.append(UsageDayBucket(
                id: key,
                date: cursor,
                usage: dailyUsage[key] ?? .zero,
                sourceQuality: sourceQuality
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var sevenDay = PricedTokenUsage.zero
        var previousSevenDayTokens: Int64 = 0
        var month = PricedTokenUsage.zero
        let previousSevenDayStart = calendar.date(byAdding: .day, value: -7, to: sevenDayStart) ?? sevenDayStart

        for bucket in buckets {
            if bucket.date >= sevenDayStart {
                sevenDay.add(tokens: bucket.usage.tokens, costUSD: bucket.usage.estimatedCostUSD)
            } else if bucket.date >= previousSevenDayStart {
                previousSevenDayTokens += bucket.tokens
            }

            if bucket.date >= monthStart {
                month.add(tokens: bucket.usage.tokens, costUSD: bucket.usage.estimatedCostUSD)
            }
        }

        let peakDay = buckets
            .filter { $0.date >= sevenDayStart }
            .max { $0.tokens < $1.tokens }
        let changePercent: Double?
        let isNewActivity: Bool
        if previousSevenDayTokens > 0 {
            changePercent = (Double(sevenDay.tokens.visibleTotalTokens) - Double(previousSevenDayTokens)) / Double(previousSevenDayTokens) * 100
            isNewActivity = false
        } else {
            changePercent = nil
            isNewActivity = sevenDay.tokens.visibleTotalTokens > 0
        }

        let dayOfMonth = max(calendar.component(.day, from: dayStart), 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: dayStart)?.count ?? dayOfMonth
        let projectedMonthCostUSD: Double?
        if dayOfMonth >= 2, month.estimatedCostUSD > 0 {
            projectedMonthCostUSD = month.estimatedCostUSD / Double(dayOfMonth) * Double(daysInMonth)
        } else {
            projectedMonthCostUSD = nil
        }

        let heatmapData = makeHeatmapData(
            buckets: buckets,
            endDate: dayStart,
            weekCount: 26,
            calendar: calendar
        )

        return UsageTrend(
            dayBuckets: buckets,
            heatmapWeeks: heatmapData.weeks,
            heatmapThresholds: heatmapData.thresholds,
            summary: UsageTrendSummary(
                sevenDay: sevenDay,
                dailyAverageTokens: sevenDay.tokens.visibleTotalTokens / 7,
                peakDay: peakDay?.tokens ?? 0 > 0 ? peakDay : nil,
                changePercent: changePercent,
                isNewActivity: isNewActivity
            ),
            month: month,
            projectedMonthCostUSD: projectedMonthCostUSD,
            activeDayCount: buckets.filter { $0.tokens > 0 }.count,
            sourceQuality: sourceQuality
        )
    }

    private func makeHeatmapData(
        buckets: [UsageDayBucket],
        endDate: Date,
        weekCount: Int,
        calendar: Calendar
    ) -> (weeks: [[UsageHeatmapDay]], thresholds: [Int64]) {
        let latestDate = calendar.startOfDay(for: endDate)
        let currentWeekStart = weekStart(for: latestDate, calendar: calendar)
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: currentWeekStart) ?? currentWeekStart
        let bucketByDay = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })

        let weeks: [[UsageHeatmapDay]] = (0..<weekCount).map { weekIndex in
            (0..<7).compactMap { weekdayIndex in
                guard let date = calendar.date(byAdding: .day, value: weekIndex * 7 + weekdayIndex, to: firstWeekStart) else {
                    return nil
                }
                let key = localDayKey(date, calendar: calendar)
                let isFuture = date > latestDate
                return UsageHeatmapDay(
                    id: key,
                    date: date,
                    usage: isFuture ? nil : bucketByDay[key]?.usage,
                    isFuture: isFuture
                )
            }
        }

        let values = weeks
            .flatMap { $0 }
            .filter { !$0.isFuture }
            .map(\.tokens)
            .filter { $0 > 0 }
            .sorted()
        return (weeks, heatmapThresholds(values))
    }

    private func heatmapThresholds(_ values: [Int64]) -> [Int64] {
        guard values.count >= 5 else {
            let maxValue = max(values.max() ?? 0, 1)
            return [maxValue / 5, maxValue * 2 / 5, maxValue * 3 / 5, maxValue * 4 / 5]
                .map { max($0, 1) }
        }
        return [
            quantile(values, fraction: 0.25),
            quantile(values, fraction: 0.50),
            quantile(values, fraction: 0.75),
            quantile(values, fraction: 0.90)
        ]
    }

    private func quantile(_ values: [Int64], fraction: Double) -> Int64 {
        guard !values.isEmpty else { return 1 }
        let index = min(values.count - 1, max(0, Int((Double(values.count - 1) * fraction).rounded())))
        return max(values[index], 1)
    }

    private func weekStart(for date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: calendar.startOfDay(for: date)) ?? date
    }

    private func readApproximateUsageTrend(
        sqlitePath: String,
        dbPaths: [String],
        dayStart: Date,
        sevenDayStart: Date,
        calendar: Calendar
    ) -> UsageTrend? {
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? sevenDayStart
        var monthComponents = calendar.dateComponents([.year, .month], from: Date())
        monthComponents.day = 1
        monthComponents.hour = 0
        monthComponents.minute = 0
        monthComponents.second = 0
        let monthStart = calendar.date(from: monthComponents) ?? dayStart

        let query = """
        SELECT updated_at AS updatedAt, tokens_used AS tokens
        FROM threads
        WHERE updated_at >= \(Int(trendStart.timeIntervalSince1970))
        ORDER BY updated_at ASC;
        """

        let rows = dbPaths.flatMap {
            runSQLiteJSON(sqlitePath: sqlitePath, dbPath: $0, query: query)
        }
        guard !rows.isEmpty else { return nil }

        var dailyUsage: [String: PricedTokenUsage] = [:]
        for row in rows {
            guard let updatedAt = dateFromEpoch(row["updatedAt"]) else { continue }
            let key = localDayKey(updatedAt, calendar: calendar)
            let tokens = int64Value(row["tokens"]) ?? 0
            var usage = dailyUsage[key] ?? .zero
            usage.add(
                tokens: TokenBreakdown(
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: tokens
                ),
                costUSD: 0
            )
            dailyUsage[key] = usage
        }

        return makeUsageTrend(
            dailyUsage: dailyUsage,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            trendStart: trendStart,
            monthStart: monthStart,
            sourceQuality: .approximate,
            calendar: calendar
        )
    }

    private func readAllTimeProjects(sqlitePath: String, dbPaths: [String]) -> [ProjectUsage] {
        let query = """
        SELECT cwd, COUNT(*) AS threadCount, COALESCE(SUM(tokens_used), 0) AS tokens, MAX(CASE WHEN recency_at > 0 THEN recency_at ELSE updated_at END) AS lastActiveAt
        FROM threads
        WHERE tokens_used > 0
        GROUP BY cwd
        ORDER BY tokens DESC
        LIMIT 24;
        """

        let projects = dbPaths.flatMap { dbPath in
            runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query).map { row in
            let path = row["cwd"] as? String ?? ""
            return ProjectUsage(
                id: path.isEmpty ? "uncategorized" : path,
                name: path.isEmpty ? "未归类" : shortWorkspaceName(path),
                fullPath: path,
                tokens: int64Value(row["tokens"]) ?? 0,
                estimatedCostUSD: nil,
                threadCount: intValue(row["threadCount"]) ?? 0,
                lastActiveAt: dateFromEpoch(row["lastActiveAt"]),
                sourceQuality: .approximate
            )
            }
        }
        return mergeApproximateProjects(projects)
    }

    private func readApproximateRecentProjects(
        sqlitePath: String,
        dbPaths: [String],
        sevenDayStart: Date
    ) -> [ProjectUsage] {
        let query = """
        SELECT cwd, COUNT(*) AS threadCount, COALESCE(SUM(tokens_used), 0) AS tokens, MAX(CASE WHEN recency_at > 0 THEN recency_at ELSE updated_at END) AS lastActiveAt
        FROM threads
        WHERE tokens_used > 0
          AND updated_at >= \(Int(sevenDayStart.timeIntervalSince1970))
        GROUP BY cwd
        ORDER BY tokens DESC
        LIMIT 24;
        """

        let projects = dbPaths.flatMap { dbPath in
            runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query).map { row in
            let path = row["cwd"] as? String ?? ""
            return ProjectUsage(
                id: path.isEmpty ? "uncategorized" : path,
                name: path.isEmpty ? "未归类" : shortWorkspaceName(path),
                fullPath: path,
                tokens: int64Value(row["tokens"]) ?? 0,
                estimatedCostUSD: nil,
                threadCount: intValue(row["threadCount"]) ?? 0,
                lastActiveAt: dateFromEpoch(row["lastActiveAt"]),
                sourceQuality: .approximate
            )
            }
        }
        return mergeApproximateProjects(projects)
    }

    private func mergeApproximateProjects(_ projects: [ProjectUsage]) -> [ProjectUsage] {
        struct ProjectTotals {
            var tokens: Int64 = 0
            var threadCount: Int = 0
            var lastActiveAt: Date?
        }

        var totalsByPath: [String: ProjectTotals] = [:]
        for project in projects {
            var totals = totalsByPath[project.fullPath] ?? ProjectTotals()
            totals.tokens += project.tokens
            totals.threadCount += project.threadCount
            if let candidate = project.lastActiveAt,
               totals.lastActiveAt == nil || candidate > (totals.lastActiveAt ?? .distantPast) {
                totals.lastActiveAt = candidate
            }
            totalsByPath[project.fullPath] = totals
        }

        var merged: [ProjectUsage] = []
        merged.reserveCapacity(totalsByPath.count)
        for (path, totals) in totalsByPath {
            let project = ProjectUsage(
                id: path.isEmpty ? "uncategorized" : path,
                name: path.isEmpty ? "未归类" : shortWorkspaceName(path),
                fullPath: path,
                tokens: totals.tokens,
                estimatedCostUSD: nil,
                threadCount: totals.threadCount,
                lastActiveAt: totals.lastActiveAt,
                sourceQuality: .approximate
            )
            merged.append(project)
        }
        merged.sort { left, right in
            left.tokens == right.tokens ? left.name < right.name : left.tokens > right.tokens
        }
        return Array(merged.prefix(24))
    }

    private func makeSkillUsages(from accumulators: [String: SkillUsageAccumulator]) -> [SkillUsage] {
        accumulators.values
            .map { accumulator in
                accumulator.makeUsage(staticInfo: skillStaticInfo(for: accumulator.path))
            }
            .sorted {
                if $0.loadCount != $1.loadCount { return $0.loadCount > $1.loadCount }
                if ($0.staticTokenEstimate ?? -1) != ($1.staticTokenEstimate ?? -1) {
                    return ($0.staticTokenEstimate ?? -1) > ($1.staticTokenEstimate ?? -1)
                }
                return $0.name < $1.name
            }
    }

    private func skillStaticInfo(for path: String) -> SkillStaticInfo {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let allowedRoots = [
            home.appendingPathComponent(".codex/skills", isDirectory: true),
            home.appendingPathComponent(".codex/plugins", isDirectory: true),
            home.appendingPathComponent(".openclaw/workspace/skills", isDirectory: true)
        ]
        guard allowedRoots.contains(where: { root in
            url.path.hasPrefix(root.path + "/")
        }) else {
            return SkillStaticInfo(tokenEstimate: nil, byteCount: nil)
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let byteCount = (attributes[.size] as? NSNumber)?.int64Value,
              byteCount <= 1_000_000,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else {
            return SkillStaticInfo(tokenEstimate: nil, byteCount: nil)
        }

        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return SkillStaticInfo(
            tokenEstimate: estimateStaticTokens(text),
            byteCount: byteCount
        )
    }

    private func cachedSessionUsage(
        source: SessionUsageSource,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter
    ) -> SessionUsageCacheEntry? {
        let url = URL(fileURLWithPath: source.rolloutPath)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.int64Value
        else { return nil }

        let modificationDate = attributes[.modificationDate] as? Date
        if let cached = memorySessionUsageCacheEntry(for: source.rolloutPath),
           sameSessionFileIdentity(cached, fileSize: fileSize, modificationDate: modificationDate) {
            return cached
        }

        if let cached = persistentSessionUsageCache()[source.rolloutPath],
           sameSessionFileIdentity(cached, fileSize: fileSize, modificationDate: modificationDate) {
            storeSessionUsageCacheEntry(cached, for: source.rolloutPath, markDirty: false)
            return cached
        }

        let eventPattern = #""type":"(token_count|function_call|custom_tool_call)""#
        let tokenCountNeedle = Data(#""type":"token_count""#.utf8)
        let functionCallNeedle = Data(#""type":"function_call""#.utf8)
        let customToolCallNeedle = Data(#""type":"custom_tool_call""#.utf8)
        if let parsed = parseSessionUsageWithGrep(
            url: url,
            eventPattern: eventPattern,
            tokenCountNeedle: tokenCountNeedle,
            functionCallNeedle: functionCallNeedle,
            customToolCallNeedle: customToolCallNeedle,
            fractionalFormatter: fractionalFormatter,
            plainFormatter: plainFormatter
        ) {
            let entry = SessionUsageCacheEntry(
                fileSize: fileSize,
                modificationDate: modificationDate,
                hasTokenEvents: parsed.hasTokenEvents,
                tokenEventCount: parsed.tokenEventCount,
                deltas: parsed.deltas,
                toolCalls: parsed.toolCalls,
                skillLoads: parsed.skillLoads
            )
            storeSessionUsageCacheEntry(entry, for: source.rolloutPath)
            return entry
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var buffer = Data()
        var previous = TokenBreakdown.zero
        var sawTokenEvent = false
        var tokenEventCount = 0
        var deltas: [SessionUsageDelta] = []
        var toolCalls: [String: Int] = [:]
        var skillLoads: [SkillLoadEvent] = []

        while true {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 10) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                processSessionLine(
                    lineData,
                    tokenCountNeedle: tokenCountNeedle,
                    functionCallNeedle: functionCallNeedle,
                    customToolCallNeedle: customToolCallNeedle,
                    fractionalFormatter: fractionalFormatter,
                    plainFormatter: plainFormatter,
                    previous: &previous,
                    sawTokenEvent: &sawTokenEvent,
                    tokenEventCount: &tokenEventCount,
                    deltas: &deltas,
                    toolCalls: &toolCalls,
                    skillLoads: &skillLoads
                )
            }
        }

        if !buffer.isEmpty {
            processSessionLine(
                buffer,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                previous: &previous,
                sawTokenEvent: &sawTokenEvent,
                tokenEventCount: &tokenEventCount,
                deltas: &deltas,
                toolCalls: &toolCalls,
                skillLoads: &skillLoads
            )
        }

        let entry = SessionUsageCacheEntry(
            fileSize: fileSize,
            modificationDate: modificationDate,
            hasTokenEvents: sawTokenEvent,
            tokenEventCount: tokenEventCount,
            deltas: deltas,
            toolCalls: toolCalls,
            skillLoads: skillLoads
        )
        storeSessionUsageCacheEntry(entry, for: source.rolloutPath)
        return entry
    }

    private func memorySessionUsageCacheEntry(for key: String) -> SessionUsageCacheEntry? {
        guard let entry = Self.sessionUsageCache[key] else { return nil }
        Self.sessionUsageCacheOrder.removeAll { $0 == key }
        Self.sessionUsageCacheOrder.append(key)
        return entry
    }

    private func storeSessionUsageCacheEntry(
        _ entry: SessionUsageCacheEntry,
        for key: String,
        markDirty: Bool = true
    ) {
        Self.sessionUsageCache[key] = entry
        if markDirty {
            Self.persistentSessionUsageCacheIsDirty = true
        }
        Self.sessionUsageCacheOrder.removeAll { $0 == key }
        Self.sessionUsageCacheOrder.append(key)
        while Self.sessionUsageCacheOrder.count > Self.sessionUsageCacheLimit {
            let evicted = Self.sessionUsageCacheOrder.removeFirst()
            Self.sessionUsageCache.removeValue(forKey: evicted)
        }
    }

    private func parseSessionUsageWithGrep(
        url: URL,
        eventPattern: String,
        tokenCountNeedle: Data,
        functionCallNeedle: Data,
        customToolCallNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter
    ) -> (hasTokenEvents: Bool, tokenEventCount: Int, deltas: [SessionUsageDelta], toolCalls: [String: Int], skillLoads: [SkillLoadEvent])? {
        let grepPath = "/usr/bin/grep"
        guard fileManager.isExecutableFile(atPath: grepPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: grepPath)
        process.arguments = ["-a", "-E", eventPattern, url.path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }

        var buffer = data
        var previous = TokenBreakdown.zero
        var sawTokenEvent = false
        var tokenEventCount = 0
        var deltas: [SessionUsageDelta] = []
        var toolCalls: [String: Int] = [:]
        var skillLoads: [SkillLoadEvent] = []

        while let newline = buffer.firstIndex(of: 10) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            processSessionLine(
                lineData,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                previous: &previous,
                sawTokenEvent: &sawTokenEvent,
                tokenEventCount: &tokenEventCount,
                deltas: &deltas,
                toolCalls: &toolCalls,
                skillLoads: &skillLoads
            )
        }

        if !buffer.isEmpty {
            processSessionLine(
                buffer,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                previous: &previous,
                sawTokenEvent: &sawTokenEvent,
                tokenEventCount: &tokenEventCount,
                deltas: &deltas,
                toolCalls: &toolCalls,
                skillLoads: &skillLoads
            )
        }

        return (sawTokenEvent, tokenEventCount, deltas, toolCalls, skillLoads)
    }

    private func processSessionLine(
        _ lineData: Data,
        tokenCountNeedle: Data,
        functionCallNeedle: Data,
        customToolCallNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter,
        previous: inout TokenBreakdown,
        sawTokenEvent: inout Bool,
        tokenEventCount: inout Int,
        deltas: inout [SessionUsageDelta],
        toolCalls: inout [String: Int],
        skillLoads: inout [SkillLoadEvent]
    ) {
        let isTokenEvent = lineData.range(of: tokenCountNeedle) != nil
        let isToolEvent = lineData.range(of: functionCallNeedle) != nil || lineData.range(of: customToolCallNeedle) != nil
        guard isTokenEvent || isToolEvent,
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String
        else { return }

        if payloadType == "function_call" || payloadType == "custom_tool_call" {
            if let name = payload["name"] as? String, !name.isEmpty {
                toolCalls[name, default: 0] += 1
            }
            let paths = skillLoadPaths(in: payload)
            guard !paths.isEmpty else { return }
            let eventDate = (object["timestamp"] as? String).flatMap {
                fractionalFormatter.date(from: $0) ?? plainFormatter.date(from: $0)
            }
            for path in paths {
                skillLoads.append(SkillLoadEvent(path: path, date: eventDate))
            }
            return
        }

        guard payloadType == "token_count",
              let timestamp = object["timestamp"] as? String,
              let info = payload["info"] as? [String: Any]
        else { return }

        let totalUsage = (info["total_token_usage"] as? [String: Any]).map(tokenBreakdown)
        let lastUsage = (info["last_token_usage"] as? [String: Any]).map(tokenBreakdown)
        guard let delta = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: totalUsage,
            lastUsage: lastUsage,
            previousTotal: &previous
        ) else { return }

        sawTokenEvent = true
        tokenEventCount += 1
        guard !delta.isZero,
              let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp)
        else { return }
        deltas.append(SessionUsageDelta(date: date, tokens: delta))
    }

    private func tokenBreakdown(_ usage: [String: Any]) -> TokenBreakdown {
        TokenBreakdown(
            inputTokens: int64Value(usage["input_tokens"]) ?? 0,
            cachedInputTokens: int64Value(usage["cached_input_tokens"]) ?? 0,
            outputTokens: int64Value(usage["output_tokens"]) ?? 0,
            reasoningOutputTokens: int64Value(usage["reasoning_output_tokens"]) ?? 0,
            totalTokens: int64Value(usage["total_tokens"]) ?? 0
        )
    }

    private func readTaskBoard(context: RuntimeLoadContext, messages: inout [String]) -> TaskBoard? {
        let calendar = context.statistics.calendar
        let now = context.now
        let dayStart = calendar.startOfDay(for: now)
        let activeCutoff = now.addingTimeInterval(-2 * 60 * 60)

        var activeItems: [TaskItem] = []
        var pendingItems: [TaskItem] = []
        var doneItems: [TaskItem] = []

        let home = context.homeDirectory.path
        if let dbPath = firstExistingPath([
            home + "/.codex/state_5.sqlite",
            home + "/.codex/sqlite/state_5.sqlite"
        ]), let sqlitePath = firstExistingPath([
            "/usr/bin/sqlite3",
            "/opt/homebrew/bin/sqlite3",
            "/opt/homebrew/share/android-commandlinetools/platform-tools/sqlite3"
        ]) {
            let todayThreadsQuery = """
            SELECT id, title, preview, first_user_message AS firstUserMessage,
                   rollout_path AS rolloutPath, cwd, tokens_used AS tokens,
                   updated_at AS updatedAt, recency_at AS recencyAt, model
            FROM threads
            WHERE archived = 0
              AND preview <> ''
              AND (
                updated_at >= \(Int(dayStart.timeIntervalSince1970))
                OR recency_at >= \(Int(dayStart.timeIntervalSince1970))
                OR created_at >= \(Int(dayStart.timeIntervalSince1970))
              )
            ORDER BY recency_at DESC, updated_at DESC;
            """

            let archivedTodayQuery = """
            SELECT id, title, preview, first_user_message AS firstUserMessage,
                   rollout_path AS rolloutPath, cwd, tokens_used AS tokens,
                   COALESCE(archived_at, updated_at) AS updatedAt, model
            FROM threads
            WHERE archived = 1
              AND COALESCE(archived_at, updated_at) >= \(Int(dayStart.timeIntervalSince1970))
            ORDER BY COALESCE(archived_at, updated_at) DESC;
            """

            let todayThreads = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: todayThreadsQuery)
            for object in todayThreads {
                let updatedAt = dateFromEpoch(object["recencyAt"]) ?? dateFromEpoch(object["updatedAt"])
                let kind: TaskColumnKind = (updatedAt ?? .distantPast) >= activeCutoff ? .active : .pending
                let item = makeThreadTaskItem(object: object, updatedAt: updatedAt, kind: kind)
                if kind == .active {
                    activeItems.append(item)
                } else {
                    pendingItems.append(item)
                }
            }

            doneItems = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: archivedTodayQuery).map { object in
                makeThreadTaskItem(object: object, updatedAt: dateFromEpoch(object["updatedAt"]), kind: .done)
            }
        } else {
            messages.append("任务看板未找到 SQLite 数据源")
        }

        let scheduledItems = readAutomationTasks(homeDirectory: context.homeDirectory)

        return TaskBoard(refreshedAt: Date(), columns: [
            TaskColumn(id: .active, title: "进行中", count: activeItems.count, items: activeItems),
            TaskColumn(id: .pending, title: "待处理", count: pendingItems.count, items: pendingItems),
            TaskColumn(id: .scheduled, title: "定时", count: scheduledItems.count, items: scheduledItems),
            TaskColumn(id: .done, title: "完成", count: doneItems.count, items: doneItems)
        ])
    }

    private func makeThreadTaskItem(object: [String: Any], updatedAt: Date?, kind: TaskColumnKind) -> TaskItem {
        let rawThreadID = object["id"] as? String
        let rawId = rawThreadID ?? UUID().uuidString
        let title = normalizedTitle(object["title"] as? String, fallback: object["preview"] as? String)
        let cwd = object["cwd"] as? String ?? ""
        let tokens = int64Value(object["tokens"]) ?? 0
        let compactId = rawId.replacingOccurrences(of: "-", with: "")
        let code = "COD-" + compactId.suffix(4).uppercased()
        let chip: String

        switch kind {
        case .active:
            chip = tokens >= 5_000_000 ? "High" : "Active"
        case .pending:
            chip = tokens >= 2_000_000 ? "Medium" : "Idle"
        case .scheduled:
            chip = "Cron"
        case .done:
            chip = "Done"
        }

        let detailParts = [
            shortWorkspaceName(cwd),
            tokens > 0 ? formatTokens(tokens) : nil
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let summary = taskDisplayText(
            (object["firstUserMessage"] as? String) ?? (object["preview"] as? String),
            limit: 1_200
        )
        let recentReply = lastCodexAssistantReply(at: object["rolloutPath"] as? String)

        return TaskItem(
            id: "codex:\(rawId):\(kind.rawValue)",
            code: String(code),
            title: title,
            detail: detailParts.joined(separator: " · "),
            chip: chip,
            updatedAt: updatedAt,
            tokens: tokens,
            kind: kind,
            source: .codex,
            summary: summary,
            recentReply: recentReply,
            timing: nil,
            progress: kind == .done ? TaskProgress(percent: 100, origin: .completedStatus) : nil,
            navigationTarget: TaskNavigationTarget.codexThread(id: rawThreadID)
        )
    }

    private func lastCodexAssistantReply(at path: String?) -> String? {
        guard let path, !path.isEmpty,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = min(fileSize, 1_500_000)
        try? handle.seek(toOffset: fileSize - readSize)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        for rawLine in data.split(separator: 10).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "assistant",
                  let content = payload["content"] as? [[String: Any]] else {
                continue
            }
            let text = content.compactMap { item -> String? in
                guard item["type"] as? String == "output_text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
            if let compact = taskDisplayText(text, limit: 1_600) {
                return compact
            }
        }
        return nil
    }

    private func readAutomationTasks(homeDirectory: URL) -> [TaskItem] {
        let root = homeDirectory.appendingPathComponent(".codex/automations")
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var items: [TaskItem] = []
        for case let url as URL in enumerator where url.lastPathComponent == "automation.toml" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let fields = parseSimpleTOML(text)
            guard (fields["status"] ?? "").uppercased() == "ACTIVE" else { continue }

            let id = fields["id"] ?? url.deletingLastPathComponent().lastPathComponent
            let name = fields["name"] ?? id
            let kind = fields["kind"] ?? "cron"
            let schedule = scheduleSummary(fields["rrule"])
            let detail = [kind.uppercased(), schedule].filter { !$0.isEmpty }.joined(separator: " · ")

            items.append(TaskItem(
                id: "codex:automation:" + id,
                code: "AUTO-" + id.prefix(4).uppercased(),
                title: name,
                detail: detail,
                chip: kind == "heartbeat" ? "Wake" : "Cron",
                updatedAt: dateFromEpoch(fields["updated_at"]),
                tokens: nil,
                kind: .scheduled,
                source: .codex,
                summary: taskDisplayText(detail, limit: 1_200),
                recentReply: nil,
                timing: nil,
                progress: nil,
                navigationTarget: nil
            ))
        }

        return items.sorted { $0.title < $1.title }
    }

    private func runSQLiteJSON(sqlitePath: String, dbPath: String, query: String) -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = ["-readonly", "-json", dbPath, query]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard
            process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return json
    }

    private func resolveCodexExecutablePath() -> String? {
        if let override = ProcessInfo.processInfo.environment["CODEXU_CODEX_EXECUTABLE_OVERRIDE"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        var candidates: [String] = []

        // The app's display name and install path may change, while its bundle identifier remains stable.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(
                appURL
                    .appendingPathComponent("Contents/Resources/codex")
                    .path
            )
        }

        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])

        return firstExistingPath(candidates)
    }

    private func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { fileManager.isExecutableFile(atPath: $0) || fileManager.fileExists(atPath: $0) }
    }

    private func localAnalyticsCacheURL() -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent("codexU", isDirectory: true)
            .appendingPathComponent("local-analytics-v2.json")
    }

    private func sessionUsageCacheURL() -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent("codexU", isDirectory: true)
            .appendingPathComponent("session-usage-v1.json")
    }

    private func readPersistentLocalAnalyticsCache() -> LocalAnalyticsCacheEntry? {
        guard let url = localAnalyticsCacheURL(),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(LocalAnalyticsCacheEntry.self, from: data)
    }

    private func persistentSessionUsageCache() -> [String: SessionUsageCacheEntry] {
        if let cache = Self.persistentSessionUsageCache {
            return cache
        }

        guard let url = sessionUsageCacheURL(),
              let data = try? Data(contentsOf: url),
              let diskCache = try? JSONDecoder().decode(SessionUsageDiskCache.self, from: data),
              diskCache.version == sessionUsageCacheVersion
        else {
            Self.persistentSessionUsageCache = [:]
            return [:]
        }

        let entries = limitedSessionUsageCache(diskCache.entries)
        Self.persistentSessionUsageCache = entries
        return entries
    }

    private func writePersistentLocalAnalyticsCache(_ entry: LocalAnalyticsCacheEntry?) {
        guard let entry, let url = localAnalyticsCacheURL() else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(entry)
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("failed to write local analytics cache: \(error.localizedDescription)")
        }
    }

    private func writePersistentSessionUsageCache() {
        guard Self.persistentSessionUsageCacheIsDirty else { return }
        let now = Date()
        if let lastWrite = Self.lastPersistentSessionUsageCacheWriteAt,
           now.timeIntervalSince(lastWrite) < Self.persistentSessionUsageCacheWriteInterval {
            return
        }
        guard let url = sessionUsageCacheURL() else { return }
        let mergedEntries = limitedSessionUsageCache(
            persistentSessionUsageCache().merging(Self.sessionUsageCache) { _, new in new }
        )
        Self.persistentSessionUsageCache = mergedEntries

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(SessionUsageDiskCache(version: sessionUsageCacheVersion, entries: mergedEntries))
            try data.write(to: url, options: .atomic)
            Self.persistentSessionUsageCacheIsDirty = false
            Self.lastPersistentSessionUsageCacheWriteAt = now
        } catch {
            debugLog("failed to write session usage cache: \(error.localizedDescription)")
        }
    }

    private func limitedSessionUsageCache(
        _ entries: [String: SessionUsageCacheEntry]
    ) -> [String: SessionUsageCacheEntry] {
        guard entries.count > Self.sessionUsageCacheLimit else { return entries }
        let retained = entries.sorted { lhs, rhs in
            let lhsDate = lhs.value.modificationDate ?? .distantPast
            let rhsDate = rhs.value.modificationDate ?? .distantPast
            return lhsDate == rhsDate ? lhs.key < rhs.key : lhsDate > rhsDate
        }.prefix(Self.sessionUsageCacheLimit)
        return Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }

    private func sameSessionFileIdentity(
        _ cached: SessionUsageCacheEntry,
        fileSize: Int64,
        modificationDate: Date?
    ) -> Bool {
        guard cached.fileSize == fileSize else { return false }
        let cachedMs = Int64((cached.modificationDate?.timeIntervalSince1970 ?? -1) * 1000)
        let currentMs = Int64((modificationDate?.timeIntervalSince1970 ?? -1) * 1000)
        return cachedMs == currentMs
    }

    private func sessionSourcesFingerprint(_ sources: [SessionUsageSource]) -> String {
        var components: [String] = [String(sources.count)]
        for source in sources {
            components.append(source.threadId)
            components.append(source.rolloutPath)
            components.append(source.model ?? "")
            components.append(source.cwd)
            let updatedMs = Int64((source.updatedAt?.timeIntervalSince1970 ?? -1) * 1_000)
            components.append(String(updatedMs))
            guard let attributes = try? fileManager.attributesOfItem(atPath: source.rolloutPath) else {
                components.append("missing")
                continue
            }
            components.append(String((attributes[.size] as? NSNumber)?.int64Value ?? -1))
            let modifiedMs = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1) * 1000)
            components.append(String(modifiedMs))
        }
        return components.joined(separator: "|")
    }
}

private func skillLoadPaths(in payload: [String: Any]) -> [String] {
    var candidates: [String] = []
    for key in ["arguments", "input", "cmd", "command"] {
        if let text = serializedStringValue(payload[key]) {
            candidates.append(text)
        }
    }

    var paths: [String] = []
    var seen = Set<String>()
    for candidate in candidates {
        for path in extractSkillPaths(from: candidate) where seen.insert(path).inserted {
            paths.append(path)
        }
    }
    return paths
}

private func serializedStringValue(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
        return string
    }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let string = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    return string
}

private func extractSkillPaths(from text: String) -> [String] {
    let pattern = "(?:(?:~|/)[^\\s\\\"'`<>,;)]*SKILL\\.md)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    var paths: [String] = []
    var seen = Set<String>()
    regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
        guard let match, let range = Range(match.range, in: text) else { return }
        let rawPath = String(text[range])
        guard let path = canonicalSkillPath(rawPath), seen.insert(path).inserted else { return }
        paths.append(path)
    }
    return paths
}

private func canonicalSkillPath(_ rawPath: String) -> String? {
    let trimmed = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t\"'`;,.)]"))
    guard trimmed.hasSuffix("/SKILL.md") || trimmed == "SKILL.md" else { return nil }

    let home = NSHomeDirectory()
    let expanded: String
    if trimmed == "~" {
        expanded = home
    } else if trimmed.hasPrefix("~/") {
        expanded = home + String(trimmed.dropFirst())
    } else {
        expanded = trimmed
    }

    guard expanded.hasPrefix("/") else { return nil }
    let standardized = (expanded as NSString).standardizingPath
    if FileManager.default.fileExists(atPath: standardized) {
        return standardized
    }
    if let equivalentPath = equivalentCachedSkillPath(for: standardized) {
        return equivalentPath
    }
    if standardized.hasPrefix(home + "/") {
        return standardized
    }
    return nil
}

private func equivalentCachedSkillPath(for path: String) -> String? {
    let components = path.split(separator: "/").map(String.init)
    guard let cacheIndex = components.firstIndex(of: "cache"),
          components.count > cacheIndex + 5,
          components[cacheIndex + 1].hasPrefix("openai-"),
          let skillsIndex = components.lastIndex(of: "skills"),
          components.count > skillsIndex + 2,
          components.last == "SKILL.md"
    else {
        return nil
    }

    let family = components[cacheIndex + 1]
    let plugin = components[cacheIndex + 2]
    let skill = components[skillsIndex + 1]
    let cacheRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/plugins/cache")
        .appendingPathComponent(family)
        .appendingPathComponent(plugin)

    guard let versions = try? FileManager.default.contentsOfDirectory(
        at: cacheRoot,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let candidates = versions
        .map { versionURL in
            versionURL
                .appendingPathComponent("skills")
                .appendingPathComponent(skill)
                .appendingPathComponent("SKILL.md")
        }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        .sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }

    return candidates.first?.path
}

private func skillName(from path: String) -> String {
    URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
}

private func skillSourceLabel(from path: String) -> String {
    let displayPath = displayHomePath(path)
    let components = path.split(separator: "/").map(String.init)

    if let cacheIndex = components.firstIndex(of: "cache"), components.count > cacheIndex + 2 {
        let family = components[cacheIndex + 1]
        let plugin = components[cacheIndex + 2]
        return "\(family)/\(plugin)"
    }
    if displayPath.contains("/ai-infra/skills/") {
        return "ai-infra"
    }
    if displayPath.contains("/.agents/skills/") {
        return "agents"
    }
    if displayPath.contains("/.codex/skills/.system/") {
        return "system"
    }
    if displayPath.contains("/.codex/skills/") {
        return "personal"
    }
    return displayPath
}

private func displayHomePath(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home {
        return "~"
    }
    if path.hasPrefix(home + "/") {
        return "~" + String(path.dropFirst(home.count))
    }
    return path
}

private func estimateStaticTokens(_ text: String) -> Int64 {
    let scalars = Array(text.unicodeScalars)
    guard !scalars.isEmpty else { return 0 }

    let whitespaceCount = scalars.filter { CharacterSet.whitespacesAndNewlines.contains($0) }.count
    let cjkCount = scalars.filter { scalar in
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
            || (0x3040...0x30FF).contains(Int(scalar.value))
            || (0xAC00...0xD7AF).contains(Int(scalar.value))
    }.count
    let nonWhitespaceCount = max(0, scalars.count - whitespaceCount)
    let nonCJKCount = max(0, nonWhitespaceCount - cjkCount)
    let estimate = (Double(nonCJKCount) / 3.8) + Double(cjkCount)
    return max(1, Int64(estimate.rounded(.up)))
}

private func modelTokenPrice(for model: String?) -> ModelTokenPrice {
    let normalized = (model ?? "").lowercased()

    if normalized.contains("gpt-5.5-pro") {
        return ModelTokenPrice(model: "gpt-5.5-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180)
    }
    if normalized.contains("gpt-5.5") || normalized == "chat-latest" {
        return ModelTokenPrice(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30)
    }
    if normalized.contains("gpt-5.4-mini") {
        return ModelTokenPrice(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5)
    }
    if normalized.contains("gpt-5.4-nano") {
        return ModelTokenPrice(model: "gpt-5.4-nano", inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25)
    }
    if normalized.contains("gpt-5.4-pro") {
        return ModelTokenPrice(model: "gpt-5.4-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180)
    }
    if normalized.contains("gpt-5.4") {
        return ModelTokenPrice(model: "gpt-5.4", inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15)
    }
    if normalized.contains("gpt-5.3-codex")
        || normalized.contains("gpt-5.2-codex")
        || normalized.contains("gpt-5.3-chat")
        || normalized.contains("gpt-5.2") {
        return ModelTokenPrice(model: "gpt-5.2-codex", inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14)
    }
    if normalized.contains("gpt-5-codex") || normalized == "gpt-5" {
        return ModelTokenPrice(model: "gpt-5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10)
    }

    return ModelTokenPrice(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30)
}

private func estimatedCostUSD(tokens: TokenBreakdown, price: ModelTokenPrice) -> Double {
    let uncachedInputCost = Double(tokens.uncachedInputTokens) / 1_000_000 * price.inputPerMillion
    let cachedInputCost = Double(tokens.billableCachedInputTokens) / 1_000_000 * price.cachedInputPerMillion
    let outputCost = Double(max(tokens.outputTokens, 0)) / 1_000_000 * price.outputPerMillion
    return uncachedInputCost + cachedInputCost + outputCost
}

private func parseSimpleTOML(_ text: String) -> [String: String] {
    var fields: [String: String] = [:]

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
            continue
        }

        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }

        fields[key] = value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    return fields
}

private func normalizedTitle(_ title: String?, fallback: String?) -> String {
    let raw = [title, fallback]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? "Untitled"

    let singleLine = raw
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

    if singleLine.count <= 48 { return singleLine }
    return String(singleLine.prefix(45)) + "..."
}

private func taskDisplayText(_ value: String?, limit: Int) -> String? {
    guard let value else { return nil }
    let compact = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return nil }
    if compact.count <= limit { return compact }
    return String(compact.prefix(max(1, limit - 1))) + "…"
}

private func shortWorkspaceName(_ path: String) -> String {
    guard !path.isEmpty else { return "" }
    let url = URL(fileURLWithPath: path)
    let name = url.lastPathComponent
    if !name.isEmpty { return name }
    return path
}

private func relativeTimeText(_ date: Date, language: WidgetLanguage) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return language.text("刚刚", "just now") }
    let minutes = seconds / 60
    if minutes < 60 { return language.text("\(minutes) 分钟前", "\(minutes)m ago") }
    let hours = minutes / 60
    if hours < 24 { return language.text("\(hours) 小时前", "\(hours)h ago") }
    return language.text("\(hours / 24) 天前", "\(hours / 24)d ago")
}

private func scheduleSummary(_ rrule: String?) -> String {
    guard let rrule, !rrule.isEmpty else { return "" }

    var timeText = ""
    if let range = rrule.range(of: #"T(\d{2})(\d{2})(\d{2})"#, options: .regularExpression) {
        let match = String(rrule[range])
        let start = match.index(after: match.startIndex)
        let hourEnd = match.index(start, offsetBy: 2)
        let minuteEnd = match.index(hourEnd, offsetBy: 2)
        timeText = "\(match[start..<hourEnd]):\(match[hourEnd..<minuteEnd])"
    }

    if rrule.contains("FREQ=DAILY") {
        return timeText.isEmpty ? "每天" : "每天 \(timeText)"
    }
    if rrule.contains("FREQ=WEEKLY") {
        return timeText.isEmpty ? "每周" : "每周 \(timeText)"
    }
    if rrule.contains("FREQ=HOURLY") {
        return "每小时"
    }
    return timeText
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let int64 = value as? Int64 { return Int(int64) }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String { return Int(string) }
    return nil
}

private func int64Value(_ value: Any?) -> Int64? {
    if let int = value as? Int { return Int64(int) }
    if let int64 = value as? Int64 { return int64 }
    if let double = value as? Double { return Int64(double) }
    if let string = value as? String { return Int64(string) }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let int64 = value as? Int64 { return Double(int64) }
    if let string = value as? String { return Double(string) }
    return nil
}

private func stringValue(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

private func dateFromEpoch(_ value: Any?) -> Date? {
    guard var seconds = doubleValue(value), seconds > 0 else { return nil }
    if seconds > 10_000_000_000 {
        seconds /= 1000
    }
    return Date(timeIntervalSince1970: seconds)
}

enum WidgetLanguage: String, CaseIterable, Equatable {
    case zh
    case en

    static let storageKey = "codexU.interfaceLanguage"

    static var automatic: WidgetLanguage {
        let identifier = TimeZone.current.identifier
        let chineseTimeZones: Set<String> = [
            "Asia/Shanghai",
            "Asia/Chongqing",
            "Asia/Harbin",
            "Asia/Urumqi",
            "Asia/Hong_Kong",
            "Asia/Macau",
            "Asia/Taipei"
        ]
        return chineseTimeZones.contains(identifier) ? .zh : .en
    }

    var isChinese: Bool { self == .zh }

    static func storedOrAutomatic(defaults: UserDefaults = .standard) -> WidgetLanguage {
        guard let rawValue = defaults.string(forKey: storageKey),
              let language = WidgetLanguage(rawValue: rawValue)
        else { return .automatic }
        return language
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    func text(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}

enum WidgetThemeMode: String, CaseIterable, Equatable {
    case system
    case light
    case dark

    static let storageKey = "codexU.interfaceThemeMode"

    static func storedOrAutomatic(defaults: UserDefaults = .standard) -> WidgetThemeMode {
        guard let rawValue = defaults.string(forKey: storageKey),
              let mode = WidgetThemeMode(rawValue: rawValue)
        else { return .system }
        return mode
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    func applyAppearance() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum ParticleAnimationMode: String, CaseIterable, Equatable {
    case standard = "default"
    case powerSaving = "powerSaving"

    static let storageKey = "codexU.particleAnimationMode"

    static func storedOrDefault(defaults: UserDefaults = .standard) -> ParticleAnimationMode {
        guard let rawValue = defaults.string(forKey: storageKey),
              let mode = ParticleAnimationMode(rawValue: rawValue)
        else { return .standard }
        return mode
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

final class AppSettings: ObservableObject {
    private static let keepMainWindowOnTopKey = "codexU.keepMainWindowOnTop"
    private static let keepRunningWhenMainWindowClosedKey = "codexU.keepRunningWhenMainWindowClosed"
    private static let visibleRuntimeScopesKey = "codexU.visibleRuntimeScopes"
    private static let selectedAgentRuntimeKey = "codexU.selectedAgentRuntime.v1"
    private static let multiAgentSelectionMigrationKey = "codexU.multiAgentSelectionMigrationV1"
    private static let automaticUpdateChecksEnabledKey = "codexU.update.autoCheckEnabled"
    private static let skippedUpdateVersionKey = "codexU.update.skippedVersion"

    private let defaults: UserDefaults

    @Published var language: WidgetLanguage {
        didSet {
            language.persist(defaults: defaults)
        }
    }

    @Published var themeMode: WidgetThemeMode {
        didSet {
            themeMode.persist(defaults: defaults)
            themeMode.applyAppearance()
        }
    }

    @Published var particleAnimationMode: ParticleAnimationMode {
        didSet {
            particleAnimationMode.persist(defaults: defaults)
        }
    }

    @Published var keepMainWindowOnTop: Bool {
        didSet {
            defaults.set(keepMainWindowOnTop, forKey: Self.keepMainWindowOnTopKey)
        }
    }

    @Published var keepRunningWhenMainWindowClosed: Bool {
        didSet {
            defaults.set(keepRunningWhenMainWindowClosed, forKey: Self.keepRunningWhenMainWindowClosedKey)
        }
    }

    @Published var automaticUpdateChecksEnabled: Bool {
        didSet {
            defaults.set(automaticUpdateChecksEnabled, forKey: Self.automaticUpdateChecksEnabledKey)
        }
    }

    @Published private(set) var skippedUpdateVersion: String? {
        didSet {
            if let skippedUpdateVersion {
                defaults.set(skippedUpdateVersion, forKey: Self.skippedUpdateVersionKey)
            } else {
                defaults.removeObject(forKey: Self.skippedUpdateVersionKey)
            }
        }
    }

    @Published private(set) var selectedAgentRuntime: RuntimeScope {
        didSet {
            defaults.set(selectedAgentRuntime.runtimeId, forKey: Self.selectedAgentRuntimeKey)
            visibleRuntimeScopes = [.codex, selectedAgentRuntime]
            defaults.set(visibleRuntimeScopes.map(\.runtimeId), forKey: Self.visibleRuntimeScopesKey)
        }
    }

    @Published private(set) var visibleRuntimeScopes: [RuntimeScope] {
        didSet {
            defaults.set(visibleRuntimeScopes.map(\.runtimeId), forKey: Self.visibleRuntimeScopesKey)
        }
    }

    @Published private(set) var statusItemPreferences: StatusItemPreferences
    @Published private(set) var globalShortcut: GlobalShortcut?
    @Published private(set) var globalShortcutError: GlobalShortcutError?
    var globalShortcutRegistration: ((GlobalShortcut) -> Result<Void, GlobalShortcutRegistrationFailure>)?
    var globalShortcutUnregistration: (() -> Result<Void, GlobalShortcutRegistrationFailure>)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = WidgetLanguage.storedOrAutomatic(defaults: defaults)
        themeMode = WidgetThemeMode.storedOrAutomatic(defaults: defaults)
        particleAnimationMode = ParticleAnimationMode.storedOrDefault(defaults: defaults)
        keepMainWindowOnTop = defaults.bool(forKey: Self.keepMainWindowOnTopKey)
        if defaults.object(forKey: Self.keepRunningWhenMainWindowClosedKey) == nil {
            keepRunningWhenMainWindowClosed = true
        } else {
            keepRunningWhenMainWindowClosed = defaults.bool(forKey: Self.keepRunningWhenMainWindowClosedKey)
        }
        // Local multi-Agent customizations must not be overwritten by an upstream DMG.
        automaticUpdateChecksEnabled = false
        defaults.set(false, forKey: Self.automaticUpdateChecksEnabledKey)
        skippedUpdateVersion = defaults.string(forKey: Self.skippedUpdateVersionKey)
        let storedAgent = defaults.string(forKey: Self.selectedAgentRuntimeKey)
            .flatMap(RuntimeScope.storedIdentifier)
        let legacyAgent = (defaults.array(forKey: Self.visibleRuntimeScopesKey) as? [String])?
            .compactMap(RuntimeScope.storedIdentifier)
            .first(where: \.isCompanionAgent)
        let initialAgent = storedAgent?.isCompanionAgent == true
            ? storedAgent!
            : (legacyAgent ?? .openClaw)
        selectedAgentRuntime = initialAgent
        visibleRuntimeScopes = [.codex, initialAgent]
        defaults.set(initialAgent.runtimeId, forKey: Self.selectedAgentRuntimeKey)
        defaults.set([RuntimeScope.codex.runtimeId, initialAgent.runtimeId], forKey: Self.visibleRuntimeScopesKey)
        defaults.set(true, forKey: Self.multiAgentSelectionMigrationKey)
        statusItemPreferences = StatusItemPreferencesStore.load(defaults: defaults)
        let storedShortcut = GlobalShortcut.load(defaults: defaults)
        if let storedShortcut, storedShortcut.validationError != nil {
            globalShortcut = .default
            GlobalShortcut.default.save(defaults: defaults)
        } else {
            globalShortcut = storedShortcut
        }
        globalShortcutError = nil
    }

    @discardableResult
    func selectAgentRuntime(_ scope: RuntimeScope) -> Bool {
        guard scope.isCompanionAgent else { return false }
        selectedAgentRuntime = scope
        return true
    }

    @discardableResult
    func updateStatusItemPreferences(
        _ mutation: (inout StatusItemPreferences) -> Void
    ) -> Result<Void, StatusItemPreferenceError> {
        var candidate = statusItemPreferences
        mutation(&candidate)
        if let error = candidate.validationError() {
            return .failure(error)
        }
        candidate = candidate.normalized()
        guard candidate != statusItemPreferences else {
            return .success(())
        }
        statusItemPreferences = candidate
        StatusItemPreferencesStore.save(candidate, defaults: defaults)
        return .success(())
    }

    func resetStatusItemPreferences() {
        StatusItemPreferencesStore.reset(defaults: defaults)
        statusItemPreferences = .default
    }

    @discardableResult
    func requestGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        if let current = globalShortcut, shortcut.matchesRegistration(of: current) {
            globalShortcut = shortcut
            shortcut.save(defaults: defaults)
            globalShortcutError = nil
            return true
        }
        if let error = shortcut.validationError {
            globalShortcutError = .invalid(error)
            return false
        }
        guard let result = globalShortcutRegistration?(shortcut) else {
            globalShortcutError = .registrationFailed
            return false
        }
        switch result {
        case .success:
            break
        case .failure(.occupied):
            globalShortcutError = .occupied
            return false
        case .failure(.failed):
            globalShortcutError = .registrationFailed
            return false
        }
        globalShortcut = shortcut
        shortcut.save(defaults: defaults)
        globalShortcutError = nil
        return true
    }

    func resetGlobalShortcut() {
        requestGlobalShortcut(.default)
    }

    func clearGlobalShortcut() {
        guard let globalShortcutUnregistration else {
            globalShortcutError = .unregistrationFailed
            return
        }
        guard case .success = globalShortcutUnregistration() else {
            globalShortcutError = .unregistrationFailed
            return
        }
        globalShortcut = nil
        GlobalShortcut.clear(defaults: defaults)
        globalShortcutError = nil
    }

    func handleInitialGlobalShortcutFailure(defaultRegistered: Bool) {
        if defaultRegistered {
            globalShortcut = .default
            globalShortcutError = .savedShortcutUnavailableUsingDefault
        } else {
            globalShortcut = nil
            globalShortcutError = .noShortcutAvailable
        }
    }

    func skipUpdateVersion(_ version: String) {
        skippedUpdateVersion = version
    }

    func clearSkippedUpdateVersion() {
        skippedUpdateVersion = nil
    }
}

enum DashboardTab: String, CaseIterable, Equatable, Identifiable {
    case tasks
    case usage
    case projects
    case skills

    var id: String { rawValue }
}

final class WindowPresentationState: ObservableObject {
    @Published var isPinnedToFront = false
}

struct UsageWidgetView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateStore: AppUpdateStore
    @StateObject private var systemMonitor = LocalSystemMonitor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var selectedDashboardTab: DashboardTab = .tasks

    static let widgetWidth: CGFloat = 820
    static let widgetDefaultHeight: CGFloat = 720
    static let widgetMinHeight: CGFloat = 620
    static let widgetMaxHeight: CGFloat = 920
    static let windowCornerRadius: CGFloat = 18

    private var snapshot: UsageSnapshot { store.snapshot }
    private var combinedTaskBoard: TaskBoard? { store.multiRuntimeSnapshot.aggregate.taskBoard }
    private var language: WidgetLanguage { settings.language }
    private var themeMode: WidgetThemeMode { settings.themeMode }
    private var selectedQuotaIsStale: Bool {
        store.runtimeSnapshot(for: store.selectedRuntimeScope)?.status == .stale
    }
    private var effectiveColorScheme: ColorScheme {
        themeMode.preferredColorScheme ?? colorScheme
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            windowSurface
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .accessibilityHidden(true)
            widgetContent
        }
        .frame(width: Self.widgetWidth, alignment: .topLeading)
        .frame(minHeight: Self.widgetMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(themeMode.preferredColorScheme)
        .readableForegroundHierarchy(effectiveColorScheme)
        .onAppear {
            themeMode.applyAppearance()
            systemMonitor.start()
            store.setTaskBoardSelected(selectedDashboardTab == .tasks)
        }
        .onDisappear {
            systemMonitor.stop()
            store.setTaskBoardSelected(false)
        }
        .onChange(of: selectedDashboardTab) { _, tab in
            store.setTaskBoardSelected(tab == .tasks)
        }
    }

    @ViewBuilder
    private var windowSurface: some View {
        staticWindowSurface(
            fill: WidgetPalette.windowScrim(
                effectiveColorScheme,
                reduceTransparency: reduceTransparency
            )
        )
    }

    private func staticWindowSurface(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
                    .strokeBorder(
                        WidgetPalette.sectionStroke(
                            effectiveColorScheme,
                            increasedContrast: colorSchemeContrast == .increased
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.8
                    )
            )
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if shouldShowEnvironmentChecklist {
                        environmentChecklistSection
                    }
                    usageOverviewSection
                    LocalSystemStatusStrip(snapshot: systemMonitor.snapshot, language: language)
                    dashboardTabsSection
                }
                .padding(.bottom, 2)
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var environmentChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: language.text("环境检查", "Environment"),
                detail: language.text("首次使用", "First run")
            )
            ForEach(environmentDiagnostics) { item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: item.systemName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(item.tint)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
            }
        }
        .padding(12)
        .sectionBackground()
    }

    private func statusPill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(WidgetPalette.controlFill(effectiveColorScheme))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(WidgetPalette.controlStroke(effectiveColorScheme), lineWidth: 0.8)
                    )
            )
    }

    private var usageOverviewSection: some View {
        HStack(alignment: .center, spacing: 26) {
            if store.selectedRuntimeScope.isCompanionAgent {
                LocalAgentOverviewCard(scope: store.selectedRuntimeScope, language: language)
                    .frame(width: 154, height: 179)
            } else {
                VStack(spacing: 8) {
                    DualQuotaRing(
                        fiveHourQuota: snapshot.fiveHourQuota,
                        sevenDayQuota: snapshot.sevenDayQuota,
                        quotaReadSucceeded: snapshot.quotaReadSucceeded,
                        quotaIsStale: selectedQuotaIsStale,
                        language: language,
                        visualEnergyMode: store.visualEnergyMode,
                        animationMode: settings.particleAnimationMode
                    )
                    .frame(width: 145, height: 145)

                    QuotaResetSummary(
                        fiveHourQuota: snapshot.fiveHourQuota,
                        sevenDayQuota: snapshot.sevenDayQuota,
                        language: language
                    )
                    .frame(width: 154, height: 26)
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                if store.selectedRuntimeScope == .codex {
                    CodexOfficialUsageStrip(
                        lifetimeTokens: snapshot.cloudLifetimeTokens,
                        trend: snapshot.cloudUsageTrend,
                        language: language
                    )
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(language.text("本机原始上下文（非官方用量）", "Local raw context (not official usage)"))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(language.text(
                        "来自本机 token_count，包含大量缓存上下文，只用于输入/缓存/输出拆分和项目归因，不能与 Codex App 个人资料的官方 token 活动直接比较。",
                        "From local token_count events, including cached context. Used for input/cache/output breakdowns and project attribution, not for comparison with official Codex App token activity."
                    ))
                }

                HStack(spacing: 12) {
                    DetailedTokenMetricCard(
                        title: store.selectedRuntimeScope == .codex
                            ? language.text("上下文·今日", "Context today")
                            : language.text("今日", "Today"),
                        systemName: "sun.max.fill",
                        usage: snapshot.local?.detailedUsage?.today,
                        fallbackTokens: snapshot.local?.todayTokens,
                        showsEstimatedCost: store.selectedRuntimeScope == .codex,
                        language: language
                    )
                    DetailedTokenMetricCard(
                        title: store.selectedRuntimeScope == .codex
                            ? language.text("上下文·近 7 天", "Context 7 days")
                            : language.text("近 7 天", "Last 7 days"),
                        systemName: "calendar",
                        usage: snapshot.local?.detailedUsage?.sevenDay,
                        fallbackTokens: snapshot.local?.sevenDayTokens,
                        showsEstimatedCost: store.selectedRuntimeScope == .codex,
                        language: language
                    )
                    DetailedTokenMetricCard(
                        title: store.selectedRuntimeScope == .codex
                            ? language.text("上下文·累计", "Context lifetime")
                            : language.text("累计", "Lifetime"),
                        systemName: "sum",
                        usage: snapshot.local?.detailedUsage?.lifetime,
                        fallbackTokens: snapshot.local?.lifetimeTokens,
                        showsEstimatedCost: store.selectedRuntimeScope == .codex,
                        language: language
                    )
                }

                if store.selectedRuntimeScope.isCompanionAgent {
                    RuntimeAttributionCard(scope: store.selectedRuntimeScope, language: language)
                } else {
                    WoolProgressCard(usage: snapshot.local?.detailedUsage?.month, language: language)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .sectionBackground()
    }

    private var dashboardTabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                DashboardTabSwitch(selectedTab: selectedDashboardTab, language: language) { tab in
                    selectedDashboardTab = tab
                }
                Spacer(minLength: 10)
                Text(dashboardSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            dashboardTabContent
        }
        .padding(12)
        .sectionBackground()
    }

    @ViewBuilder
    private var dashboardTabContent: some View {
        switch selectedDashboardTab {
        case .tasks:
            taskBoardContent
        case .usage:
            UsageTrendPanel(
                trend: displayedUsageTrend,
                runtimeScope: store.selectedRuntimeScope,
                language: language
            )
        case .projects:
            ProjectBoardPanel(
                projectBoard: snapshot.local?.projectBoard,
                language: language
            )
        case .skills:
            SkillUsagePanel(
                skillUsages: snapshot.local?.skillUsages ?? [],
                toolUsages: snapshot.local?.toolUsages ?? [],
                language: language
            )
        }
    }

    private var taskBoardContent: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(taskBoardColumns) { column in
                TaskBoardColumnView(column: column, language: language)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            AppUpdateFooterButton(updateStore: updateStore, language: language)
            Spacer()
            Text("\(language.text("刷新", "Refreshed")) \(timeOnly(snapshot.refreshedAt, language: language))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            if let shortcut = settings.globalShortcut {
                Text(shortcut.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var taskBoardSummary: String {
        guard let board = combinedTaskBoard else { return language.text("读取中", "Loading") }
        return language.text(
            "\(board.totalCount) 事项 · \(timeOnly(board.refreshedAt, language: language))",
            "\(board.totalCount) items · \(timeOnly(board.refreshedAt, language: language))"
        )
    }

    private var dashboardSummary: String {
        switch selectedDashboardTab {
        case .tasks:
            return taskBoardSummary
        case .usage:
            guard let trend = displayedUsageTrend else { return language.text("读取中", "Loading") }
            let quality = sourceQualityText(trend.sourceQuality, language: language)
            return language.text("\(trend.activeDayCount) 活跃日 · \(quality)", "\(trend.activeDayCount) active days · \(quality)")
        case .projects:
            let activeCount = snapshot.local?.projectBoard?.recentProjects.count ?? 0
            let totalCount = snapshot.local?.projectBoard?.allProjects.count ?? 0
            return language.text("\(activeCount) 活跃项目 · \(totalCount) 全部", "\(activeCount) active projects · \(totalCount) total")
        case .skills:
            let skillCount = snapshot.local?.skillUsages.count ?? 0
            let toolCount = snapshot.local?.toolUsages.count ?? 0
            return language.text("\(skillCount) Skill · \(toolCount) 工具", "\(skillCount) skills · \(toolCount) tools")
        }
    }

    private var displayedUsageTrend: UsageTrend? {
        if store.selectedRuntimeScope == .codex {
            return snapshot.cloudUsageTrend ?? snapshot.local?.usageTrend
        }
        return snapshot.local?.usageTrend
    }

    private var taskBoardColumns: [TaskColumn] {
        combinedTaskBoard?.columns ?? [
            TaskColumn(id: .active, title: localizedTaskColumnTitle(.active, language: language), count: 0, items: []),
            TaskColumn(id: .pending, title: localizedTaskColumnTitle(.pending, language: language), count: 0, items: []),
            TaskColumn(id: .scheduled, title: localizedTaskColumnTitle(.scheduled, language: language), count: 0, items: []),
            TaskColumn(id: .done, title: localizedTaskColumnTitle(.done, language: language), count: 0, items: [])
        ]
    }

    private var shouldShowEnvironmentChecklist: Bool {
        if snapshot.messages.contains("正在读取 codexU 数据") { return false }
        if store.selectedRuntimeScope.isCompanionAgent {
            return snapshot.local == nil || snapshot.local?.detailedUsage == nil
        }
        let quotaUnavailable = snapshot.fiveHourQuota == nil && snapshot.sevenDayQuota == nil
        let hasQuotaProtocolWarning = snapshot.messages.contains { $0.contains("额度窗口") }
        return (!snapshot.messages.isEmpty && (quotaUnavailable || hasQuotaProtocolWarning || snapshot.local == nil))
            || snapshot.account == nil
            || snapshot.local == nil
    }

    private var environmentDiagnostics: [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        let messages = snapshot.messages.joined(separator: "\n")

        if store.selectedRuntimeScope.isCompanionAgent {
            let runtime = store.selectedRuntimeScope
            if snapshot.local == nil || snapshot.local?.detailedUsage == nil {
                items.append(DiagnosticItem(
                    id: "\(runtime.runtimeId)-local-usage",
                    title: language.text("暂无 \(runtime.displayName) 本机用量记录", "No local \(runtime.displayName) usage records yet"),
                    detail: companionRuntimeDiagnosticDetail(runtime),
                    systemName: "doc.text.magnifyingglass",
                    tint: WidgetPalette.statusInfo
                ))
            }

            if items.isEmpty {
                items = snapshot.messages.prefix(3).enumerated().map { index, message in
                    DiagnosticItem(
                        id: "\(runtime.runtimeId)-message-\(index)",
                        title: language.text("运行提示", "Runtime note"),
                        detail: localizedReaderMessage(message, language: language),
                        systemName: "info.circle.fill",
                        tint: WidgetPalette.statusInfo
                    )
                }
            }

            return items
        }

        if (snapshot.fiveHourQuota == nil && snapshot.sevenDayQuota == nil) || snapshot.account == nil {
            if messages.contains("未找到 codex") {
                items.append(DiagnosticItem(
                    id: "codex-missing",
                    title: language.text("未找到 Codex", "Codex not found"),
                    detail: language.text("请先安装 ChatGPT/Codex App，或确认 codex CLI 位于标准安装目录。", "Install the ChatGPT/Codex app first, or make sure the codex CLI is in a standard installation directory."),
                    systemName: "magnifyingglass",
                    tint: WidgetPalette.statusWarning
                ))
            } else if messages.contains("app-server") {
                items.append(DiagnosticItem(
                    id: "app-server",
                    title: language.text("Codex 账户接口暂不可用", "Codex account API unavailable"),
                    detail: language.text("确认 Codex 已登录后点击刷新；本机 token 统计仍可继续显示。", "Make sure Codex is signed in, then refresh. Local token stats can still be shown."),
                    systemName: "exclamationmark.triangle.fill",
                    tint: WidgetPalette.statusWarning
                ))
            } else {
                items.append(DiagnosticItem(
                    id: "quota-unavailable",
                    title: language.text("账户额度读取中", "Reading account quota"),
                    detail: language.text("如果长时间无数据，请确认 Codex 已安装并完成登录。", "If data does not appear, make sure Codex is installed and signed in."),
                    systemName: "person.crop.circle.badge.questionmark",
                    tint: WidgetPalette.statusInfo
                ))
            }
        }

        if snapshot.local == nil {
            if messages.contains("state_5.sqlite") {
                items.append(DiagnosticItem(
                    id: "sqlite-db",
                    title: language.text("未找到本机 Codex 统计库", "Local Codex database not found"),
                    detail: language.text("打开 Codex 并至少完成一次会话后，再回到小组件点击刷新。", "Open Codex and complete at least one session, then refresh this widget."),
                    systemName: "externaldrive.badge.questionmark",
                    tint: WidgetPalette.statusWarning
                ))
            } else if messages.contains("sqlite3") {
                items.append(DiagnosticItem(
                    id: "sqlite-cli",
                    title: language.text("未找到 sqlite3", "sqlite3 not found"),
                    detail: language.text("请安装 macOS Command Line Tools，或通过 Homebrew 安装 sqlite。", "Install macOS Command Line Tools, or install sqlite with Homebrew."),
                    systemName: "terminal",
                    tint: WidgetPalette.statusWarning
                ))
            } else {
                items.append(DiagnosticItem(
                    id: "local-usage",
                    title: language.text("本机统计暂不可用", "Local stats unavailable"),
                    detail: language.text("本机 token 和任务看板依赖 ~/.codex 的本地状态文件。", "Local tokens and the task board depend on Codex state files under ~/.codex."),
                    systemName: "chart.bar.doc.horizontal",
                    tint: WidgetPalette.statusInfo
                ))
            }
        }

        if items.isEmpty {
            items = snapshot.messages.prefix(3).enumerated().map { index, message in
                DiagnosticItem(
                    id: "message-\(index)",
                    title: language.text("运行提示", "Runtime note"),
                    detail: localizedReaderMessage(message, language: language),
                    systemName: "info.circle.fill",
                    tint: WidgetPalette.statusInfo
                )
            }
        }

        return items
    }

    private func companionRuntimeDiagnosticDetail(_ scope: RuntimeScope) -> String {
        switch scope {
        case .codex:
            return language.text("本机统计来自 ~/.codex。", "Local stats come from ~/.codex.")
        case .openClaw:
            return language.text(
                "来自 ~/.openclaw/agents/main/sessions，只读取 usage、模型和工具名称等结构化字段，不读取 NAS。",
                "Reads structured usage, model, and tool-name fields from ~/.openclaw/agents/main/sessions; NAS is excluded."
            )
        case .claudeCode:
            return language.text(
                "来自 ~/.claude/projects 的本机会话记录；未选中 Claude Code 时不会扫描该目录。",
                "Reads local sessions under ~/.claude/projects; the directory is not scanned when Claude Code is not selected."
            )
        case .hermes:
            return language.text(
                "来自 ~/.hermes/state.db 的默认 profile，只读取 token、会话、模型和工具等结构化字段。",
                "Reads structured token, session, model, and tool fields from the default profile at ~/.hermes/state.db."
            )
        }
    }
}

struct SectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct LanguageSwitch: View {
    let language: WidgetLanguage
    let onSelect: (WidgetLanguage) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { language },
            set: { onSelect($0) }
        )) {
            Text("中").tag(WidgetLanguage.zh)
            Text("EN").tag(WidgetLanguage.en)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.mini)
        .frame(width: 70)
    }
}

struct ThemeSwitch: View {
    let themeMode: WidgetThemeMode
    let language: WidgetLanguage
    let onSelect: (WidgetThemeMode) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { themeMode },
            set: { onSelect($0) }
        )) {
            Image(systemName: "circle.lefthalf.filled")
                .tag(WidgetThemeMode.system)
            Image(systemName: "sun.max.fill")
                .tag(WidgetThemeMode.light)
            Image(systemName: "moon.fill")
                .tag(WidgetThemeMode.dark)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.mini)
        .frame(width: 86)
        .help(language.text("外观：自动、浅色、深色", "Appearance: system, light, dark"))
        .accessibilityLabel(language.text("外观模式", "Appearance mode"))
    }
}

struct HeaderActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let systemName: String
    var isActive = false
    var hoverTint: Color?
    let help: String
    let accessibilityLabel: String
    var accessibilityValue: String?
    let action: () -> Void

    private var foregroundColor: Color {
        if isActive {
            return WidgetPalette.brandPrimary
        }
        if isHovering, let hoverTint {
            return hoverTint
        }
        return Color.secondary
    }

    private var fillColor: Color {
        if isActive {
            return WidgetPalette.brandPrimary.opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
        if isHovering {
            return WidgetPalette.controlSelectedFill(colorScheme)
        }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: titlebarControlHeight, height: titlebarControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isActive ? WidgetPalette.brandPrimary.opacity(0.42) : Color.clear,
                            lineWidth: 0.8
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct TitlebarToolbarView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    let onOpenSettings: () -> Void

    private var language: WidgetLanguage { settings.language }
    private var themeMode: WidgetThemeMode { settings.themeMode }
    private var effectiveColorScheme: ColorScheme {
        themeMode.preferredColorScheme ?? colorScheme
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            RuntimeSelector(
                selected: store.selectedRuntimeScope,
                scopes: settings.visibleRuntimeScopes,
                language: language
            ) { scope in
                store.selectRuntime(scope)
            }

            HStack(spacing: 2) {
                HeaderActionButton(
                    systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise",
                    help: language.text("刷新", "Refresh"),
                    accessibilityLabel: language.text("刷新", "Refresh")
                ) {
                    store.refresh()
                }
                .disabled(store.isRefreshing)

                HeaderActionButton(
                    systemName: "gearshape",
                    help: language.text("设置", "Settings"),
                    accessibilityLabel: language.text("设置", "Settings")
                ) {
                    onOpenSettings()
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WidgetPalette.controlFill(effectiveColorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(WidgetPalette.controlStroke(effectiveColorScheme), lineWidth: 0.8)
                    )
            )
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topTrailing)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(themeMode.preferredColorScheme)
        .readableForegroundHierarchy(effectiveColorScheme)
    }
}

struct SettingsPanelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: AppUpdateStore
    @Environment(\.colorScheme) private var colorScheme

    private var language: WidgetLanguage { settings.language }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader
                settingsSection(
                    title: language.text("通用", "General"),
                    detail: language.text("界面偏好", "Interface")
                ) {
                    SettingsPickerRow(
                        title: language.text("语言", "Language"),
                        detail: language.text("影响主窗口、浮窗和设置窗口", "Applies to the main window, menu popover, and settings")
                    ) {
                        SettingsSegmentedControl(
                            selection: $settings.language,
                            options: [
                                SettingsSegmentOption(value: .zh, title: "中文"),
                                SettingsSegmentOption(value: .en, title: "English")
                            ],
                            width: 156
                        )
                    }

                    SettingsPickerRow(
                        title: language.text("外观", "Appearance"),
                        detail: language.text("默认跟随系统", "System is the default")
                    ) {
                        SettingsSegmentedControl(
                            selection: $settings.themeMode,
                            options: [
                                SettingsSegmentOption(value: .system, title: language.text("自动", "System")),
                                SettingsSegmentOption(value: .light, title: language.text("浅色", "Light")),
                                SettingsSegmentOption(value: .dark, title: language.text("深色", "Dark"))
                            ],
                            width: 190
                        )
                    }

                    SettingsPickerRow(
                        title: language.text("额度环动效", "Quota ring motion"),
                        detail: language.text(
                            "默认仅窗口置前且聚焦；省电仅悬停环带",
                            "Default: frontmost and focused; Power Saving: ring hover only"
                        )
                    ) {
                        SettingsSegmentedControl(
                            selection: $settings.particleAnimationMode,
                            options: [
                                SettingsSegmentOption(value: .standard, title: language.text("默认", "Default")),
                                SettingsSegmentOption(value: .powerSaving, title: language.text("省电", "Power Saving"))
                            ],
                            width: 190
                        )
                    }
                }

                settingsSection(
                    title: "Runtime",
                    detail: language.text("Agent 接入", "Agent integration")
                ) {
                    SettingsPickerRow(
                        title: language.text("第二 Agent", "Companion agent"),
                        detail: language.text("Codex 始终保留；选择一个本机 Agent", "Codex stays enabled; choose one local agent")
                    ) {
                        SettingsAgentPickerControl(
                            selectedScope: settings.selectedAgentRuntime,
                            language: language
                        ) { scope in
                            settings.selectAgentRuntime(scope)
                        }
                        .help(runtimeSelectionHelp)
                    }
                }

                settingsSection(
                    title: language.text("数据与统计", "Data & Statistics"),
                    detail: language.text("自然日口径", "Calendar-day basis")
                ) {
                    SettingsPickerRow(
                        title: language.text("统计时区", "Statistics time zone"),
                        detail: statisticsTimeZoneDetail
                    ) {
                        SettingsSegmentedControl(
                            selection: statisticsTimeZoneSelectionBinding,
                            options: [
                                SettingsSegmentOption(value: .system, title: language.text("跟随系统", "System")),
                                SettingsSegmentOption(value: .utc, title: "UTC"),
                                SettingsSegmentOption(value: .fixed, title: language.text("固定", "Fixed"))
                            ],
                            width: 250
                        )
                    }

                    if store.statisticsPreference.selection == .fixed {
                        SettingsPickerRow(
                            title: language.text("固定时区", "Fixed time zone"),
                            detail: language.text("使用 IANA 时区，自动处理夏令时", "Uses an IANA zone and observes daylight saving time")
                        ) {
                            Picker("", selection: statisticsFixedIdentifierBinding) {
                                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                                    Text(identifier).tag(identifier)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 250)
                        }
                    }
                }

                settingsSection(
                    title: language.text("状态栏", "Menu Bar"),
                    detail: language.text("内容与显示密度", "Content and density")
                ) {
                    StatusItemSettingsView(settings: settings, store: store)
                }

                settingsSection(
                    title: language.text("窗口", "Window"),
                    detail: language.text("主窗口行为", "Main window")
                ) {
                    SettingsToggleRow(
                        title: language.text("保持主窗口置顶", "Keep main window on top"),
                        detail: language.text("适合需要持续观察用量时开启", "Use this when you need the usage view visible")
                    ) {
                        SettingsSwitchToggle(isOn: $settings.keepMainWindowOnTop)
                    }

                    SettingsToggleRow(
                        title: language.text("关闭后继续后台运行", "Keep running after closing the window"),
                        detail: language.text("关闭主窗口会隐藏 Dock 图标，可从菜单栏或快捷键再次打开", "Closing the main window hides the Dock icon; reopen from the menu bar or shortcut")
                    ) {
                        SettingsSwitchToggle(isOn: $settings.keepRunningWhenMainWindowClosed)
                    }

                    SettingsPickerRow(
                        title: language.text("快捷键", "Shortcut"),
                        detail: language.text(
                            "默认 ⌘U；自定义需两个修饰键（含 ⌘ 或 ⌃）；仅能检测独占冲突",
                            "Default: ⌘U. Custom: two modifiers including ⌘ or ⌃; only exclusive conflicts are detected"
                        )
                    ) {
                        HStack(spacing: settingsShortcutControlSpacing) {
                            ShortcutRecorderView(
                                shortcut: settings.globalShortcut,
                                language: language,
                                onRecord: settings.requestGlobalShortcut,
                                onClear: settings.clearGlobalShortcut
                            )
                            .frame(
                                width: settingsShortcutRecorderWidth,
                                height: settingsSegmentHeight
                            )

                            Button(language.text("恢复默认", "Restore Default")) {
                                settings.resetGlobalShortcut()
                            }
                            .buttonStyle(.borderless)
                            .disabled(
                                settings.globalShortcut == .default
                                    && settings.globalShortcutError == nil
                            )
                        }
                    }

                    if let error = settings.globalShortcutError {
                        SettingsErrorRow(
                            title: language.text("快捷键不可用", "Shortcut unavailable"),
                            message: error.message(language: language),
                            currentValue: settings.globalShortcut.map {
                                language.text("当前仍使用 \($0.displayName)", "Still using \($0.displayName)")
                            } ?? language.text("当前未设置全局快捷键", "No global shortcut is currently set")
                        )
                    }
                }

                settingsSection(
                    title: language.text("系统", "System"),
                    detail: language.text("状态与更新", "Status")
                ) {
                    SettingsValueRow(
                        title: language.text("当前 Runtime", "Current runtime"),
                        detail: language.text("主窗口数据范围", "Main window data scope"),
                        value: store.selectedRuntimeScope.displayName
                    )
                    SettingsValueRow(
                        title: language.text("计划状态", "Plan"),
                        detail: language.text("来自本机账户读取结果", "Read from the local account result"),
                        value: planLabel
                    )
                    AppUpdateSettingsRows(
                        settings: settings,
                        updateStore: updateStore,
                        language: language
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 480, alignment: .topLeading)
        .background(WidgetPalette.sectionFill(colorScheme).opacity(0.35))
        .readableForegroundHierarchy(colorScheme)
    }

    private var statisticsTimeZoneSelectionBinding: Binding<StatisticsTimeZoneSelection> {
        Binding(
            get: { store.statisticsPreference.selection },
            set: { selection in
                var preference = store.statisticsPreference
                preference.selection = selection
                store.updateStatisticsTimeZone(preference)
            }
        )
    }

    private var statisticsFixedIdentifierBinding: Binding<String> {
        Binding(
            get: { store.statisticsPreference.fixedIdentifier },
            set: { identifier in
                store.updateStatisticsTimeZone(
                    StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: identifier)
                )
            }
        )
    }

    private var statisticsTimeZoneDetail: String {
        if let message = store.statisticsTransitionMessage {
            return message
        }
        let identity = store.multiRuntimeSnapshot.statisticsIdentity
        switch identity.preference.selection {
        case .system:
            return language.text(
                "默认按系统自然日统计 · \(identity.resolvedIdentifier)",
                "Uses the system calendar day · \(identity.resolvedIdentifier)"
            )
        case .utc:
            return language.text("UTC 日界线，便于对照官方", "UTC day boundary for easier official comparison")
        case .fixed:
            return identity.resolvedIdentifier
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(language.text("设置", "Settings"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("codexU")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, detail: detail)
            VStack(spacing: 0) {
                content()
            }
            .cardBackground(cornerRadius: 10, elevated: true)
        }
    }

    private var planLabel: String {
        store.snapshot.account?.planType?.uppercased() ?? "LOCAL"
    }

    private var runtimeSelectionHelp: String {
        language.text(
            "Codex 固定显示；未选中的 Agent 不会读取本机数据",
            "Codex stays visible; unselected agents are not read"
        )
    }
}

struct SettingsPickerRow<Control: View>: View {
    let title: String
    let detail: String
    let control: Control

    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            control
        }
    }
}

struct SettingsSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

struct SettingsSegmentedControl<Value: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: Value
    let options: [SettingsSegmentOption<Value>]
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: selection == option.value ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selection == option.value ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: settingsSegmentHeight)
                        .background(
                            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                                .fill(selection == option.value ? WidgetPalette.brandPrimary : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])

                if index < options.count - 1 {
                    Rectangle()
                        .fill(WidgetPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: width, height: settingsSegmentHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous))
    }
}

struct SettingsAgentPickerControl: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedScope: RuntimeScope
    let language: WidgetLanguage
    let onSelect: (RuntimeScope) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(RuntimeScope.companionCases.enumerated()), id: \.element.id) { index, scope in
                Button {
                    onSelect(scope)
                } label: {
                    HStack(spacing: 4) {
                        RuntimeLogoView(scope: scope, size: 14)
                        Text(label(for: scope))
                            .font(.system(size: 11, weight: isSelected(scope) ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .foregroundStyle(isSelected(scope) ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: settingsSegmentHeight)
                    .background(
                        RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                            .fill(isSelected(scope) ? WidgetPalette.brandPrimary : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scope.displayName)
                .accessibilityValue(isSelected(scope) ? language.text("已选择", "Selected") : language.text("未选择", "Not selected"))

                if index < RuntimeScope.companionCases.count - 1 {
                    Rectangle()
                        .fill(WidgetPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: settingsAccessoryColumnWidth, height: settingsSegmentHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous))
    }

    private func isSelected(_ scope: RuntimeScope) -> Bool {
        selectedScope == scope
    }

    private func label(for scope: RuntimeScope) -> String {
        scope == .claudeCode ? "Claude" : scope.displayName
    }
}

struct SettingsSwitchToggle: View {
    let isOn: Binding<Bool>
    var isDisabled = false
    var help: String?

    var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.regular)
            .tint(WidgetPalette.brandPrimary)
            .frame(width: settingsSwitchWidth, alignment: .trailing)
            .disabled(isDisabled)
            .help(help ?? "")
    }
}

struct SettingsToggleRow<Control: View>: View {
    let title: String
    let detail: String
    let control: Control

    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            control
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let detail: String
    let value: String

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

struct SettingsErrorRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let message: String
    let currentValue: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WidgetPalette.statusDanger)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.statusDanger)
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentValue)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(WidgetPalette.statusDangerFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.statusDangerStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsBaseRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .frame(width: settingsAccessoryColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardTabSwitch: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedTab: DashboardTab
    let language: WidgetLanguage
    let onSelect: (DashboardTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(DashboardTab.allCases.enumerated()), id: \.element.id) { index, tab in
                Button {
                    onSelect(tab)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: dashboardTabIcon(tab))
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: dashboardTabIconWidth, alignment: .center)
                        Text(localizedDashboardTabLabel(tab, language: language))
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, dashboardTabHorizontalPadding)
                    .padding(.vertical, 6)
                    .frame(width: dashboardTabSegmentWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selectedTab == tab ? WidgetPalette.controlSelectedFill(colorScheme) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedDashboardTabLabel(tab, language: language))

                if index < DashboardTab.allCases.count - 1 {
                    Rectangle()
                        .fill(WidgetPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(language.text("切换今日任务、用量趋势和项目排行", "Switch between tasks, usage, and project rankings"))
        .accessibilityLabel(language.text("看板标签页", "Dashboard tabs"))
    }
}

struct SectionBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        WidgetPalette.sectionFill(
                            colorScheme,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                WidgetPalette.sectionStroke(
                                    colorScheme,
                                    increasedContrast: colorSchemeContrast == .increased
                                ),
                                lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.8
                            )
                    )
            )
    }
}

struct CardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        WidgetPalette.cardFill(
                            colorScheme,
                            elevated: elevated,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                WidgetPalette.cardStroke(
                                    colorScheme,
                                    elevated: elevated,
                                    increasedContrast: colorSchemeContrast == .increased
                                ),
                                lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.8
                            )
                    )
            )
    }
}

extension View {
    func readableForegroundHierarchy(_ colorScheme: ColorScheme) -> some View {
        foregroundStyle(
            Color.primary,
            WidgetPalette.secondaryText(colorScheme),
            WidgetPalette.tertiaryText(colorScheme)
        )
    }

    func sectionBackground() -> some View {
        modifier(SectionBackgroundModifier())
    }

    func cardBackground(cornerRadius: CGFloat = 10, elevated: Bool = false) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius, elevated: elevated))
    }
}

struct GaugeRing: View {
    let percent: Double
    let available: Bool
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.surfaceTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: available ? CGFloat(max(0, min(1, percent / 100))) : 0.0)
                .stroke(
                    AngularGradient(
                        colors: [
                            WidgetPalette.brandPrimary,
                            WidgetPalette.brandPrimaryLight,
                            WidgetPalette.brandHighlight,
                            WidgetPalette.brandPrimary
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

private enum QuotaRingGeometry {
    static let outerDiameter: CGFloat = 145
    static let innerDiameter: CGFloat = 107
    static let lineWidth: CGFloat = 16
    static let dualCenterDiameter: CGFloat = 72
    static let singleCenterDiameter: CGFloat = 110
    static let outerRadius = (outerDiameter - lineWidth) / 2
    static let innerRadius = (innerDiameter - lineWidth) / 2
    static let center = CGPoint(x: outerDiameter / 2, y: outerDiameter / 2)
}

private enum QuotaWindowKind: String, Hashable {
    case fiveHour
    case sevenDay

    var compactTitle: String {
        switch self {
        case .fiveHour: "5h"
        case .sevenDay: "7d"
        }
    }

    var startColor: RingRGBColor {
        switch self {
        case .fiveHour: quotaPrimaryStartColor
        case .sevenDay: quotaSecondaryStartColor
        }
    }

    var endColor: RingRGBColor {
        switch self {
        case .fiveHour: quotaPrimaryEndColor
        case .sevenDay: quotaSecondaryEndColor
        }
    }

    var color: Color {
        switch self {
        case .fiveHour: quotaPrimaryColor
        case .sevenDay: quotaSecondaryColor
        }
    }
}

private struct QuotaRingItem: Identifiable, Equatable {
    let kind: QuotaWindowKind
    let window: RateWindow

    var id: QuotaWindowKind { kind }

    var remainingText: String {
        "\(Int(window.remainingPercent.rounded()))%"
    }

    var particleProgress: CGFloat? {
        let progress = CGFloat(max(0, min(1, window.remainingPercent / 100)))
        return progress > 0.02 ? progress : nil
    }
}

private struct QuotaParticleLane: Equatable {
    let radius: CGFloat
    let progress: CGFloat?
    let maximumCount: Int
    let phaseOffset: Double
}

private struct QuotaRingPresentation: Equatable {
    enum Topology: Equatable {
        case none
        case single
        case dual
    }

    let items: [QuotaRingItem]

    init(fiveHourQuota: RateWindow?, sevenDayQuota: RateWindow?) {
        var items: [QuotaRingItem] = []
        if let fiveHourQuota {
            items.append(QuotaRingItem(kind: .fiveHour, window: fiveHourQuota))
        }
        if let sevenDayQuota {
            items.append(QuotaRingItem(kind: .sevenDay, window: sevenDayQuota))
        }
        self.items = items
    }

    var topology: Topology {
        switch items.count {
        case 0: .none
        case 1: .single
        default: .dual
        }
    }

    var particleLanes: [QuotaParticleLane] {
        switch topology {
        case .none:
            []
        case .single:
            items.prefix(1).map {
                QuotaParticleLane(
                    radius: QuotaRingGeometry.outerRadius,
                    progress: $0.particleProgress,
                    maximumCount: 17,
                    phaseOffset: 0
                )
            }
        case .dual:
            [
                QuotaParticleLane(
                    radius: QuotaRingGeometry.outerRadius,
                    progress: items[0].particleProgress,
                    maximumCount: 17,
                    phaseOffset: 0
                ),
                QuotaParticleLane(
                    radius: QuotaRingGeometry.innerRadius,
                    progress: items[1].particleProgress,
                    maximumCount: 12,
                    phaseOffset: 0.31
                )
            ]
        }
    }

    var activeRadii: [CGFloat] {
        particleLanes.map(\.radius)
    }

    func diameter(for item: QuotaRingItem) -> CGFloat {
        guard topology == .dual, item.kind == .sevenDay else {
            return QuotaRingGeometry.outerDiameter
        }
        return QuotaRingGeometry.innerDiameter
    }
}

private enum QuotaRingHoverTarget {
    private static let bounds = CGRect(
        x: 0,
        y: 0,
        width: QuotaRingGeometry.outerDiameter,
        height: QuotaRingGeometry.outerDiameter
    )
    private static let hitSlop: CGFloat = 10

    static func contains(_ location: CGPoint, activeRadii: [CGFloat]) -> Bool {
        guard bounds.contains(location), !activeRadii.isEmpty else { return false }
        let distance = hypot(
            location.x - QuotaRingGeometry.center.x,
            location.y - QuotaRingGeometry.center.y
        )
        return activeRadii.contains { abs(distance - $0) <= hitSlop }
    }
}

struct DualQuotaRing: View {
    let fiveHourQuota: RateWindow?
    let sevenDayQuota: RateWindow?
    let quotaReadSucceeded: Bool
    let quotaIsStale: Bool
    let language: WidgetLanguage
    let visualEnergyMode: VisualEnergyMode
    let animationMode: ParticleAnimationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPointerOverRing = false

    private var presentation: QuotaRingPresentation {
        QuotaRingPresentation(
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota
        )
    }

    var body: some View {
        ZStack {
            ForEach(presentation.items) { item in
                QuotaRingSegment(
                    percent: item.window.remainingPercent,
                    startColor: item.kind.startColor,
                    endColor: item.kind.endColor,
                    trackColor: WidgetPalette.surfaceTrack,
                    lineWidth: QuotaRingGeometry.lineWidth
                )
                .frame(
                    width: presentation.diameter(for: item),
                    height: presentation.diameter(for: item)
                )
            }

            if presentation.topology != .none {
                DualQuotaRingParticles(
                    lanes: presentation.particleLanes,
                    energyMode: visualEnergyMode,
                    animationMode: animationMode,
                    reduceMotion: reduceMotion,
                    isPointerOverRing: isPointerOverRing
                )
                .frame(
                    width: QuotaRingGeometry.outerDiameter,
                    height: QuotaRingGeometry.outerDiameter
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            switch presentation.topology {
            case .none:
                QuotaUnavailablePlaceholder(
                    isAuthoritative: quotaReadSucceeded,
                    language: language
                )
            case .single:
                Circle()
                    .fill(WidgetPalette.surfaceTrack)
                    .frame(
                        width: QuotaRingGeometry.singleCenterDiameter,
                        height: QuotaRingGeometry.singleCenterDiameter
                    )
                if let item = presentation.items.first {
                    SingleQuotaRingLabel(
                        item: item,
                        language: language,
                        isStale: quotaIsStale
                    )
                }
            case .dual:
                Circle()
                    .fill(WidgetPalette.surfaceTrack)
                    .frame(
                        width: QuotaRingGeometry.dualCenterDiameter,
                        height: QuotaRingGeometry.dualCenterDiameter
                    )
                VStack(spacing: 4) {
                    ForEach(presentation.items) { item in
                        QuotaRingLabel(
                            title: item.kind.compactTitle,
                            value: item.remainingText,
                            color: item.kind.color
                        )
                    }
                    Text(
                        quotaIsStale
                            ? language.text("旧快照", "stale")
                            : language.text("剩余", "left")
                    )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onContinuousHover { phase in
            let isOverRing: Bool
            switch phase {
            case let .active(location):
                isOverRing = QuotaRingHoverTarget.contains(
                    location,
                    activeRadii: presentation.activeRadii
                )
            case .ended:
                isOverRing = false
            }
            if isPointerOverRing != isOverRing {
                isPointerOverRing = isOverRing
            }
        }
    }

    private var accessibilityLabel: String {
        guard !presentation.items.isEmpty else {
            return quotaReadSucceeded
                ? language.text("当前无额度限制", "No active quota limits")
                : language.text("暂无额度数据", "No quota data")
        }
        let values = presentation.items.map { item in
            "\(item.kind.compactTitle) \(item.remainingText)"
        }.joined(separator: language.text("，", ", "))
        let base = language.text("额度剩余 \(values)", "Quota remaining \(values)")
        return quotaIsStale
            ? "\(base) · \(language.text("旧快照", "stale snapshot"))"
            : base
    }
}

struct QuotaRingSegment: View {
    let percent: Double
    let startColor: RingRGBColor
    let endColor: RingRGBColor
    let trackColor: Color
    let lineWidth: CGFloat

    var body: some View {
        let progress = CGFloat(max(0, min(1, percent / 100)))
        ZStack {
            Circle()
                .strokeBorder(trackColor, lineWidth: lineWidth)

            if progress > 0.001 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [startColor.color, endColor.color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(max(1, Double(progress) * 360))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private enum QuotaParticleRenderPolicy {
    static func shouldRender(
        hasProgress: Bool,
        energyMode: VisualEnergyMode,
        animationMode: ParticleAnimationMode,
        reduceMotion: Bool,
        isPointerOverRing: Bool,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState,
        appIsActive: Bool,
        appIsHidden: Bool,
        appIsFrontmost: Bool,
        windowIsVisible: Bool,
        windowIsMiniaturized: Bool,
        windowIsKey: Bool,
        windowIsOnActiveSpace: Bool,
        windowIsOccluded: Bool
    ) -> Bool {
        hasProgress
            && energyMode == .normal
            && !reduceMotion
            && !isLowPowerModeEnabled
            && thermalState == .nominal
            && appIsActive
            && !appIsHidden
            && appIsFrontmost
            && windowIsVisible
            && !windowIsMiniaturized
            && windowIsKey
            && windowIsOnActiveSpace
            && !windowIsOccluded
            && (animationMode == .standard || isPointerOverRing)
    }
}

private struct DualQuotaRingParticles: NSViewRepresentable {
    private struct ParticleStyle {
        let phase: Double
        let speed: Double
        let radialOffset: CGFloat
        let diameter: CGFloat
        let opacity: Double
    }

    private static let styles = [
        ParticleStyle(phase: 0.04, speed: 0.095, radialOffset: -2.8, diameter: 1.3, opacity: 0.52),
        ParticleStyle(phase: 0.24, speed: 0.122, radialOffset: 2.5, diameter: 2.2, opacity: 0.78),
        ParticleStyle(phase: 0.45, speed: 0.076, radialOffset: -0.4, diameter: 2.9, opacity: 0.90),
        ParticleStyle(phase: 0.66, speed: 0.274, radialOffset: 3.0, diameter: 1.2, opacity: 0.46),
        ParticleStyle(phase: 0.86, speed: 0.104, radialOffset: -2.0, diameter: 1.8, opacity: 0.66),
        ParticleStyle(phase: 0.14, speed: 0.083, radialOffset: 0.9, diameter: 2.5, opacity: 0.82),
        ParticleStyle(phase: 0.56, speed: 0.116, radialOffset: -3.1, diameter: 1.4, opacity: 0.50),
        ParticleStyle(phase: 0.34, speed: 0.068, radialOffset: 1.7, diameter: 0.9, opacity: 0.38),
        ParticleStyle(phase: 0.74, speed: 0.154, radialOffset: -1.2, diameter: 2.0, opacity: 0.72),
        ParticleStyle(phase: 0.94, speed: 0.111, radialOffset: 2.1, diameter: 1.1, opacity: 0.58),
        ParticleStyle(phase: 0.51, speed: 0.126, radialOffset: -2.4, diameter: 1.7, opacity: 0.64),
        ParticleStyle(phase: 0.09, speed: 0.142, radialOffset: 1.4, diameter: 1.5, opacity: 0.62),
        ParticleStyle(phase: 0.19, speed: 0.091, radialOffset: -1.8, diameter: 1.0, opacity: 0.44),
        ParticleStyle(phase: 0.29, speed: 0.182, radialOffset: 2.7, diameter: 1.8, opacity: 0.70),
        ParticleStyle(phase: 0.62, speed: 0.073, radialOffset: -0.8, diameter: 2.3, opacity: 0.76),
        ParticleStyle(phase: 0.81, speed: 0.133, radialOffset: -2.6, diameter: 1.2, opacity: 0.54),
        ParticleStyle(phase: 0.99, speed: 0.108, radialOffset: 1.9, diameter: 1.6, opacity: 0.60)
    ]

    static var maximumParticleRadialExtentForTesting: CGFloat {
        styles.map { abs($0.radialOffset) + $0.diameter / 2 }.max() ?? 0
    }

    let lanes: [QuotaParticleLane]
    let energyMode: VisualEnergyMode
    let animationMode: ParticleAnimationMode
    let reduceMotion: Bool
    let isPointerOverRing: Bool

    func makeNSView(context: Context) -> QuotaRingParticleHostView {
        let view = QuotaRingParticleHostView(frame: .zero)
        view.configure(
            lanes: lanes,
            energyMode: energyMode,
            animationMode: animationMode,
            reduceMotion: reduceMotion,
            isPointerOverRing: isPointerOverRing
        )
        return view
    }

    func updateNSView(_ nsView: QuotaRingParticleHostView, context: Context) {
        nsView.configure(
            lanes: lanes,
            energyMode: energyMode,
            animationMode: animationMode,
            reduceMotion: reduceMotion,
            isPointerOverRing: isPointerOverRing
        )
    }

    static func dismantleNSView(_ nsView: QuotaRingParticleHostView, coordinator: ()) {
        nsView.prepareForRemoval()
    }

    final class QuotaRingParticleHostView: NSView {
        private let particleContainer = CALayer()
        private var lanes: [QuotaParticleLane] = []
        private var energyMode: VisualEnergyMode = .suspended
        private var animationMode: ParticleAnimationMode = .standard
        private var reduceMotion = false
        private var isPointerOverRing = false
        private var renderedSize = CGSize.zero
        private var renderedScale: CGFloat = 0
        private var isRenderingParticles = false
        private var isPreparedForRemoval = false
        private var testingEligibilityOverride: Bool?
        private var windowObservers: [NSObjectProtocol] = []
        private var applicationObservers: [NSObjectProtocol] = []
        private var processObservers: [NSObjectProtocol] = []
        private var workspaceObservers: [NSObjectProtocol] = []

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false
            particleContainer.masksToBounds = false
            particleContainer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(particleContainer)
            installLifecycleObservers()
        }

        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            removeLifecycleObservers()
            removeWindowObservers()
        }

        func configure(
            lanes: [QuotaParticleLane],
            energyMode: VisualEnergyMode,
            animationMode: ParticleAnimationMode,
            reduceMotion: Bool,
            isPointerOverRing: Bool
        ) {
            guard !isPreparedForRemoval else { return }
            let lanes = lanes.map { lane in
                QuotaParticleLane(
                    radius: lane.radius,
                    progress: clampedProgress(lane.progress),
                    maximumCount: lane.maximumCount,
                    phaseOffset: lane.phaseOffset
                )
            }
            let lanesChanged = lanes != self.lanes

            self.lanes = lanes
            self.energyMode = energyMode
            self.animationMode = animationMode
            self.reduceMotion = reduceMotion
            self.isPointerOverRing = isPointerOverRing

            reconcileRendering(forceRebuild: lanesChanged)
        }

        func prepareForRemoval() {
            guard !isPreparedForRemoval else { return }
            isPreparedForRemoval = true
            clearParticles()
            removeWindowObservers()
            removeLifecycleObservers()
        }

        func setEligibilityOverrideForTesting(_ isEligible: Bool?) {
            testingEligibilityOverride = isEligible
            reconcileRendering()
        }

        var particleSublayerCountForTesting: Int {
            particleContainer.sublayers?.count ?? 0
        }

        var particleAnimationCountForTesting: Int {
            particleContainer.sublayers?.reduce(0) { count, layer in
                count + (layer.animationKeys()?.count ?? 0)
            } ?? 0
        }

        var particleAnimationPathsFitRingStrokeForTesting: Bool {
            guard let particles = particleContainer.sublayers, !particles.isEmpty else { return false }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let halfLineWidth = QuotaRingGeometry.lineWidth / 2

            return particles.allSatisfy { particle in
                let halfDiagonal = hypot(particle.bounds.width / 2, particle.bounds.height / 2)
                guard pointFitsRingStroke(
                    particle.position,
                    center: center,
                    halfDiagonal: halfDiagonal,
                    halfLineWidth: halfLineWidth
                ),
                let group = particle.animation(forKey: "quota-flow") as? CAAnimationGroup,
                let position = group.animations?.compactMap({ $0 as? CAKeyframeAnimation })
                    .first(where: { $0.keyPath == "position" }),
                let path = position.path
                else { return false }

                var pathFits = true
                var previousPoint: CGPoint?
                path.applyWithBlock { elementPointer in
                    guard pathFits else { return }
                    let element = elementPointer.pointee
                    switch element.type {
                    case .moveToPoint:
                        pathFits = pointFitsRingStroke(
                            element.points[0],
                            center: center,
                            halfDiagonal: halfDiagonal,
                            halfLineWidth: halfLineWidth
                        )
                        previousPoint = element.points[0]
                    case .addLineToPoint:
                        guard let segmentStart = previousPoint else {
                            pathFits = false
                            return
                        }
                        let point = element.points[0]
                        let halfSegmentLength = hypot(
                            point.x - segmentStart.x,
                            point.y - segmentStart.y
                        ) / 2
                        pathFits = pointFitsRingStroke(
                            segmentStart,
                            center: center,
                            halfDiagonal: halfDiagonal + halfSegmentLength,
                            halfLineWidth: halfLineWidth
                        ) && pointFitsRingStroke(
                            point,
                            center: center,
                            halfDiagonal: halfDiagonal + halfSegmentLength,
                            halfLineWidth: halfLineWidth
                        )
                        previousPoint = point
                    case .closeSubpath:
                        break
                    case .addQuadCurveToPoint, .addCurveToPoint:
                        pathFits = false
                    @unknown default:
                        pathFits = false
                    }
                }
                return pathFits
            }
        }

        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let geometryChanged = renderedSize != bounds.size || abs(renderedScale - scale) > 0.01

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particleContainer.frame = bounds
            particleContainer.contentsScale = scale
            CATransaction.commit()

            renderedSize = bounds.size
            renderedScale = scale
            reconcileRendering(forceRebuild: geometryChanged)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            renderedScale = 0
            needsLayout = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeWindowObservers()
            guard !isPreparedForRemoval, let window else {
                clearParticles()
                return
            }

            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification
            ]
            windowObservers = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    if notification.name == NSWindow.willCloseNotification {
                        self?.clearParticles()
                    } else {
                        self?.reconcileRendering()
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.reconcileRendering()
            }
        }

        private func reconcileRendering(forceRebuild: Bool = false) {
            guard !isPreparedForRemoval else {
                clearParticles()
                return
            }
            guard shouldRenderParticles else {
                clearParticles()
                return
            }
            guard bounds.width > 0, bounds.height > 0 else { return }
            guard forceRebuild || !isRenderingParticles else { return }
            rebuildAnimations()
        }

        private var shouldRenderParticles: Bool {
            if let testingEligibilityOverride {
                return testingEligibilityOverride
                    && lanes.contains { $0.progress != nil }
                    && (animationMode == .standard || isPointerOverRing)
            }
            guard let window else { return false }
            let processInfo = ProcessInfo.processInfo
            let currentProcessIdentifier = processInfo.processIdentifier
            let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
            return QuotaParticleRenderPolicy.shouldRender(
                hasProgress: lanes.contains { $0.progress != nil },
                energyMode: energyMode,
                animationMode: animationMode,
                reduceMotion: reduceMotion,
                isPointerOverRing: pointerIsActuallyOverRing(in: window),
                isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
                thermalState: processInfo.thermalState,
                appIsActive: NSApp.isActive,
                appIsHidden: NSApp.isHidden,
                appIsFrontmost: frontmostProcessIdentifier == currentProcessIdentifier,
                windowIsVisible: window.isVisible,
                windowIsMiniaturized: window.isMiniaturized,
                windowIsKey: window.isKeyWindow,
                windowIsOnActiveSpace: window.isOnActiveSpace,
                windowIsOccluded: !window.occlusionState.contains(.visible)
            )
        }

        private func pointerIsActuallyOverRing(in window: NSWindow) -> Bool {
            let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return QuotaRingHoverTarget.contains(
                location,
                activeRadii: lanes.map(\.radius)
            )
        }

        private func pointFitsRingStroke(
            _ point: CGPoint,
            center: CGPoint,
            halfDiagonal: CGFloat,
            halfLineWidth: CGFloat
        ) -> Bool {
            let radius = hypot(point.x - center.x, point.y - center.y)
            guard let centerlineDistance = lanes
                .map({ abs(radius - $0.radius) })
                .min()
            else { return false }
            return centerlineDistance + halfDiagonal <= halfLineWidth + 0.001
        }

        private func rebuildAnimations() {
            clearParticles()
            guard shouldRenderParticles else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            lanes.forEach { lane in
                addParticles(
                    center: center,
                    radius: lane.radius,
                    progress: lane.progress,
                    maximumCount: lane.maximumCount,
                    phaseOffset: lane.phaseOffset
                )
            }
            CATransaction.commit()
            isRenderingParticles = !(particleContainer.sublayers?.isEmpty ?? true)
        }

        private func clearParticles() {
            guard isRenderingParticles || !(particleContainer.sublayers?.isEmpty ?? true) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particleContainer.sublayers?.forEach { particle in
                particle.removeAllAnimations()
                particle.removeFromSuperlayer()
            }
            CATransaction.commit()
            isRenderingParticles = false
        }

        private func addParticles(
            center: CGPoint,
            radius: CGFloat,
            progress: CGFloat?,
            maximumCount: Int,
            phaseOffset: Double
        ) {
            guard let progress, progress > 0.02 else { return }
            let activeCount = min(
                maximumCount,
                max(1, Int(ceil(Double(maximumCount) * min(1, Double(progress) * 1.5))))
            )
            let activeStyles = Array(DualQuotaRingParticles.styles.prefix(activeCount))
            let speedFactor = quotaSpeedFactor(for: progress)
            let fastParticleCount = max(1, Int((Double(activeCount) * 0.3).rounded()))
            let fastParticleIndexes = Set(
                activeStyles.indices
                    .sorted {
                        actualSpeed(
                            for: activeStyles[$0],
                            progress: progress,
                            speedFactor: speedFactor
                        ) > actualSpeed(
                            for: activeStyles[$1],
                            progress: progress,
                            speedFactor: speedFactor
                        )
                    }
                    .prefix(fastParticleCount)
            )

            for (index, style) in activeStyles.enumerated() {
                let particleRadius = radius + style.radialOffset
                let path = particlePath(center: center, radius: particleRadius, progress: progress)
                let startPosition = arcPoint(center: center, radius: particleRadius, progress: progress)
                let duration = animationDuration(
                    for: style,
                    progress: progress,
                    speedFactor: speedFactor
                )
                let phase = (style.phase + phaseOffset).truncatingRemainder(dividingBy: 1)

                if fastParticleIndexes.contains(index) {
                    addAnimatedParticle(
                        style: style,
                        path: path,
                        startPosition: startPosition,
                        duration: duration,
                        phase: phase,
                        diameterScale: 0.40,
                        opacityScale: 0.12,
                        lag: 0.135
                    )
                    addAnimatedParticle(
                        style: style,
                        path: path,
                        startPosition: startPosition,
                        duration: duration,
                        phase: phase,
                        diameterScale: 0.58,
                        opacityScale: 0.24,
                        lag: 0.090
                    )
                    addAnimatedParticle(
                        style: style,
                        path: path,
                        startPosition: startPosition,
                        duration: duration,
                        phase: phase,
                        diameterScale: 0.78,
                        opacityScale: 0.42,
                        lag: 0.045
                    )
                }

                addAnimatedParticle(
                    style: style,
                    path: path,
                    startPosition: startPosition,
                    duration: duration,
                    phase: phase
                )
            }
        }

        private func addAnimatedParticle(
            style: ParticleStyle,
            path: CGPath,
            startPosition: CGPoint,
            duration: Double,
            phase: Double,
            diameterScale: CGFloat = 1,
            opacityScale: Double = 1,
            lag: Double = 0
        ) {
            let diameter = style.diameter * diameterScale
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            particle.cornerRadius = diameter / 2
            particle.backgroundColor = WidgetPalette.dataFlowParticle.cgColor
            particle.opacity = 0
            particle.position = startPosition
            particle.contentsScale = particleContainer.contentsScale
            particleContainer.addSublayer(particle)

            let position = CAKeyframeAnimation(keyPath: "position")
            position.path = path
            position.calculationMode = .paced

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            let visibleOpacity = style.opacity * opacityScale
            opacity.values = [0, visibleOpacity, visibleOpacity, 0]
            opacity.keyTimes = [0, 0.08, 0.88, 1]

            let animation = CAAnimationGroup()
            animation.animations = [position, opacity]
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: 60,
                preferred: 60
            )
            animation.beginTime = CACurrentMediaTime()
            let rawOffset = (duration * phase - lag).truncatingRemainder(dividingBy: duration)
            animation.timeOffset = rawOffset >= 0 ? rawOffset : rawOffset + duration
            animation.isRemovedOnCompletion = false
            particle.add(animation, forKey: "quota-flow")
        }

        private func quotaSpeedFactor(for progress: CGFloat) -> Double {
            0.45 + Double(progress) * 1.10
        }

        private func animationDuration(
            for style: ParticleStyle,
            progress: CGFloat,
            speedFactor: Double
        ) -> Double {
            max(1.6, Double(progress) / (style.speed * speedFactor))
        }

        private func actualSpeed(
            for style: ParticleStyle,
            progress: CGFloat,
            speedFactor: Double
        ) -> Double {
            let duration = animationDuration(
                for: style,
                progress: progress,
                speedFactor: speedFactor
            )
            return Double(progress) / duration
        }

        private func particlePath(center: CGPoint, radius: CGFloat, progress: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let sampleCount = max(16, Int(ceil(progress * 120)))
            path.move(to: arcPoint(center: center, radius: radius, progress: progress))
            for index in 1...sampleCount {
                let fraction = CGFloat(index) / CGFloat(sampleCount)
                path.addLine(to: arcPoint(
                    center: center,
                    radius: radius,
                    progress: progress * (1 - fraction)
                ))
            }
            return path
        }

        private func arcPoint(center: CGPoint, radius: CGFloat, progress: CGFloat) -> CGPoint {
            let radians = (-90.0 + Double(progress) * 360) * .pi / 180
            return CGPoint(
                x: center.x + CGFloat(cos(radians)) * radius,
                y: center.y + CGFloat(sin(radians)) * radius
            )
        }

        private func clampedProgress(_ progress: CGFloat?) -> CGFloat? {
            guard let progress, progress > 0.02 else { return nil }
            return max(0, min(1, progress))
        }

        private func installLifecycleObservers() {
            let notificationCenter = NotificationCenter.default
            applicationObservers = [
                NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification,
                NSApplication.didHideNotification,
                NSApplication.didUnhideNotification
            ].map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    self?.reconcileRendering()
                    DispatchQueue.main.async { [weak self] in
                        self?.reconcileRendering()
                    }
                }
            }

            processObservers = [
                Notification.Name.NSProcessInfoPowerStateDidChange,
                ProcessInfo.thermalStateDidChangeNotification
            ].map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reconcileRendering()
                }
            }

            workspaceObservers = [
                NSWorkspace.activeSpaceDidChangeNotification,
                NSWorkspace.didActivateApplicationNotification
            ].map { name in
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reconcileRendering()
                }
            }
        }

        private func removeWindowObservers() {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers.removeAll()
        }

        private func removeLifecycleObservers() {
            applicationObservers.forEach(NotificationCenter.default.removeObserver)
            applicationObservers.removeAll()
            processObservers.forEach(NotificationCenter.default.removeObserver)
            processObservers.removeAll()
            workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            workspaceObservers.removeAll()
        }
    }
}

private enum QuotaParticleAnimationSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        func renders(
            hasProgress: Bool = true,
            energyMode: VisualEnergyMode = .normal,
            animationMode: ParticleAnimationMode = .standard,
            reduceMotion: Bool = false,
            isPointerOverRing: Bool = false,
            isLowPowerModeEnabled: Bool = false,
            thermalState: ProcessInfo.ThermalState = .nominal,
            appIsActive: Bool = true,
            appIsHidden: Bool = false,
            appIsFrontmost: Bool = true,
            windowIsVisible: Bool = true,
            windowIsMiniaturized: Bool = false,
            windowIsKey: Bool = true,
            windowIsOnActiveSpace: Bool = true,
            windowIsOccluded: Bool = false
        ) -> Bool {
            QuotaParticleRenderPolicy.shouldRender(
                hasProgress: hasProgress,
                energyMode: energyMode,
                animationMode: animationMode,
                reduceMotion: reduceMotion,
                isPointerOverRing: isPointerOverRing,
                isLowPowerModeEnabled: isLowPowerModeEnabled,
                thermalState: thermalState,
                appIsActive: appIsActive,
                appIsHidden: appIsHidden,
                appIsFrontmost: appIsFrontmost,
                windowIsVisible: windowIsVisible,
                windowIsMiniaturized: windowIsMiniaturized,
                windowIsKey: windowIsKey,
                windowIsOnActiveSpace: windowIsOnActiveSpace,
                windowIsOccluded: windowIsOccluded
            )
        }

        func quotaWindow(usedPercent: Double, durationMins: Int) -> RateWindow {
            RateWindow(
                usedPercent: usedPercent,
                windowDurationMins: durationMins,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }

        let fullFiveHour = quotaWindow(usedPercent: 0, durationMins: 300)
        let fullSevenDay = quotaWindow(usedPercent: 0, durationMins: 10_080)
        let noQuotaPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: nil
        )
        let fiveHourOnlyPresentation = QuotaRingPresentation(
            fiveHourQuota: fullFiveHour,
            sevenDayQuota: nil
        )
        let sevenDayOnlyPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: fullSevenDay
        )
        let dualPresentation = QuotaRingPresentation(
            fiveHourQuota: fullFiveHour,
            sevenDayQuota: fullSevenDay
        )

        expect(noQuotaPresentation.topology == .none, "zero quota windows should use the empty presentation")
        expect(noQuotaPresentation.items.isEmpty, "empty presentation should not expose reset rows")
        expect(noQuotaPresentation.particleLanes.isEmpty, "empty presentation should not expose particle lanes")
        expect(fiveHourOnlyPresentation.topology == .single, "5h-only quota should use a single ring")
        expect(
            fiveHourOnlyPresentation.items.map(\.kind) == [.fiveHour],
            "5h-only presentation should preserve the blue 5h semantic"
        )
        expect(sevenDayOnlyPresentation.topology == .single, "7d-only quota should use a single ring")
        expect(
            sevenDayOnlyPresentation.items.map(\.kind) == [.sevenDay],
            "7d-only presentation should preserve the purple 7d semantic"
        )
        expect(
            sevenDayOnlyPresentation.particleLanes.count == 1
                && sevenDayOnlyPresentation.particleLanes[0].radius == QuotaRingGeometry.outerRadius
                && sevenDayOnlyPresentation.particleLanes[0].maximumCount == 17,
            "a single 7d quota should expand onto the full outer particle lane"
        )
        expect(dualPresentation.topology == .dual, "two quota windows should retain the dual-ring presentation")
        expect(
            dualPresentation.items.map(\.kind) == [.fiveHour, .sevenDay],
            "dual presentation should retain the stable 5h then 7d order"
        )
        expect(
            dualPresentation.activeRadii == [
                QuotaRingGeometry.outerRadius,
                QuotaRingGeometry.innerRadius
            ],
            "dual presentation should expose both active ring radii"
        )
        expect(
            fiveHourOnlyPresentation.items.count == 1
                && sevenDayOnlyPresentation.items.count == 1
                && dualPresentation.items.count == 2,
            "reset summary should receive only real quota rows"
        )
        expect(
            QuotaRingGeometry.singleCenterDiameter == 110,
            "single-ring center should preserve the dual-ring inner-edge clearance"
        )

        expect(renders(), "default mode should render in a focused frontmost window")
        expect(
            !renders(animationMode: .powerSaving),
            "power-saving mode should stay empty without ring hover"
        )
        expect(
            renders(animationMode: .powerSaving, isPointerOverRing: true),
            "power-saving mode should render while the ring is hovered"
        )
        expect(
            QuotaRingHoverTarget.contains(CGPoint(
                x: QuotaRingGeometry.center.x,
                y: QuotaRingGeometry.center.y - QuotaRingGeometry.outerRadius
            ), activeRadii: dualPresentation.activeRadii),
            "outer ring should be a power-saving hover target"
        )
        expect(
            QuotaRingHoverTarget.contains(CGPoint(
                x: QuotaRingGeometry.center.x + QuotaRingGeometry.innerRadius,
                y: QuotaRingGeometry.center.y
            ), activeRadii: dualPresentation.activeRadii),
            "inner ring should be a power-saving hover target"
        )
        expect(
            !QuotaRingHoverTarget.contains(
                CGPoint(
                    x: QuotaRingGeometry.center.x + QuotaRingGeometry.innerRadius,
                    y: QuotaRingGeometry.center.y
                ),
                activeRadii: sevenDayOnlyPresentation.activeRadii
            ),
            "single-ring mode should not react to the removed inner ring"
        )
        expect(
            !QuotaRingHoverTarget.contains(
                CGPoint(
                    x: QuotaRingGeometry.center.x,
                    y: QuotaRingGeometry.center.y - QuotaRingGeometry.outerRadius
                ),
                activeRadii: noQuotaPresentation.activeRadii
            ),
            "empty mode should not expose a hidden hover target"
        )
        expect(
            !QuotaRingHoverTarget.contains(
                QuotaRingGeometry.center,
                activeRadii: dualPresentation.activeRadii
            ),
            "center labels should not trigger power-saving particles"
        )
        expect(
            !QuotaRingHoverTarget.contains(
                CGPoint(x: 0, y: 0),
                activeRadii: dualPresentation.activeRadii
            ),
            "ring component corners should not trigger power-saving particles"
        )
        expect(
            abs(QuotaRingGeometry.outerRadius - 64.5) < 0.0001
                && abs(QuotaRingGeometry.innerRadius - 45.5) < 0.0001,
            "inset ring strokes should share the original particle centerline radii"
        )
        expect(
            DualQuotaRingParticles.maximumParticleRadialExtentForTesting
                <= QuotaRingGeometry.lineWidth / 2,
            "every particle pixel should remain inside the aligned ring stroke"
        )
        expect(!renders(hasProgress: false), "missing quota progress should not allocate particles")
        expect(!renders(energyMode: .suspended), "suspended visual energy mode should stop particles")
        expect(!renders(energyMode: .constrained), "constrained visual energy mode should stop particles")
        expect(!renders(reduceMotion: true), "Reduce Motion should stop particles")
        expect(!renders(isLowPowerModeEnabled: true), "Low Power Mode should stop particles")
        expect(!renders(thermalState: .fair), "thermal pressure should stop particles")
        expect(!renders(appIsActive: false), "inactive app should stop particles")
        expect(!renders(appIsHidden: true), "hidden app should stop particles")
        expect(!renders(appIsFrontmost: false), "non-frontmost app should stop particles")
        expect(!renders(windowIsVisible: false), "closed or ordered-out window should stop particles")
        expect(!renders(windowIsMiniaturized: true), "miniaturized window should stop particles")
        expect(!renders(windowIsKey: false), "unfocused window should stop particles")
        expect(!renders(windowIsOnActiveSpace: false), "window on another Space should stop particles")
        expect(!renders(windowIsOccluded: true), "occluded window should stop particles")

        let host = DualQuotaRingParticles.QuotaRingParticleHostView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: QuotaRingGeometry.outerDiameter,
                height: QuotaRingGeometry.outerDiameter
            )
        )
        host.setEligibilityOverrideForTesting(true)
        host.configure(
            lanes: [
                QuotaParticleLane(
                    radius: QuotaRingGeometry.outerRadius,
                    progress: 0.03,
                    maximumCount: 17,
                    phaseOffset: 0
                ),
                QuotaParticleLane(
                    radius: QuotaRingGeometry.innerRadius,
                    progress: 0.03,
                    maximumCount: 12,
                    phaseOffset: 0.31
                )
            ],
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 8,
            "three-percent progress should create the expected sparse particle field"
        )
        expect(
            host.particleAnimationPathsFitRingStrokeForTesting,
            "sparse particle paths should remain inside both aligned ring strokes"
        )
        host.configure(
            lanes: [
                QuotaParticleLane(
                    radius: QuotaRingGeometry.outerRadius,
                    progress: 0.5,
                    maximumCount: 17,
                    phaseOffset: 0
                ),
                QuotaParticleLane(
                    radius: QuotaRingGeometry.innerRadius,
                    progress: 0.5,
                    maximumCount: 12,
                    phaseOffset: 0.31
                )
            ],
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 43,
            "half progress should preserve the original particle density"
        )
        expect(
            host.particleAnimationPathsFitRingStrokeForTesting,
            "partial particle paths should remain inside both aligned ring strokes"
        )
        host.configure(
            lanes: dualPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 56,
            "full original particle field should create 56 particle and trail layers"
        )
        expect(
            host.particleAnimationCountForTesting == 56,
            "every original particle and trail layer should run one quota-flow animation group"
        )
        expect(
            host.particleAnimationPathsFitRingStrokeForTesting,
            "full-circle particle paths should remain inside both aligned ring strokes"
        )
        host.configure(
            lanes: sevenDayOnlyPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 32,
            "full single-ring particle field should use the outer-ring density only"
        )
        expect(
            host.particleAnimationCountForTesting == 32,
            "every single-ring particle and trail layer should run one animation group"
        )
        expect(
            host.particleAnimationPathsFitRingStrokeForTesting,
            "single-ring particle paths should fit the active outer stroke"
        )
        host.configure(
            lanes: noQuotaPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 0,
            "empty presentation should immediately remove every particle layer"
        )
        host.configure(
            lanes: dualPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .powerSaving,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 0,
            "power-saving mode should remove particles before ring hover"
        )
        host.configure(
            lanes: dualPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .powerSaving,
            reduceMotion: false,
            isPointerOverRing: true
        )
        expect(
            host.particleSublayerCountForTesting == 56,
            "power-saving ring hover should restore the full original particle field"
        )
        host.configure(
            lanes: dualPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .powerSaving,
            reduceMotion: false,
            isPointerOverRing: false
        )
        expect(
            host.particleSublayerCountForTesting == 0,
            "leaving the ring should immediately remove power-saving particles"
        )
        host.configure(
            lanes: dualPresentation.particleLanes,
            energyMode: .normal,
            animationMode: .standard,
            reduceMotion: false,
            isPointerOverRing: false
        )
        host.setEligibilityOverrideForTesting(false)
        expect(
            host.particleSublayerCountForTesting == 0,
            "ineligible state should remove particle sublayers instead of pausing them"
        )
        expect(
            host.particleAnimationCountForTesting == 0,
            "ineligible state should remove all particle animations"
        )
        host.prepareForRemoval()

        let suiteName = "codexU.particle-animation-self-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("particle animation self-test failed: could not create UserDefaults suite")
            return false
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        expect(
            ParticleAnimationMode.storedOrDefault(defaults: defaults) == .standard,
            "missing particle animation preference should default to standard"
        )
        let settings = AppSettings(defaults: defaults)
        settings.particleAnimationMode = .powerSaving
        expect(
            defaults.string(forKey: ParticleAnimationMode.storageKey) == ParticleAnimationMode.powerSaving.rawValue,
            "particle animation preference should persist immediately"
        )
        expect(
            AppSettings(defaults: defaults).particleAnimationMode == .powerSaving,
            "particle animation preference should survive AppSettings recreation"
        )
        defaults.set("future-mode", forKey: ParticleAnimationMode.storageKey)
        expect(
            ParticleAnimationMode.storedOrDefault(defaults: defaults) == .standard,
            "unknown particle animation preference should fall back to standard"
        )

        if failures.isEmpty {
            print("particle animation self-test passed")
            return true
        }
        failures.forEach { print("particle animation self-test failed: \($0)") }
        return false
    }
}

struct QuotaRingLabel: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

private struct SingleQuotaRingLabel: View {
    let item: QuotaRingItem
    let language: WidgetLanguage
    let isStale: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(item.kind.compactTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(item.kind.color)
            Text(item.remainingText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(
                isStale
                    ? language.text("旧快照", "stale")
                    : language.text("剩余", "left")
            )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuotaUnavailablePlaceholder: View {
    let isAuthoritative: Bool
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: isAuthoritative ? "infinity.circle" : "gauge")
                .font(.system(size: 24, weight: .medium))
            Text(
                isAuthoritative
                    ? language.text("当前无额度限制", "No active quota limits")
                    : language.text("暂无额度数据", "No quota data")
            )
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(
            width: QuotaRingGeometry.singleCenterDiameter,
            height: QuotaRingGeometry.singleCenterDiameter
        )
        .accessibilityElement(children: .combine)
    }
}

struct QuotaResetSummary: View {
    let fiveHourQuota: RateWindow?
    let sevenDayQuota: RateWindow?
    let language: WidgetLanguage

    private var presentation: QuotaRingPresentation {
        QuotaRingPresentation(
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(presentation.items) { item in
                QuotaResetLine(
                    title: item.kind.compactTitle,
                    window: item.window,
                    color: item.kind.color,
                    language: language
                )
            }
        }
    }
}

struct QuotaResetLine: View {
    let title: String
    let window: RateWindow
    let color: Color
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(language.text("重置", "resets"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(resetText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else { return "--" }
        return resetDateTime(resetsAt, language: language)
    }
}

struct DailyTokenChart: View {
    let buckets: [DailyTokenBucket]
    let language: WidgetLanguage

    private var maxTokens: Int64 {
        max(buckets.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(buckets) { bucket in
                DailyTokenBar(bucket: bucket, maxTokens: maxTokens, language: language)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
    }
}

struct DailyTokenBar: View {
    let bucket: DailyTokenBucket
    let maxTokens: Int64
    let language: WidgetLanguage

    private var barHeight: CGFloat {
        let ratio = Double(bucket.tokens) / Double(maxTokens)
        return max(4, CGFloat(ratio) * 54)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(formatTokens(bucket.tokens))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WidgetPalette.surfaceTrack)
                    .frame(height: 58)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bucket.tokens == 0 ? WidgetPalette.dataZero : WidgetPalette.brandPrimary.opacity(bucket.label == "今天" ? 1 : 0.58))
                    .frame(height: barHeight)
            }
            Text(localizedDayLabel(bucket.label, language: language))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(bucket.label == "今天" ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetailedTokenMetricCard: View {
    let title: String
    let systemName: String
    let usage: PricedTokenUsage?
    let fallbackTokens: Int64?
    let showsEstimatedCost: Bool
    let language: WidgetLanguage

    private var displayTokens: Int64? {
        usage?.tokens.visibleTotalTokens ?? fallbackTokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WidgetPalette.surfaceTrack)
                    )
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(showsEstimatedCost ? formatUSD(usage?.estimatedCostUSD) : language.text("本机", "Local"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(height: dashboardCardHeaderHeight, alignment: .center)

            Text(formatTokens(displayTokens))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            TokenSplitBar(tokens: usage?.tokens)
                .frame(height: 8)

            VStack(spacing: 3) {
                TokenSplitLegendRow(
                    title: language.text("未缓存", "Input"),
                    value: usage?.tokens.uncachedInputTokens,
                    color: uncachedInputColor
                )
                TokenSplitLegendRow(
                    title: language.text("缓存", "Cached"),
                    value: usage?.tokens.billableCachedInputTokens,
                    color: cachedInputColor
                )
                TokenSplitLegendRow(
                    title: language.text("输出", "Output"),
                    value: usage?.tokens.outputTokens,
                    color: outputTokenColor
                )
            }
        }
        .padding(dashboardCardPadding)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }
}

struct CodexOfficialUsageStrip: View {
    let lifetimeTokens: Int64?
    let trend: UsageTrend?
    let language: WidgetLanguage

    @Environment(\.colorScheme) private var colorScheme

    private var sourceLabel: String {
        lifetimeTokens == nil && trend == nil
            ? language.text("暂不可用", "Unavailable")
            : language.text("服务端汇总", "Server summary")
    }

    private var latestBucket: UsageDayBucket? {
        trend?.dayBuckets.last(where: { $0.tokens > 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.brandPrimary)
                Text(language.text("Codex App 官方用量", "Codex App official usage"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(WidgetPalette.controlFill(colorScheme))
                    )
            }

            HStack(spacing: 0) {
                officialMetric(
                    title: latestBucket.map {
                        language.text("最近一天 \(shortDate($0.date))", "Latest \(shortDate($0.date))")
                    } ?? language.text("最近一天", "Latest day"),
                    tokens: latestBucket?.tokens
                )
                Divider().frame(height: 30)
                officialMetric(
                    title: language.text("近 7 天", "Last 7 days"),
                    tokens: trend?.summary.sevenDay.tokens.visibleTotalTokens
                )
                Divider().frame(height: 30)
                officialMetric(
                    title: language.text("累计", "Lifetime"),
                    tokens: lifetimeTokens
                )
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: dashboardCardCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack)
                .overlay(
                    RoundedRectangle(cornerRadius: dashboardCardCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .help(language.text(
            "直接来自 Codex App 的 account/usage/read，与个人资料中的 token 活动使用同一服务端数据；本机上下文数据仅用于拆分和归因。",
            "Directly from Codex App account/usage/read, the same server data used by Profile token activity. Local context data is only for breakdowns and attribution."
        ))
    }

    private func officialMetric(title: String, tokens: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(formatTokens(tokens))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = language.isChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }
}

struct TokenSplitBar: View {
    let tokens: TokenBreakdown?

    var body: some View {
        GeometryReader { geometry in
            let splitTotal = tokens?.splitTotalTokens ?? 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WidgetPalette.surfaceTrack)

                if let tokens, splitTotal > 0 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(uncachedInputColor)
                            .frame(width: segmentWidth(tokens.uncachedInputTokens, total: splitTotal, available: geometry.size.width))
                        Rectangle()
                            .fill(cachedInputColor)
                            .frame(width: segmentWidth(tokens.billableCachedInputTokens, total: splitTotal, available: geometry.size.width))
                        Rectangle()
                            .fill(outputTokenColor)
                            .frame(width: segmentWidth(tokens.outputTokens, total: splitTotal, available: geometry.size.width))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    private func segmentWidth(_ value: Int64, total: Int64, available: CGFloat) -> CGFloat {
        guard total > 0, value > 0 else { return 0 }
        return max(2, available * CGFloat(Double(value) / Double(total)))
    }
}

struct TokenSplitLegendRow: View {
    let title: String
    let value: Int64?
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formatTokens(value))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct SubscriptionMilestone: Identifiable {
    let id: String
    let title: String
    let amountUSD: Double
    let color: Color
}

private let subscriptionMilestones: [SubscriptionMilestone] = [
    SubscriptionMilestone(id: "plus", title: "Plus", amountUSD: 20, color: WidgetPalette.statusInfo),
    SubscriptionMilestone(id: "pro100", title: "Pro100", amountUSD: 100, color: WidgetPalette.brandSecondary),
    SubscriptionMilestone(id: "pro200", title: "Pro200", amountUSD: 200, color: WidgetPalette.brandPrimaryLight)
]

// Used only for the full-quota monthly ceiling. Actual usage still uses per-session model prices and token splits.
private let quotaValueDailyTokenLimit: Double = 200_000_000
private let quotaValueBillingDays: Double = 30
private let quotaValueUncachedInputShare = 0.30
private let quotaValueCachedInputShare = 0.50
private let quotaValueOutputShare = 0.20
private let quotaValueReferencePrice = modelTokenPrice(for: "chat-latest")
private let quotaValueWeightedPricePerMillion =
    quotaValueUncachedInputShare * quotaValueReferencePrice.inputPerMillion
    + quotaValueCachedInputShare * quotaValueReferencePrice.cachedInputPerMillion
    + quotaValueOutputShare * quotaValueReferencePrice.outputPerMillion
private let quotaValueMonthlyTokenLimit = quotaValueDailyTokenLimit * quotaValueBillingDays
private let quotaValueMonthlyMaxUSD = quotaValueMonthlyTokenLimit / 1_000_000 * quotaValueWeightedPricePerMillion

struct LocalAgentOverviewCard: View {
    let scope: RuntimeScope
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 9) {
            RuntimeLogoView(scope: scope, size: 62)
                .accessibilityHidden(true)
            Text(scope.displayName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(WidgetPalette.statusSuccess)
                    .frame(width: 6, height: 6)
                Text(language.text("只读本机记录", "Local records only"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(storageNote)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }

    private var subtitle: String {
        switch scope {
        case .codex:
            return language.text("本机 Codex", "Local Codex")
        case .openClaw:
            return language.text("本机 main agent", "Local main agent")
        case .claudeCode:
            return language.text("本机会话", "Local sessions")
        case .hermes:
            return language.text("本机默认 profile", "Local default profile")
        }
    }

    private var storageNote: String {
        switch scope {
        case .codex:
            return language.text("本机记录", "Local records")
        case .openClaw:
            return language.text("不读取 NAS", "NAS excluded")
        case .claudeCode:
            return "~/.claude"
        case .hermes:
            return "~/.hermes/state.db"
        }
    }
}

struct RuntimeAttributionCard: View {
    let scope: RuntimeScope
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetPalette.statusInfo)
                Text(language.text("token 归属", "Token attribution"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(language.text("按实际执行方", "By executing runtime"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if scope == .openClaw {
                    attributionPill(
                        scope: .openClaw,
                        text: language.text("main agent → OpenClaw", "main agent → OpenClaw")
                    )
                    attributionPill(
                        scope: .codex,
                        text: language.text("Codex 子代理 → Codex", "Codex subagent → Codex")
                    )
                } else {
                    attributionPill(
                        scope: scope,
                        text: language.text("本机会话 → \(scope.displayName)", "Local sessions → \(scope.displayName)")
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(dashboardCardPadding)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }

    private func attributionPill(scope: RuntimeScope, text: String) -> some View {
        HStack(spacing: 5) {
            RuntimeLogoView(scope: scope, size: 14)
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(WidgetPalette.surfaceTrack)
        )
    }
}

struct WoolProgressCard: View {
    let usage: PricedTokenUsage?
    let language: WidgetLanguage

    private var cost: Double {
        usage?.estimatedCostUSD ?? 0
    }

    private var maxValue: Double {
        max(quotaValueMonthlyMaxUSD, subscriptionMilestones.map(\.amountUSD).max() ?? 200)
    }

    private var accent: Color {
        if cost >= 200 { return WidgetPalette.brandPrimaryLight }
        if cost >= 100 { return WidgetPalette.brandSecondary }
        if cost >= 20 { return WidgetPalette.statusInfo }
        return WidgetPalette.statusWarning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: cost >= 20 ? "chart.line.uptrend.xyaxis" : "target")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                Text(language.text("羊毛进度", "Value progress"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(formatUSD(usage?.estimatedCostUSD))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ \(formatCompactUSD(maxValue))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: dashboardCardHeaderHeight, alignment: .center)

            QuotaValueProgressBar(
                currentValue: cost,
                maxValue: maxValue
            )
            .frame(height: 18)

            HStack(spacing: 8) {
                ForEach(subscriptionMilestones) { milestone in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(milestone.color)
                            .frame(width: 5, height: 5)
                        Text(milestone.title)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("\(language.text("满额", "Cap")) \(formatCompactUSD(maxValue))")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        }
        .padding(dashboardCardPadding)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }
}

struct QuotaValueProgressBar: View {
    let currentValue: Double
    let maxValue: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = valueOffset(currentValue, width: width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(WidgetPalette.surfaceTrack)
                    .frame(height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                WidgetPalette.brandPrimaryLight,
                                WidgetPalette.brandPrimary,
                                WidgetPalette.brandSecondaryStrong
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: currentValue > 0 ? max(5, progressWidth) : 0, height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)

                ForEach(subscriptionMilestones) { milestone in
                    let x = valueOffset(milestone.amountUSD, width: width)
                    Circle()
                        .fill(milestone.color)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .offset(x: x - 3.5)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .help("\(milestone.title) \(formatUSD(milestone.amountUSD))")
                }
            }
        }
    }

    private func valueOffset(_ amount: Double, width: CGFloat) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        let subscriptionCeiling = subscriptionMilestones.map(\.amountUSD).max() ?? 200
        let subscriptionBand = 0.28
        let clamped = max(0, min(amount, maxValue))

        let fraction: Double
        if clamped <= subscriptionCeiling {
            fraction = subscriptionBand * (clamped / subscriptionCeiling)
        } else {
            let remainingValue = max(maxValue - subscriptionCeiling, 0)
            let scaleBase = max(subscriptionCeiling, 1)
            if remainingValue <= 0 {
                fraction = 1
            } else {
                let tailValue = clamped - subscriptionCeiling
                let tailProgress = log1p(tailValue / scaleBase) / log1p(remainingValue / scaleBase)
                fraction = subscriptionBand + (1 - subscriptionBand) * tailProgress
            }
        }

        let raw = width * CGFloat(max(0, min(1, fraction)))
        return min(max(raw, 0), width)
    }
}

struct TokenMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(language.text("Tokens", "Tokens"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(dashboardCardPadding)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }
}

struct MiniTrendCard: View {
    let buckets: [DailyTokenBucket]
    let language: WidgetLanguage

    private var maxTokens: Int64 {
        max(buckets.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("近 7 天使用趋势", "7-day trend"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(buckets) { bucket in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(bucket.tokens == 0 ? WidgetPalette.dataZero : WidgetPalette.brandPrimary.opacity(bucket.label == "今天" ? 1 : 0.55))
                        .frame(width: 12, height: miniBarHeight(bucket.tokens))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack {
                Text(language.text("一", "M"))
                Spacer()
                Text(language.text("三", "W"))
                Spacer()
                Text(language.text("五", "F"))
                Spacer()
                Text(language.text("今", "Now"))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(dashboardCardPadding)
        .frame(width: 132, alignment: .leading)
        .frame(minHeight: 78, alignment: .leading)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }

    private func miniBarHeight(_ tokens: Int64) -> CGFloat {
        let ratio = Double(tokens) / Double(maxTokens)
        return max(6, CGFloat(ratio) * 34)
    }
}

struct ChartTooltipRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

struct ChartTooltipPayload: Equatable {
    let title: String
    let rows: [ChartTooltipRow]
}

struct ChartTooltipView: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: ChartTooltipPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(payload.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            VStack(spacing: 4) {
                ForEach(payload.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.cardFill(colorScheme, elevated: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WidgetPalette.cardStroke(colorScheme, elevated: true), lineWidth: 0.9)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 10, x: 0, y: 5)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private func usageTooltipPayload(
    date: Date,
    usage: PricedTokenUsage?,
    runtimeScope: RuntimeScope,
    sourceQuality: UsageSourceQuality,
    language: WidgetLanguage
) -> ChartTooltipPayload {
    let title = fullDateText(date, language: language)
    guard let usage, usage.tokens.visibleTotalTokens > 0 else {
        let emptyStatus = sourceQuality == .official
            ? language.text("无官方记录", "No official records")
            : language.text("无本机记录", "No local records")
        return ChartTooltipPayload(
            title: title,
            rows: [
                ChartTooltipRow(id: "runtime", label: "Runtime", value: runtimeScope.displayName),
                ChartTooltipRow(id: "total", label: language.text("总量", "Total"), value: "0 tokens"),
                ChartTooltipRow(id: "status", label: language.text("状态", "Status"), value: emptyStatus),
                ChartTooltipRow(id: "source", label: language.text("口径", "Source"), value: sourceQualityText(sourceQuality, language: language))
            ]
        )
    }

    var rows = [
        ChartTooltipRow(id: "runtime", label: "Runtime", value: runtimeScope.displayName),
        ChartTooltipRow(
            id: "total",
            label: language.text("总量", "Total"),
            value: "\(formatTokens(usage.tokens.visibleTotalTokens)) tokens"
        )
    ]

    if usage.tokens.splitTotalTokens > 0 {
        rows.append(ChartTooltipRow(
            id: "uncached",
            label: language.text("未缓存", "Input"),
            value: formatTokens(usage.tokens.uncachedInputTokens)
        ))
        rows.append(ChartTooltipRow(
            id: "cached",
            label: language.text("缓存", "Cached"),
            value: formatTokens(usage.tokens.billableCachedInputTokens)
        ))
        rows.append(ChartTooltipRow(
            id: "output",
            label: language.text("输出", "Output"),
            value: formatTokens(usage.tokens.outputTokens)
        ))
    } else {
        rows.append(ChartTooltipRow(
            id: "split",
            label: language.text("拆分", "Split"),
            value: language.text("暂不可用", "Unavailable")
        ))
    }

    if usage.estimatedCostUSD > 0 {
        rows.append(ChartTooltipRow(
            id: "cost",
            label: language.text("估算", "Est."),
            value: formatUSD(usage.estimatedCostUSD)
        ))
    }

    rows.append(ChartTooltipRow(
        id: "source",
        label: language.text("口径", "Source"),
        value: sourceQualityText(sourceQuality, language: language)
    ))

    return ChartTooltipPayload(title: title, rows: rows)
}

struct UsageTrendPanel: View {
    let trend: UsageTrend?
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage

    var body: some View {
        if let trend {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: usageTrendCardSpacing) {
                    UsageHeatmapCard(trend: trend, runtimeScope: runtimeScope, language: language)
                        .frame(
                            width: usageTrendHeatmapCardWidth(
                                containerWidth: geometry.size.width,
                                weekCount: trend.heatmapWeeks.count
                            ),
                            height: usageTrendCardHeight,
                            alignment: .topLeading
                        )
                    UsageSevenDaySummaryCard(trend: trend, runtimeScope: runtimeScope, language: language)
                        .frame(
                            width: usageTrendSevenDayCardWidth(
                                containerWidth: geometry.size.width,
                                weekCount: trend.heatmapWeeks.count
                            ),
                            height: usageTrendCardHeight,
                            alignment: .topLeading
                        )
                }
            }
            .frame(height: usageTrendCardHeight)
        } else {
            AnalyticsEmptyState(
                systemName: "chart.bar.doc.horizontal",
                title: language.text("暂无用量趋势", "No usage trend"),
                detail: language.text(
                    "完成一次 \(runtimeScope.displayName) 会话后，这里会显示最近半年的每日 token 热力图。",
                    "After one \(runtimeScope.displayName) session, this panel shows a daily token heatmap for the last six months."
                )
            )
        }
    }
}

struct UsageHeatmapCard: View {
    let trend: UsageTrend
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("最近半年用量", "Last 6 months"),
                    systemName: "calendar"
                ) {
                    InfoChip(
                        title: language.text("口径", "Source"),
                        value: sourceQualityText(trend.sourceQuality, language: language)
                    )
                }

                UsageHeatmapView(trend: trend, runtimeScope: runtimeScope, language: language)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Spacer()
                    Text(language.text("少", "Less"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatmapColor(level: level))
                            .frame(width: heatmapCellSize, height: heatmapCellSize)
                    }
                    Text(language.text("多", "More"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .help(usageSourceHelp(runtimeScope: runtimeScope, sourceQuality: trend.sourceQuality, language: language))
            }
        }
    }
}

struct UsageHeatmapView: View {
    let trend: UsageTrend
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    @State private var hoveredCell: UsageHeatmapDay?
    @State private var hoverAnchor: CGPoint = .zero

    private let cellSize: CGFloat = heatmapCellSize
    private let cellSpacing: CGFloat = usageHeatmapCellSpacing
    private let weekdayLabelWidth: CGFloat = usageHeatmapWeekdayLabelWidth

    private struct MonthMarker: Identifiable {
        let id: Int
        let columnIndex: Int
        let title: String
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            heatmapGrid
            if let hoveredCell {
                let payload = heatTooltipPayload(hoveredCell)
                ChartTooltipView(payload: payload)
                    .frame(width: chartTooltipWidth)
                    .position(chartTooltipPosition(
                        anchor: hoverAnchor,
                        containerSize: heatmapContentSize,
                        rowCount: payload.rows.count
                    ))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }
        }
        .frame(width: heatmapContentSize.width, height: heatmapContentSize.height, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var heatmapContentSize: CGSize {
        CGSize(
            width: usageHeatmapContentWidth(weekCount: trend.heatmapWeeks.count),
            height: usageHeatmapMonthLabelHeight + 5 + cellSize * 7 + cellSpacing * 6
        )
    }

    private var heatmapGrid: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: cellSpacing) {
                Text("")
                    .frame(width: weekdayLabelWidth)
                ZStack(alignment: .topLeading) {
                    ForEach(monthMarkers) { marker in
                        Text(marker.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: usageHeatmapMonthLabelWidth, alignment: .leading)
                            .offset(x: monthLabelX(for: marker.columnIndex))
                    }
                }
                .frame(width: usageHeatmapGridWidth(weekCount: trend.heatmapWeeks.count), height: usageHeatmapMonthLabelHeight, alignment: .topLeading)
                Color.clear
                    .frame(width: weekdayLabelWidth, height: usageHeatmapMonthLabelHeight)
            }

            HStack(alignment: .top, spacing: cellSpacing) {
                VStack(alignment: .trailing, spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdayLabel(index))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: weekdayLabelWidth, height: cellSize, alignment: .trailing)
                    }
                }

                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(trend.heatmapWeeks.enumerated()), id: \.offset) { weekIndex, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(Array(week.enumerated()), id: \.element.id) { dayIndex, cell in
                                if cell.isFuture {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.clear)
                                        .frame(width: cellSize, height: cellSize)
                                } else {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(heatmapColor(level: heatLevel(cell.tokens)))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .strokeBorder(
                                                    hoveredCell?.id == cell.id ? WidgetPalette.brandPrimary.opacity(0.78) : Color.clear,
                                                    lineWidth: 1
                                                )
                                        )
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            if hovering {
                                                hoveredCell = cell
                                                hoverAnchor = heatmapCellAnchor(weekIndex: weekIndex, dayIndex: dayIndex)
                                            } else if hoveredCell?.id == cell.id {
                                                hoveredCell = nil
                                            }
                                        }
                                        .accessibilityLabel(heatTooltip(cell))
                                }
                            }
                        }
                    }
                }
                Color.clear
                    .frame(width: weekdayLabelWidth, height: 1)
            }
        }
    }

    private func heatmapCellAnchor(weekIndex: Int, dayIndex: Int) -> CGPoint {
        CGPoint(
            x: weekdayLabelWidth + cellSpacing + CGFloat(weekIndex) * (cellSize + cellSpacing) + cellSize / 2,
            y: usageHeatmapMonthLabelHeight + 5 + CGFloat(dayIndex) * (cellSize + cellSpacing) + cellSize / 2
        )
    }

    private var monthMarkers: [MonthMarker] {
        trend.heatmapWeeks.enumerated().compactMap { index, week in
            let label = monthLabel(for: week)
            guard !label.isEmpty else { return nil }
            return MonthMarker(id: index, columnIndex: index, title: label)
        }
    }

    private func monthLabelX(for columnIndex: Int) -> CGFloat {
        CGFloat(columnIndex) * (cellSize + cellSpacing)
    }

    private func monthLabel(for week: [UsageHeatmapDay]) -> String {
        let calendar = Calendar.current
        guard let firstOfMonth = week.first(where: { cell in
            !cell.isFuture && calendar.component(.day, from: cell.date) == 1
        }) else { return "" }
        return monthText(firstOfMonth.date)
    }

    private func monthText(_ date: Date) -> String {
        if language.isChinese {
            switch Calendar.current.component(.month, from: date) {
            case 1: return "一月"
            case 2: return "二月"
            case 3: return "三月"
            case 4: return "四月"
            case 5: return "五月"
            case 6: return "六月"
            case 7: return "七月"
            case 8: return "八月"
            case 9: return "九月"
            case 10: return "十月"
            case 11: return "十一月"
            default: return "十二月"
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    private func weekdayLabel(_ index: Int) -> String {
        switch index {
        case 0: return language.text("一", "M")
        case 1: return language.text("二", "T")
        case 2: return language.text("三", "W")
        case 3: return language.text("四", "T")
        case 4: return language.text("五", "F")
        case 5: return language.text("六", "S")
        default: return language.text("日", "S")
        }
    }

    private func heatLevel(_ tokens: Int64) -> Int {
        guard tokens > 0 else { return 0 }
        if tokens <= trend.heatmapThresholds[0] { return 1 }
        if tokens <= trend.heatmapThresholds[1] { return 2 }
        if tokens <= trend.heatmapThresholds[2] { return 3 }
        return 4
    }

    private func heatTooltip(_ cell: UsageHeatmapDay) -> String {
        let date = fullDateText(cell.date, language: language)
        guard let usage = cell.usage, usage.tokens.visibleTotalTokens > 0 else {
            if trend.sourceQuality == .official {
                return language.text("\(date) 无官方 token 记录", "No official token records on \(date)")
            }
            return language.text("\(date) 无本机 token 记录", "No local token records on \(date)")
        }
        let cost = usage.estimatedCostUSD > 0 ? " · \(language.text("估算", "est.")) \(formatUSD(usage.estimatedCostUSD))" : ""
        return "\(date) · \(formatTokens(usage.tokens.visibleTotalTokens)) tokens\(cost)"
    }

    private func heatTooltipPayload(_ cell: UsageHeatmapDay) -> ChartTooltipPayload {
        usageTooltipPayload(
            date: cell.date,
            usage: cell.usage,
            runtimeScope: runtimeScope,
            sourceQuality: trend.sourceQuality,
            language: language
        )
    }
}

struct UsageSevenDaySummaryCard: View {
    let trend: UsageTrend
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("最近 7 日", "Last 7 days"),
                    systemName: "chart.xyaxis.line"
                ) {
                    Text(changeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(changeTint)
                        .lineLimit(1)
                }

                SevenDayLineChart(buckets: lastSevenDayBuckets, runtimeScope: runtimeScope, language: language)
                    .frame(height: 116)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatTokens(trend.summary.sevenDay.tokens.visibleTotalTokens))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(language.text("总量", "total"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(language.text("日均 \(formatTokens(trend.summary.dailyAverageTokens))", "avg \(formatTokens(trend.summary.dailyAverageTokens))"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var lastSevenDayBuckets: [UsageDayBucket] {
        Array(trend.dayBuckets.suffix(7))
    }

    private var changeText: String {
        if trend.summary.isNewActivity {
            return language.text("新增", "New")
        }
        guard let change = trend.summary.changePercent else { return "--" }
        return formatSignedPercent(change)
    }

    private var changeTint: Color {
        if trend.summary.isNewActivity { return WidgetPalette.statusSuccess }
        guard let change = trend.summary.changePercent else { return WidgetPalette.statusNeutral }
        return change >= 0 ? WidgetPalette.statusSuccess : WidgetPalette.statusWarning
    }
}

struct SevenDayLineChart: View {
    let buckets: [UsageDayBucket]
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    @State private var hoveredBucket: UsageDayBucket?
    @State private var hoverAnchor: CGPoint = .zero

    private var maxTokens: Int64 {
        max(buckets.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let points = chartPoints(size: geometry.size)
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(WidgetPalette.surfaceTrack.opacity(0.45))
                                .frame(height: 1)
                            Spacer()
                        }
                    }

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        WidgetPalette.brandSecondary,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        ZStack {
                            Circle()
                                .fill(buckets[index].tokens > 0 ? WidgetPalette.brandSecondary : WidgetPalette.surfaceTrack)
                                .frame(width: hoveredBucket?.id == buckets[index].id ? 8 : 6, height: hoveredBucket?.id == buckets[index].id ? 8 : 6)
                        }
                        .position(point)
                        .accessibilityLabel(dayTooltip(buckets[index]))
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.001))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(location: location, points: points)
                            case .ended:
                                hoveredBucket = nil
                            }
                        }

                    if let hoveredBucket {
                        let payload = dayTooltipPayload(hoveredBucket)
                        ChartTooltipView(payload: payload)
                            .frame(width: chartTooltipWidth)
                            .position(chartTooltipPosition(
                                anchor: hoverAnchor,
                                containerSize: geometry.size,
                                rowCount: payload.rows.count
                            ))
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .zIndex(10)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(buckets) { bucket in
                    Text(shortWeekdayText(bucket.date, language: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
    }

    private func chartPoints(size: CGSize) -> [CGPoint] {
        guard !buckets.isEmpty else { return [] }
        let horizontalPadding: CGFloat = 4
        let verticalPadding: CGFloat = 8
        let availableWidth = max(1, size.width - horizontalPadding * 2)
        let availableHeight = max(1, size.height - verticalPadding * 2)
        return buckets.enumerated().map { index, bucket in
            let x = horizontalPadding + availableWidth * CGFloat(index) / CGFloat(max(buckets.count - 1, 1))
            let ratio = Double(bucket.tokens) / Double(maxTokens)
            let y = verticalPadding + availableHeight * CGFloat(1 - max(0, min(1, ratio)))
            return CGPoint(x: x, y: y)
        }
    }

    private func updateHover(location: CGPoint, points: [CGPoint]) {
        guard let index = nearestPointIndex(to: location.x, points: points),
              buckets.indices.contains(index)
        else { return }
        hoveredBucket = buckets[index]
        hoverAnchor = points[index]
    }

    private func nearestPointIndex(to x: CGFloat, points: [CGPoint]) -> Int? {
        points.enumerated()
            .min { left, right in
                abs(left.element.x - x) < abs(right.element.x - x)
            }?
            .offset
    }

    private func dayTooltip(_ bucket: UsageDayBucket) -> String {
        "\(fullDateText(bucket.date, language: language)) · \(formatTokens(bucket.tokens)) tokens"
    }

    private func dayTooltipPayload(_ bucket: UsageDayBucket) -> ChartTooltipPayload {
        usageTooltipPayload(
            date: bucket.date,
            usage: bucket.usage,
            runtimeScope: runtimeScope,
            sourceQuality: bucket.sourceQuality,
            language: language
        )
    }
}

enum ProjectTimeframe: String, CaseIterable, Identifiable {
    case recent
    case all

    var id: String { rawValue }
}

struct ProjectBoardPanel: View {
    let projectBoard: ProjectBoard?
    let language: WidgetLanguage
    @State private var timeframe: ProjectTimeframe = .recent

    private var projects: [ProjectUsage] {
        switch timeframe {
        case .recent:
            return projectBoard?.recentProjects ?? []
        case .all:
            return projectBoard?.allProjects ?? []
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: dashboardGridSpacing) {
            DashboardCard {
                VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                    DashboardCardHeader(
                        title: language.text("项目用量排行", "Project ranking"),
                        systemName: "folder.fill"
                    ) {
                        Picker("", selection: $timeframe) {
                            Text(language.text("近 7 天", "7 days")).tag(ProjectTimeframe.recent)
                            Text(language.text("全部", "All")).tag(ProjectTimeframe.all)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .frame(width: 118, height: dashboardHeaderControlHeight)
                    }

                    if projects.isEmpty {
                        AnalyticsEmptyState(
                            systemName: "folder.badge.questionmark",
                            title: language.text("暂无项目记录", "No project records"),
                            detail: language.text("没有可归类的本机 Codex 项目用量。", "No local Codex project usage can be grouped yet.")
                        )
                        .frame(minHeight: 214)
                    } else {
                        ProjectUsageList(projects: Array(projects.prefix(8)), language: language)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ProjectActivityOverview(projectBoard: projectBoard, language: language)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct ProjectActivityOverview: View {
    let projectBoard: ProjectBoard?
    let language: WidgetLanguage

    private var recentProjects: [ProjectUsage] {
        projectBoard?.recentProjects ?? []
    }

    private var allProjects: [ProjectUsage] {
        projectBoard?.allProjects ?? []
    }

    private var recentTokenTotal: Int64 {
        recentProjects.reduce(0) { $0 + $1.tokens }
    }

    private var newProjectCount: Int {
        let allById = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
        return recentProjects.filter { recent in
            guard let all = allById[recent.id] else { return false }
            return all.threadCount <= recent.threadCount
        }.count
    }

    private var topOneShare: String {
        shareText(recentProjects.first?.tokens ?? 0)
    }

    private var topThreeShare: String {
        shareText(recentProjects.prefix(3).reduce(0) { $0 + $1.tokens })
    }

    private var recentActivity: [ProjectUsage] {
        recentProjects
            .sorted {
                let left = $0.lastActiveAt ?? .distantPast
                let right = $1.lastActiveAt ?? .distantPast
                if left != right { return left > right }
                return $0.tokens > $1.tokens
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("项目活动概览", "Project activity"),
                    systemName: "chart.bar.doc.horizontal.fill"
                ) {
                    InfoChip(title: language.text("近 7 天", "7 days"), value: "\(recentProjects.count)")
                        .frame(height: dashboardHeaderControlHeight)
                        .help(language.text("基于近 7 天本机 Codex 项目活动统计。", "Based on local Codex project activity in the last 7 days."))
                }

                if recentProjects.isEmpty {
                    AnalyticsEmptyState(
                        systemName: "chart.bar.doc.horizontal",
                        title: language.text("暂无项目活动", "No project activity"),
                        detail: language.text("近 7 天没有可归类的项目活动。", "No local project activity can be grouped in the last 7 days.")
                    )
                    .frame(minHeight: 214)
                } else {
                    VStack(alignment: .leading, spacing: dashboardListRowSpacing) {
                        HStack(spacing: dashboardListRowSpacing) {
                            MetricTile(
                                title: language.text("活跃项目", "Active"),
                                value: "\(recentProjects.count)",
                                tint: WidgetPalette.brandSecondary
                            )
                            MetricTile(
                                title: language.text("新增估算", "New est."),
                                value: "\(newProjectCount)",
                                tint: WidgetPalette.statusSuccess
                            )
                        }
                        HStack(spacing: dashboardListRowSpacing) {
                            MetricTile(
                                title: "Top1",
                                value: topOneShare,
                                tint: WidgetPalette.statusInfo
                            )
                            MetricTile(
                                title: "Top3",
                                value: topThreeShare,
                                tint: WidgetPalette.statusWarning
                            )
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(language.text("最近活跃", "Recent activity"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            VStack(spacing: dashboardListRowSpacing) {
                                ForEach(recentActivity) { project in
                                    ProjectActivityRow(project: project, language: language)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func shareText(_ tokens: Int64) -> String {
        guard recentTokenTotal > 0, tokens > 0 else { return "--" }
        return formatUsagePercent(Double(tokens) / Double(recentTokenTotal) * 100)
    }
}

struct ProjectActivityRow: View {
    let project: ProjectUsage
    let language: WidgetLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(WidgetPalette.brandSecondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(WidgetPalette.brandSecondary.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(projectDetail)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(formatTokens(project.tokens))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack.opacity(0.42))
        )
        .help(project.fullPath.isEmpty ? project.name : project.fullPath)
    }

    private var projectDetail: String {
        let threads = language.text("\(project.threadCount) 线程", "\(project.threadCount) threads")
        if let lastActiveAt = project.lastActiveAt {
            return "\(threads) · \(relativeTimeText(lastActiveAt, language: language))"
        }
        return threads
    }
}

struct ProjectUsageList: View {
    let projects: [ProjectUsage]
    let language: WidgetLanguage

    private var maxTokens: Int64 {
        max(projects.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: dashboardListRowSpacing) {
            ForEach(projects) { project in
                ProjectUsageRow(project: project, maxTokens: maxTokens, language: language)
            }
        }
    }
}

struct ProjectUsageRow: View {
    let project: ProjectUsage
    let maxTokens: Int64
    let language: WidgetLanguage

    private var progress: Double {
        guard maxTokens > 0 else { return 0 }
        return max(0, min(1, Double(project.tokens) / Double(maxTokens)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text(projectDetail)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTokens(project.tokens))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(projectSecondaryValue)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.brandSecondary.opacity(0.82))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack.opacity(0.42))
        )
        .help(project.fullPath.isEmpty ? project.name : project.fullPath)
    }

    private var projectDetail: String {
        let threads = language.text("\(project.threadCount) 线程", "\(project.threadCount) threads")
        if let lastActiveAt = project.lastActiveAt {
            return "\(threads) · \(relativeTimeText(lastActiveAt, language: language))"
        }
        return threads
    }

    private var projectSecondaryValue: String {
        if let estimatedCostUSD = project.estimatedCostUSD {
            return language.text("估算 \(formatUSD(estimatedCostUSD))", "est. \(formatUSD(estimatedCostUSD))")
        }
        return sourceQualityDetailText(project.sourceQuality, language: language)
    }
}

struct ToolUsageList: View {
    let toolUsages: [ToolUsage]
    let language: WidgetLanguage

    private var maxCalls: Int {
        max(toolUsages.map(\.callCount).max() ?? 0, 1)
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("工具使用 TOP20", "Tool usage TOP20"),
                    systemName: "wrench.and.screwdriver.fill"
                ) {
                    InfoChip(title: "Token", value: language.text("估算", "Est."))
                        .frame(height: dashboardHeaderControlHeight)
                        .help(language.text("调用次数为事件计数；工具 token 按 session 内调用占比估算。", "Call counts are event counts. Tool tokens are estimated from each session's call share."))
                }

                if toolUsages.isEmpty {
                    AnalyticsEmptyState(
                        systemName: "wrench.and.screwdriver",
                        title: language.text("暂无工具调用", "No tool calls"),
                        detail: language.text("没有可统计的本机工具调用事件。", "No local tool call events can be counted yet.")
                    )
                    .frame(minHeight: 214)
                } else {
                    VStack(spacing: dashboardListRowSpacing) {
                        ForEach(toolUsages) { tool in
                            ToolUsageRow(tool: tool, maxCalls: maxCalls, language: language)
                        }
                    }
                }
            }
        }
    }
}

struct ToolUsageRow: View {
    let tool: ToolUsage
    let maxCalls: Int
    let language: WidgetLanguage

    private var progress: Double {
        guard maxCalls > 0 else { return 0 }
        return max(0, min(1, Double(tool.callCount) / Double(maxCalls)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: toolCategoryIcon(tool.category))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.brandPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WidgetPalette.brandPrimary.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(localizedToolCategory(tool.category, language: language))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.text("\(tool.callCount) 次", "\(tool.callCount)x"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(tool.estimatedTokens.map { language.text("估算 \(formatTokens($0))", "est. \(formatTokens($0))") } ?? "--")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.brandPrimary.opacity(0.78))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack.opacity(0.42))
        )
        .help(toolHelpText)
    }

    private var toolHelpText: String {
        let tokenText = tool.estimatedTokens.map { formatTokens($0) } ?? "--"
        let costText = tool.estimatedCostUSD.map { formatUSD($0) } ?? "--"
        return language.text(
            "\(tool.name) · \(tool.callCount) 次 · 估算 \(tokenText) · \(costText)",
            "\(tool.name) · \(tool.callCount)x · est. \(tokenText) · \(costText)"
        )
    }
}

struct SkillUsagePanel: View {
    let skillUsages: [SkillUsage]
    let toolUsages: [ToolUsage]
    let language: WidgetLanguage

    private var topSkills: [SkillUsage] {
        Array(skillUsages.prefix(20))
    }

    private var maxLoads: Int {
        max(topSkills.map(\.loadCount).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: dashboardGridSpacing) {
            skillUsageList
                .frame(maxWidth: .infinity, alignment: .topLeading)

            ToolUsageList(toolUsages: Array(toolUsages.prefix(20)), language: language)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var skillUsageList: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("Skill 使用 TOP20", "Skill usage TOP20"),
                    systemName: "puzzlepiece.extension.fill"
                ) {
                    InfoChip(title: "Token", value: language.text("Skill.md Token数", "Skill.md tokens"))
                        .frame(height: dashboardHeaderControlHeight)
                        .help(language.text(
                            "调用次数按本地 session 中 SKILL.md 加载事件计数；Token 数来自本机 Skill.md 文件内容估算，不代表完整任务消耗。",
                            "Load counts come from local session SKILL.md load events. Token counts are estimated from the local Skill.md file content, not from the full task."
                        ))
                }

                if topSkills.isEmpty {
                    AnalyticsEmptyState(
                        systemName: "puzzlepiece.extension",
                        title: language.text("暂无 Skill 加载", "No Skill loads"),
                        detail: language.text("没有在本机 session 工具调用参数中发现 SKILL.md 加载事件。", "No SKILL.md load events were found in local session tool-call arguments.")
                    )
                    .frame(minHeight: 214)
                } else {
                    VStack(spacing: dashboardListRowSpacing) {
                        ForEach(topSkills) { skill in
                            SkillUsageRow(skill: skill, maxLoads: maxLoads, language: language)
                        }
                    }
                }
            }
        }
    }
}

struct SkillUsageRow: View {
    let skill: SkillUsage
    let maxLoads: Int
    let language: WidgetLanguage

    private var progress: Double {
        guard maxLoads > 0 else { return 0 }
        return max(0, min(1, Double(skill.loadCount) / Double(maxLoads)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.brandSecondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(WidgetPalette.brandSecondary.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(skillDetail)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.text("\(skill.loadCount) 次", "\(skill.loadCount)x"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(staticTokenText)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WidgetPalette.brandSecondary.opacity(0.78))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack.opacity(0.42))
        )
        .help(skillHelpText)
    }

    private var skillDetail: String {
        let threads = language.text("\(skill.threadCount) 线程", "\(skill.threadCount) threads")
        if let lastLoadedAt = skill.lastLoadedAt {
            return "\(skill.sourceLabel) · \(threads) · \(relativeTimeText(lastLoadedAt, language: language))"
        }
        return "\(skill.sourceLabel) · \(threads)"
    }

    private var staticTokenText: String {
        guard let tokens = skill.staticTokenEstimate else {
            return language.text("文件缺失", "missing file")
        }
        return language.text("Skill.md \(formatTokens(tokens))", "Skill.md \(formatTokens(tokens))")
    }

    private var skillHelpText: String {
        let staticTokens = skill.staticTokenEstimate.map { formatTokens($0) } ?? "--"
        let size = formatBytes(skill.staticByteCount)
        return language.text(
            "\(skill.name) · \(skill.loadCount) 次加载 · \(skill.threadCount) 线程 · Skill.md Token数 \(staticTokens) · 文件 \(size) · \(displayHomePath(skill.path))",
            "\(skill.name) · \(skill.loadCount)x loads · \(skill.threadCount) threads · Skill.md tokens \(staticTokens) · file \(size) · \(displayHomePath(skill.path))"
        )
    }
}

struct AnalyticsEmptyState: View {
    let systemName: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}

struct DashboardCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(dashboardCardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }
}

struct DashboardCardHeader<Trailing: View>: View {
    let title: String
    let systemName: String
    let trailing: Trailing

    init(
        title: String,
        systemName: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemName = systemName
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: dashboardCardHeaderSpacing) {
            Image(systemName: systemName)
                .font(.system(size: dashboardCardIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: dashboardCardIconFrame, height: dashboardCardHeaderHeight)
            Text(title)
                .font(.system(size: dashboardCardTitleSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: dashboardCardHeaderSpacing)
            trailing
        }
        .frame(height: dashboardCardHeaderHeight, alignment: .center)
    }
}

struct TaskBoardColumnView: View {
    let column: TaskColumn
    let language: WidgetLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: taskColumnIcon(column.id))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(taskAccentForegroundColor(column.id, colorScheme: colorScheme))
                Text(localizedTaskColumnTitle(column.id, language: language))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(column.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: dashboardCardHeaderHeight, alignment: .center)

            if column.items.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(language.text("暂无", "No items"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 66)
            } else {
                ForEach(column.items) { item in
                    TaskIssueCard(item: item, language: language)
                }
                if column.count > column.items.count {
                    Text(language.text("+ \(column.count - column.items.count) 项", "+ \(column.count - column.items.count) more"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.leading, 6)
                }
            }
        }
        .padding(dashboardCardPadding)
        .frame(minHeight: 274, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: dashboardCardCornerRadius, style: .continuous)
                .fill(taskColumnFill(column.id))
                .overlay(
                    RoundedRectangle(cornerRadius: dashboardCardCornerRadius, style: .continuous)
                        .strokeBorder(taskAccentColor(column.id).opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

struct TaskIssueCard: View {
    let item: TaskItem
    let language: WidgetLanguage
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            switch taskPrimaryAction(for: item) {
            case .showDetail:
                isShowingDetail = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.code)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let updatedAt = item.updatedAt {
                        Text(relativeTimeText(updatedAt, language: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.9)

                if !item.detail.isEmpty {
                    Text(localizedTaskDetail(item.detail, language: language))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 5) {
                    TaskSourceBadge(source: item.source)
                    TaskChip(text: item.chip, kind: item.kind)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(dashboardRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: dashboardRowCornerRadius, elevated: true)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingDetail) {
            TaskDetailView(item: item, language: language)
        }
    }
}

struct TaskSourceBadge: View {
    let source: RuntimeScope

    var body: some View {
        HStack(spacing: 4) {
            RuntimeLogoView(scope: source, size: 12)
            Text(source.displayName)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(WidgetPalette.surfaceTrack)
        )
    }
}

struct TaskDetailView: View {
    let item: TaskItem
    let language: WidgetLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var openErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                RuntimeLogoView(scope: item.source, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        TaskSourceBadge(source: item.source)
                        TaskChip(text: item.chip, kind: item.kind)
                    }
                    taskTimingSummary
                }
                Spacer(minLength: 8)
                if let target = item.codexNavigationTarget {
                    Button {
                        openInCodex(target)
                    } label: {
                        Label(
                            language.text("在 Codex 中打开", "Open in Codex"),
                            systemImage: "arrow.up.forward.app"
                        )
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(language.text("使用 Codex 打开此线程", "Open this thread in Codex"))
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(language.text("关闭", "Close"))
            }

            Divider()

            if let openErrorMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetPalette.statusDanger)
                    Text(openErrorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                        .fill(WidgetPalette.statusDanger.opacity(0.08))
                )
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    taskDetailSection(
                        title: language.text("任务摘要", "Task summary"),
                        systemName: "text.alignleft",
                        text: item.summary ?? language.text("暂无摘要", "No summary available")
                    )
                    taskProgressSection
                    taskDetailSection(
                        title: language.text("最近回复", "Latest reply"),
                        systemName: "bubble.left.and.bubble.right.fill",
                        text: item.recentReply ?? language.text("暂无最近回复", "No recent reply available")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: 560, minHeight: 380, maxHeight: 560, alignment: .topLeading)
    }

    private func openInCodex(_ target: TaskNavigationTarget) {
        openErrorMessage = nil
        guard let url = target.url, NSWorkspace.shared.open(url) else {
            openErrorMessage = language.text(
                "无法在 Codex 中打开此任务，请确认 Codex 已安装后重试。",
                "Could not open this task in Codex. Confirm Codex is installed, then try again."
            )
            return
        }
    }

    @ViewBuilder
    private var taskTimingSummary: some View {
        if let timing = item.timing,
           timing.createdAt != nil || timing.deadlineAt != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let createdAt = timing.createdAt {
                    Text(
                        language.text("创建：", "Created: ")
                            + taskDetailDateText(createdAt, includesTime: timing.createdHasTime, language: language)
                    )
                }
                if let deadlineAt = timing.deadlineAt {
                    Text(
                        language.text("截止：", "Due: ")
                            + taskDetailDateText(deadlineAt, includesTime: timing.deadlineHasTime, language: language)
                    )
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if let updatedAt = item.updatedAt {
            Text(
                language.text("更新：", "Updated: ")
                    + taskDetailDateText(updatedAt, includesTime: true, language: language)
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var taskProgressSection: some View {
        let percent = item.progress.map { min(max($0.percent, 0), 100) }
        let progressText = percent.map { value in
            String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
        } ?? "--"
        let note: String
        switch item.progress?.origin {
        case .explicit:
            note = language.text("来自任务记录中的真实进度", "Reported by the task record")
        case .completedStatus:
            note = language.text("依据已完成状态显示", "Shown from the completed status")
        case nil:
            note = language.text("任务记录未提供进度百分比", "No progress percentage is recorded")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(language.text("完成进度", "Progress"), systemImage: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(progressText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percent == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(taskAccentColor(item.kind)))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    if let percent {
                        Capsule(style: .continuous)
                            .fill(taskAccentColor(item.kind))
                            .frame(width: proxy.size.width * percent / 100)
                    }
                }
            }
            .frame(height: 7)
            Text(note)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(WidgetPalette.surfaceTrack.opacity(0.55))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.text("完成进度", "Progress"))
        .accessibilityValue(progressText + "，" + note)
    }

    private func taskDetailSection(title: String, systemName: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                        .fill(WidgetPalette.surfaceTrack.opacity(0.55))
                )
        }
    }
}

private func taskDetailDateText(_ date: Date, includesTime: Bool, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language == .zh
        ? Locale(identifier: "zh_CN")
        : Locale(identifier: "en_US")
    formatter.dateStyle = .long
    formatter.timeStyle = includesTime ? .short : .none
    return formatter.string(from: date)
}

struct TaskAvatar: View {
    let text: String
    let kind: TaskColumnKind
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(taskAccentForegroundColor(kind, colorScheme: colorScheme))
            .frame(width: 18, height: 18)
            .background(
                Circle()
                    .fill(taskAccentColor(kind).opacity(0.13))
            )
    }
}

struct TaskChip: View {
    let text: String
    let kind: TaskColumnKind
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chipIcon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(chipForegroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(chipAccentColor.opacity(0.13))
        )
    }

    private var chipAccentColor: Color {
        switch text.lowercased() {
        case "high", "urgent":
            return WidgetPalette.statusDanger
        case "medium":
            return WidgetPalette.statusWarning
        case "active":
            return WidgetPalette.statusWarning
        case "cron", "wake":
            return WidgetPalette.brandSecondary
        case "done":
            return WidgetPalette.statusSuccess
        default:
            return taskAccentColor(kind)
        }
    }

    private var chipForegroundColor: Color {
        guard colorScheme == .light else { return chipAccentColor }
        switch text.lowercased() {
        case "high", "urgent":
            return WidgetPalette.statusDangerLightText
        case "medium", "active":
            return WidgetPalette.statusWarningLightText
        case "cron", "wake":
            return WidgetPalette.brandSecondaryLightText
        case "done":
            return WidgetPalette.statusSuccessLightText
        default:
            return taskAccentForegroundColor(kind, colorScheme: colorScheme)
        }
    }

    private var chipIcon: String {
        switch text.lowercased() {
        case "cron", "wake":
            return "clock.fill"
        case "done":
            return "checkmark.circle.fill"
        default:
            return "chart.bar.fill"
        }
    }
}

struct InfoChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(WidgetPalette.surfaceTrack)
        )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.surfaceTrack)
        )
    }
}

struct RingRGBColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

}

enum WidgetPalette {
    static let brandPrimaryRGB = RingRGBColor(red: 0.157, green: 0.400, blue: 0.969) // #2866F7
    static let brandPrimaryStrongRGB = RingRGBColor(red: 0.122, green: 0.349, blue: 0.929) // #1F59ED
    static let brandPrimaryLightRGB = RingRGBColor(red: 0.482, green: 0.627, blue: 1.000) // #7BA0FF
    static let brandSecondaryRGB = RingRGBColor(red: 0.545, green: 0.427, blue: 1.000) // #8B6DFF
    static let brandSecondaryStrongRGB = RingRGBColor(red: 0.427, green: 0.271, blue: 0.910) // #6D45E8
    static let brandHighlightRGB = RingRGBColor(red: 0.855, green: 0.639, blue: 0.980) // #DAA3FA

    static let brandPrimary = brandPrimaryRGB.color
    static let brandPrimaryStrong = brandPrimaryStrongRGB.color
    static let brandPrimaryLight = brandPrimaryLightRGB.color
    static let brandSecondary = brandSecondaryRGB.color
    static let brandSecondaryStrong = brandSecondaryStrongRGB.color
    static let brandHighlight = brandHighlightRGB.color
    static let dataFlowParticle = NSColor.white

    static let statusSuccess = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let statusInfo = Color(red: 0.039, green: 0.518, blue: 1.000) // #0A84FF
    static let statusWarning = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let statusDanger = Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A
    static let statusNeutral = Color(red: 0.596, green: 0.596, blue: 0.616) // #98989D
    static let dataReasoning = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2

    // Strong semantic foregrounds keep 9 pt labels readable on light glass.
    static let statusDangerLightText = Color(red: 0.706, green: 0.137, blue: 0.094) // #B42318
    static let statusWarningLightText = Color(red: 0.502, green: 0.294, blue: 0.000) // #804B00
    static let statusSuccessLightText = Color(red: 0.078, green: 0.439, blue: 0.224) // #147039
    static let brandSecondaryLightText = Color(red: 0.384, green: 0.251, blue: 0.773) // #6240C5
    static let statusNeutralLightText = Color(red: 0.329, green: 0.333, blue: 0.369) // #54555E

    static let surfaceTrack = Color.primary.opacity(0.10)
    static let dataZero = statusNeutral.opacity(0.35)

    static func windowScrim(_ colorScheme: ColorScheme, reduceTransparency: Bool = false) -> Color {
        if reduceTransparency {
            return Color(nsColor: .windowBackgroundColor).opacity(0.94)
        }
        return colorScheme == .dark ? Color.black.opacity(0.080) : Color.white.opacity(0.100)
    }

    static func sectionFill(_ colorScheme: ColorScheme, reduceTransparency: Bool = false) -> Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor).opacity(0.96)
        }
        return colorScheme == .dark ? Color.black.opacity(0.060) : Color.white.opacity(0.360)
    }

    static func sectionStroke(_ colorScheme: ColorScheme, increasedContrast: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(increasedContrast ? 0.240 : 0.120)
        }
        return Color.black.opacity(increasedContrast ? 0.180 : 0.080)
    }

    static func cardFill(
        _ colorScheme: ColorScheme,
        elevated: Bool = false,
        reduceTransparency: Bool = false
    ) -> Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor).opacity(elevated ? 1.0 : 0.96)
        }
        if colorScheme == .dark {
            return Color.white.opacity(elevated ? 0.110 : 0.080)
        }
        return Color.white.opacity(elevated ? 0.680 : 0.520)
    }

    static func cardStroke(
        _ colorScheme: ColorScheme,
        elevated: Bool = false,
        increasedContrast: Bool = false
    ) -> Color {
        if colorScheme == .dark {
            let base = elevated ? 0.140 : 0.100
            return Color.white.opacity(increasedContrast ? base + 0.100 : base)
        }
        let base = elevated ? 0.100 : 0.070
        return Color.black.opacity(increasedContrast ? base + 0.100 : base)
    }

    static func secondaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.720) : Color.black.opacity(0.660)
    }

    static func tertiaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.560) : Color.black.opacity(0.560)
    }

    static func controlFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.085) : Color.white.opacity(0.520)
    }

    static func controlSelectedFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.180) : Color.black.opacity(0.105)
    }

    static func controlStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.070) : Color.black.opacity(0.050)
    }

    static func statusDangerFill(_ colorScheme: ColorScheme) -> Color {
        statusDanger.opacity(colorScheme == .dark ? 0.14 : 0.08)
    }

    static func statusDangerStroke(_ colorScheme: ColorScheme) -> Color {
        statusDanger.opacity(colorScheme == .dark ? 0.34 : 0.24)
    }
}

private let quotaPrimaryStartColor = WidgetPalette.brandPrimaryLightRGB
private let quotaPrimaryEndColor = WidgetPalette.brandPrimaryRGB
private let quotaPrimaryColor = quotaPrimaryEndColor.color
private let quotaPrimaryTrackColor = WidgetPalette.surfaceTrack
private let quotaSecondaryStartColor = WidgetPalette.brandHighlightRGB
private let quotaSecondaryEndColor = WidgetPalette.brandSecondaryRGB
private let quotaSecondaryColor = quotaSecondaryEndColor.color
private let quotaSecondaryTrackColor = WidgetPalette.surfaceTrack
private let uncachedInputColor = WidgetPalette.statusInfo
private let cachedInputColor = WidgetPalette.brandSecondary
private let outputTokenColor = WidgetPalette.statusWarning
private let dashboardGridSpacing: CGFloat = 10
private let dashboardCardPadding: CGFloat = 10
private let dashboardCardCornerRadius: CGFloat = 10
private let dashboardCardHeaderHeight: CGFloat = 28
private let dashboardCardHeaderSpacing: CGFloat = 8
private let dashboardCardContentSpacing: CGFloat = 8
private let dashboardHeaderControlHeight: CGFloat = 24
let titlebarControlHeight: CGFloat = 18
private let dashboardTabSegmentWidth: CGFloat = 96
private let dashboardTabIconWidth: CGFloat = 14
private let dashboardTabHorizontalPadding: CGFloat = 10
private let dashboardCardIconSize: CGFloat = 12
private let dashboardCardIconFrame: CGFloat = 18
private let dashboardCardTitleSize: CGFloat = 11
private let dashboardListRowSpacing: CGFloat = 6
private let dashboardRowPadding: CGFloat = 7
private let dashboardRowCornerRadius: CGFloat = 8
private let settingsAccessoryColumnWidth: CGFloat = 220
private let settingsControlCornerRadius: CGFloat = 8
private let settingsSegmentHeight: CGFloat = 30
private let settingsSwitchWidth: CGFloat = 56
private let settingsShortcutControlSpacing: CGFloat = 8
private let settingsShortcutRecorderWidth: CGFloat = 132
private let usageTrendCardHeight: CGFloat = 214
private let usageTrendCardSpacing: CGFloat = dashboardGridSpacing
private let usageSevenDayMinimumCardWidth: CGFloat = 260
private let usageHeatmapCellSpacing: CGFloat = 4
private let usageHeatmapWeekdayLabelWidth: CGFloat = 20
private let usageHeatmapMonthLabelWidth: CGFloat = 42
private let usageHeatmapMonthLabelHeight: CGFloat = 16
private let heatmapCellSize: CGFloat = 10
private let chartTooltipWidth: CGFloat = 188

func runtimeStatusPopoverHeight(for runtimeCount: Int) -> CGFloat {
    runtimeCount <= 1 ? 352 : 478
}

private func chartTooltipPosition(anchor: CGPoint, containerSize: CGSize, rowCount: Int) -> CGPoint {
    let tooltipHeight = CGFloat(38 + rowCount * 17)
    let margin: CGFloat = 8
    let x = min(
        max(anchor.x, chartTooltipWidth / 2 + margin),
        max(chartTooltipWidth / 2 + margin, containerSize.width - chartTooltipWidth / 2 - margin)
    )
    let showBelow = anchor.y < tooltipHeight + margin * 2
    let rawY = showBelow
        ? anchor.y + tooltipHeight / 2 + margin
        : anchor.y - tooltipHeight / 2 - margin
    let y = min(
        max(rawY, tooltipHeight / 2 + margin),
        max(tooltipHeight / 2 + margin, containerSize.height - tooltipHeight / 2 - margin)
    )
    return CGPoint(x: x, y: y)
}

private func usageHeatmapGridWidth(weekCount: Int) -> CGFloat {
    guard weekCount > 0 else { return 0 }
    return CGFloat(weekCount) * heatmapCellSize + CGFloat(max(weekCount - 1, 0)) * usageHeatmapCellSpacing
}

private func usageHeatmapContentWidth(weekCount: Int) -> CGFloat {
    usageHeatmapWeekdayLabelWidth
        + usageHeatmapCellSpacing
        + usageHeatmapGridWidth(weekCount: weekCount)
        + usageHeatmapCellSpacing
        + usageHeatmapWeekdayLabelWidth
}

private func usageHeatmapPreferredCardWidth(weekCount: Int) -> CGFloat {
    usageHeatmapContentWidth(weekCount: weekCount) + dashboardCardPadding * 2
}

private func usageTrendHeatmapCardWidth(containerWidth: CGFloat, weekCount: Int) -> CGFloat {
    let availableWidth = max(0, containerWidth - usageTrendCardSpacing)
    let preferredWidth = usageHeatmapPreferredCardWidth(weekCount: weekCount)
    guard availableWidth > preferredWidth + usageSevenDayMinimumCardWidth else {
        return min(preferredWidth, max(0, availableWidth * 0.58))
    }
    return preferredWidth
}

private func usageTrendSevenDayCardWidth(containerWidth: CGFloat, weekCount: Int) -> CGFloat {
    max(
        0,
        containerWidth - usageTrendCardSpacing - usageTrendHeatmapCardWidth(
            containerWidth: containerWidth,
            weekCount: weekCount
        )
    )
}

private func localizedDashboardTitle(_ tab: DashboardTab, language: WidgetLanguage) -> String {
    switch tab {
    case .tasks:
        return language.text("今日任务看板", "Today's task board")
    case .usage:
        return language.text("用量趋势", "Usage trend")
    case .projects:
        return language.text("项目排行", "Project ranking")
    case .skills:
        return language.text("Skill 使用", "Skill usage")
    }
}

private func localizedDashboardTabLabel(_ tab: DashboardTab, language: WidgetLanguage) -> String {
    switch tab {
    case .tasks:
        return language.text("今日任务", "Today")
    case .usage:
        return language.text("用量趋势", "Usage")
    case .projects:
        return language.text("项目排行", "Projects")
    case .skills:
        return "Skill"
    }
}

private func dashboardTabIcon(_ tab: DashboardTab) -> String {
    switch tab {
    case .tasks:
        return "checklist"
    case .usage:
        return "calendar"
    case .projects:
        return "folder"
    case .skills:
        return "puzzlepiece.extension"
    }
}

private func heatmapColor(level: Int) -> Color {
    switch level {
    case 0:
        return WidgetPalette.surfaceTrack
    case 1:
        return WidgetPalette.brandSecondary.opacity(0.28)
    case 2:
        return WidgetPalette.brandSecondary.opacity(0.46)
    case 3:
        return WidgetPalette.brandSecondary.opacity(0.70)
    default:
        return WidgetPalette.brandSecondary.opacity(0.96)
    }
}

private func sourceQualityText(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .official:
        return language.text("官方", "Official")
    case .detailed:
        return language.text("精细", "Detailed")
    case .approximate:
        return language.text("粗略", "Approx.")
    }
}

private func sourceQualityDetailText(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .official:
        return language.text("Codex App 服务端", "Codex App server")
    case .detailed:
        return language.text("事件口径", "Event source")
    case .approximate:
        return language.text("线程口径", "Thread source")
    }
}

private func usageSourceTooltip(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .official:
        return language.text("来自 account/usage/read", "From account/usage/read")
    case .detailed:
        return language.text("来自 token_count", "From token_count")
    case .approximate:
        return language.text("按线程更新时间", "By thread time")
    }
}

private func usageSourceHelp(
    runtimeScope: RuntimeScope,
    sourceQuality: UsageSourceQuality,
    language: WidgetLanguage
) -> String {
    if runtimeScope == .codex, sourceQuality == .official {
        return language.text(
            "来自 Codex App account/usage/read，与个人资料 token 活动使用同一服务端日桶。",
            "From Codex App account/usage/read, using the same server-side daily buckets as Profile token activity."
        )
    }
    switch runtimeScope {
    case .codex:
        return language.text(
            "使用本机 Codex session token_count 事件估算；缺失时回退到本机线程更新时间统计。API 等效价值为估算，不代表官方账单。",
            "Estimated from local Codex session token_count events. Falls back to thread updated_at when detailed events are unavailable. API-equivalent value is an estimate, not an official bill."
        )
    case .openClaw:
        return language.text(
            "使用本机 OpenClaw main-agent transcript 的 assistant message.usage；明确的 Codex-backed 记录会排除。",
            "Uses assistant message.usage from local OpenClaw main-agent transcripts; explicit Codex-backed records are excluded."
        )
    case .claudeCode:
        return language.text(
            "使用本机 Claude Code transcript usage 事件；未选中 Claude Code 时不会扫描 ~/.claude。",
            "Uses local Claude Code transcript usage events; ~/.claude is not scanned when Claude Code is not selected."
        )
    case .hermes:
        return language.text(
            "使用 Hermes 默认 profile state.db 的 session token 汇总；自然日趋势按最后活跃时间近似归桶。",
            "Uses session token totals from the Hermes default-profile state.db; calendar-day trends are approximated from last activity time."
        )
    }
}

private func fullDateText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = language.isChinese ? "M月d日 EEEE" : "MMM d, EEEE"
    return formatter.string(from: date)
}

private func shortWeekdayText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = language.isChinese ? "E" : "EEE"
    return formatter.string(from: date)
}

private func localDayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func formatTokens(_ value: Int64?) -> String {
    TokenFormatter.format(value)
}

private func formatBytes(_ value: Int64?) -> String {
    guard let value else { return "--" }
    let absValue = abs(Double(value))
    if absValue >= 1_000_000 {
        return String(format: "%.1fMB", Double(value) / 1_000_000)
    }
    if absValue >= 1_000 {
        return String(format: "%.1fKB", Double(value) / 1_000)
    }
    return "\(value)B"
}

private func formatUSD(_ value: Double?) -> String {
    guard let value else { return "--" }
    let absValue = abs(value)
    if absValue >= 1_000 {
        return String(format: "$%.0f", value)
    }
    return String(format: "$%.2f", value)
}

private func formatCompactUSD(_ value: Double?) -> String {
    guard let value else { return "--" }
    let absValue = abs(value)
    if absValue >= 1_000_000 {
        return String(format: "$%.1fM", value / 1_000_000)
    }
    if absValue >= 10_000 {
        return String(format: "$%.1fK", value / 1_000)
    }
    if absValue >= 1_000 {
        return String(format: "$%.0f", value)
    }
    return String(format: "$%.0f", value)
}

private func formatUSDPerMillion(_ value: Double) -> String {
    String(format: "$%.2f/M", value)
}

private func formatUsagePercent(_ value: Double) -> String {
    if value > 0, value < 1 {
        return "<1%"
    }
    return "\(Int(value.rounded()))%"
}

private func formatSignedPercent(_ value: Double) -> String {
    if value > 0, value < 1 {
        return "+<1%"
    }
    if value < 0, value > -1 {
        return "-<1%"
    }
    return String(format: "%+.0f%%", value)
}

private func toolCategory(for name: String) -> String {
    let normalized = name.lowercased()
    if normalized.contains("exec") || normalized.contains("shell") || normalized.contains("stdin") {
        return "terminal"
    }
    if normalized.contains("patch") || normalized.contains("edit") {
        return "edit"
    }
    if normalized.contains("web") || normalized.contains("browser") || normalized.contains("page") || normalized.contains("click") || normalized.contains("screenshot") || normalized.contains("snapshot") {
        return "browser"
    }
    if normalized.contains("image") || normalized.contains("figma") {
        return "visual"
    }
    if normalized.contains("docs") || normalized.contains("library") || normalized.contains("mcp") || normalized.contains("resource") {
        return "docs"
    }
    if normalized.contains("plan") || normalized.contains("goal") {
        return "planning"
    }
    return "tool"
}

private func toolCategoryIcon(_ category: String) -> String {
    switch category {
    case "terminal":
        return "terminal"
    case "edit":
        return "pencil.and.outline"
    case "browser":
        return "globe"
    case "visual":
        return "photo"
    case "docs":
        return "doc.text.magnifyingglass"
    case "planning":
        return "checklist"
    default:
        return "wrench"
    }
}

private func localizedToolCategory(_ category: String, language: WidgetLanguage) -> String {
    switch category {
    case "terminal":
        return language.text("终端", "Terminal")
    case "edit":
        return language.text("代码编辑", "Edit")
    case "browser":
        return language.text("浏览/检索", "Browser/Web")
    case "visual":
        return language.text("视觉", "Visual")
    case "docs":
        return language.text("文档/MCP", "Docs/MCP")
    case "planning":
        return language.text("计划", "Planning")
    default:
        return language.text("工具", "Tool")
    }
}

private func taskAccentColor(_ kind: TaskColumnKind) -> Color {
    switch kind {
    case .active:
        return WidgetPalette.statusWarning
    case .pending:
        return WidgetPalette.statusNeutral
    case .scheduled:
        return WidgetPalette.brandSecondary
    case .done:
        return WidgetPalette.statusSuccess
    }
}

private func taskAccentForegroundColor(_ kind: TaskColumnKind, colorScheme: ColorScheme) -> Color {
    guard colorScheme == .light else { return taskAccentColor(kind) }
    switch kind {
    case .active:
        return WidgetPalette.statusWarningLightText
    case .pending:
        return WidgetPalette.statusNeutralLightText
    case .scheduled:
        return WidgetPalette.brandSecondaryLightText
    case .done:
        return WidgetPalette.statusSuccessLightText
    }
}

private func taskColumnFill(_ kind: TaskColumnKind) -> Color {
    taskAccentColor(kind).opacity(0.065)
}

private func taskColumnIcon(_ kind: TaskColumnKind) -> String {
    switch kind {
    case .active:
        return "record.circle"
    case .pending:
        return "circle"
    case .scheduled:
        return "clock"
    case .done:
        return "checkmark.circle.fill"
    }
}

private func localizedTaskColumnTitle(_ kind: TaskColumnKind, language: WidgetLanguage) -> String {
    switch kind {
    case .active:
        return language.text("进行中", "Active")
    case .pending:
        return language.text("待处理", "Pending")
    case .scheduled:
        return language.text("定时", "Scheduled")
    case .done:
        return language.text("完成", "Done")
    }
}

private func localizedDayLabel(_ label: String, language: WidgetLanguage) -> String {
    if label == "今天" {
        return language.text("今天", "Today")
    }
    return label
}

private func localizedTaskDetail(_ detail: String, language: WidgetLanguage) -> String {
    guard !language.isChinese else { return detail }
    return detail
        .replacingOccurrences(of: "每天", with: "Daily")
        .replacingOccurrences(of: "每周", with: "Weekly")
        .replacingOccurrences(of: "每小时", with: "Hourly")
}

private func localizedReaderMessage(_ message: String, language: WidgetLanguage) -> String {
    guard !language.isChinese else { return message }
    if message == "正在读取 codexU 数据" { return "Reading codexU data" }
    if message.contains("未找到 codex") { return "Codex executable not found" }
    if message.contains("app-server 启动失败") { return "Failed to start app-server" }
    if message.contains("app-server 响应超时") { return "app-server response timed out" }
    if message.contains("未找到 Codex state_5.sqlite") { return "Codex state_5.sqlite not found" }
    if message.contains("未找到 sqlite3") { return "sqlite3 not found" }
    if message.contains("SQLite 查询失败") { return "SQLite query failed" }
    if message.contains("未找到 Codex session 日志") { return "Codex session logs not found" }
    if message.contains("未找到 Codex token_count 事件") { return "Codex token_count events not found" }
    if message.contains("任务看板未找到 SQLite 数据源") { return "Task board SQLite data source not found" }
    if message.contains("未找到 ~/.openclaw") { return "OpenClaw local session directory not found" }
    if message.contains("OpenClaw transcript 中未找到 usage 事件") { return "No usage events found in OpenClaw transcripts" }
    if message.contains("未找到 ~/.claude/projects") { return "Claude Code local projects directory not found" }
    if message.contains("未找到 Claude Code transcript JSONL") { return "No Claude Code transcript files found" }
    if message.contains("暂无 Claude Code 本机用量记录") { return "No local Claude Code usage records yet" }
    if message.contains("未找到 ~/.hermes/state.db") { return "Hermes default-profile state.db not found" }
    if message.contains("Hermes state.db sessions schema 不受支持") { return "Unsupported Hermes sessions schema" }
    if message.contains("Hermes state.db 暂无会话记录") { return "No Hermes sessions found in state.db" }
    if message.contains("暂无 Hermes 默认 profile 本机用量记录") { return "No local Hermes default-profile usage records yet" }
    if message.contains("Hermes 中 Codex-backed 会话已从 Hermes token 统计排除") {
        return "Codex-backed Hermes sessions were excluded from Hermes token totals"
    }
    if message.contains("Hermes 自然日趋势按会话最后活跃时间近似归桶") {
        return "Hermes calendar-day trends are approximated from each session's last activity time"
    }
    if message.contains("额度响应缺少窗口字段") {
        return "Codex quota response is missing window fields, so it was not treated as having no active limits"
    }
    if message.contains("额度窗口格式无法解析") {
        return "Codex quota window could not be parsed, so it was not treated as having no active limits"
    }
    if message.contains("重复的 5 小时额度窗口") { return "Codex returned duplicate 5-hour quota windows, so that quota is hidden" }
    if message.contains("重复的 7 天额度窗口") { return "Codex returned duplicate 7-day quota windows, so that quota is hidden" }
    if message.contains("缺少时长的额度窗口") { return "Codex returned a quota window without a duration, so it was not labeled as 5h or 7d" }
    if message.contains("未识别的额度窗口") {
        return message
            .replacingOccurrences(
                of: "Codex 返回了未识别的额度窗口（",
                with: "Codex returned an unknown quota window ("
            )
            .replacingOccurrences(
                of: " 分钟），未将其标注为 5 小时或 7 天",
                with: " minutes), so it was not labeled as 5h or 7d"
            )
    }
    if message.contains("app-server") { return message.replacingOccurrences(of: "未知错误", with: "Unknown error") }
    return message
}

private func taskAvatarText(_ item: TaskItem) -> String {
    if item.code.hasPrefix("AUTO") { return "B" }
    let source = item.detail.split(separator: "·").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let first = source.first {
        return String(first).uppercased()
    }
    return "C"
}

private func timeOnly(_ date: Date, language: WidgetLanguage = .zh) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func resetDateTime(_ date: Date, language: WidgetLanguage = .zh) -> String {
    if Calendar.current.isDateInToday(date) {
        return timeOnly(date, language: language)
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
}

private func isoString(_ date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: date)
}

private func jsonValue<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

private func jsonObject(_ usage: PricedTokenUsage) -> [String: Any] {
    [
        "estimatedCostUSD": usage.estimatedCostUSD,
        "tokens": [
            "inputTokens": usage.tokens.inputTokens,
            "cachedInputTokens": usage.tokens.billableCachedInputTokens,
            "uncachedInputTokens": usage.tokens.uncachedInputTokens,
            "outputTokens": usage.tokens.outputTokens,
            "reasoningOutputTokens": usage.tokens.reasoningOutputTokens,
            "totalTokens": usage.tokens.visibleTotalTokens
        ] as [String: Any]
    ]
}

private func jsonObject(_ project: ProjectUsage) -> [String: Any] {
    [
        "name": project.name,
        "fullPath": project.fullPath,
        "tokens": project.tokens,
        "estimatedCostUSD": jsonValue(project.estimatedCostUSD),
        "threadCount": project.threadCount,
        "lastActiveAt": jsonValue(isoString(project.lastActiveAt)),
        "sourceQuality": project.sourceQuality.rawValue
    ] as [String: Any]
}

private func jsonObject(_ tool: ToolUsage) -> [String: Any] {
    [
        "name": tool.name,
        "category": tool.category,
        "callCount": tool.callCount,
        "estimatedTokens": jsonValue(tool.estimatedTokens),
        "estimatedCostUSD": jsonValue(tool.estimatedCostUSD)
    ] as [String: Any]
}

private func jsonObject(_ skill: SkillUsage) -> [String: Any] {
    [
        "name": skill.name,
        "path": skill.path,
        "sourceLabel": skill.sourceLabel,
        "loadCount": skill.loadCount,
        "threadCount": skill.threadCount,
        "staticTokenEstimate": jsonValue(skill.staticTokenEstimate),
        "staticByteCount": jsonValue(skill.staticByteCount),
        "lastLoadedAt": jsonValue(isoString(skill.lastLoadedAt))
    ] as [String: Any]
}

private func dumpJSON(_ snapshot: UsageSnapshot) {
    var object: [String: Any] = [
        "refreshedAt": isoString(snapshot.refreshedAt) ?? "",
        "messages": snapshot.messages
    ]

    if let account = snapshot.account {
        object["account"] = [
            "type": account.type,
            "planType": jsonValue(account.planType),
            "emailPresent": account.emailPresent
        ] as [String: Any]
    }

    if let primary = snapshot.fiveHourQuota {
        object["primary"] = [
            "usedPercent": primary.usedPercent,
            "remainingPercent": primary.remainingPercent,
            "windowDurationMins": jsonValue(primary.windowDurationMins),
            "resetsAt": jsonValue(isoString(primary.resetsAt))
        ] as [String: Any]
    }

    if let secondary = snapshot.sevenDayQuota {
        object["secondary"] = [
            "usedPercent": secondary.usedPercent,
            "remainingPercent": secondary.remainingPercent,
            "windowDurationMins": jsonValue(secondary.windowDurationMins),
            "resetsAt": jsonValue(isoString(secondary.resetsAt))
        ] as [String: Any]
    }

    if let credits = snapshot.credits {
        object["credits"] = [
            "hasCredits": credits.hasCredits,
            "unlimited": credits.unlimited,
            "balance": jsonValue(credits.balance),
            "resetCredits": jsonValue(credits.resetCredits)
        ] as [String: Any]
    }

    if let cloudLifetimeTokens = snapshot.cloudLifetimeTokens {
        object["cloudLifetimeTokens"] = cloudLifetimeTokens
    }

    if let cloudUsageTrend = snapshot.cloudUsageTrend {
        object["cloudUsageTrend"] = [
            "sourceQuality": cloudUsageTrend.sourceQuality.rawValue,
            "activeDayCount": cloudUsageTrend.activeDayCount,
            "sevenDayTokens": cloudUsageTrend.summary.sevenDay.tokens.visibleTotalTokens,
            "latestBucket": cloudUsageTrend.dayBuckets.last(where: { $0.tokens > 0 }).map { bucket in
                ["day": bucket.id, "tokens": bucket.tokens] as [String: Any]
            } ?? NSNull(),
            "dailyBuckets": cloudUsageTrend.dayBuckets.filter { $0.tokens > 0 }.map { bucket in
                ["day": bucket.id, "tokens": bucket.tokens] as [String: Any]
            }
        ] as [String: Any]
    }

    if let local = snapshot.local {
        var localObject: [String: Any] = [
            "todayTokens": local.todayTokens,
            "sevenDayTokens": local.sevenDayTokens,
            "lifetimeTokens": local.lifetimeTokens,
            "threadCount": local.threadCount,
            "lastUpdatedAt": jsonValue(isoString(local.lastUpdatedAt)),
            "dailyBuckets": local.dailyBuckets.map { bucket in
                [
                    "day": bucket.id,
                    "label": bucket.label,
                    "tokens": bucket.tokens
                ] as [String: Any]
            }
        ]

        if let detailed = local.detailedUsage {
            localObject["detailedUsage"] = [
                "today": jsonObject(detailed.today),
                "sevenDay": jsonObject(detailed.sevenDay),
                "month": jsonObject(detailed.month),
                "lifetime": jsonObject(detailed.lifetime),
                "parsedFileCount": detailed.parsedFileCount,
                "tokenEventCount": detailed.tokenEventCount
            ] as [String: Any]
        }

        if let trend = local.usageTrend {
            localObject["usageTrend"] = [
                "sourceQuality": trend.sourceQuality.rawValue,
                "dayCount": trend.dayBuckets.count,
                "activeDayCount": trend.activeDayCount,
                "sevenDay": jsonObject(trend.summary.sevenDay),
                "dailyAverageTokens": trend.summary.dailyAverageTokens,
                "peakDay": trend.summary.peakDay.map { bucket in
                    [
                        "day": bucket.id,
                        "tokens": bucket.tokens,
                        "estimatedCostUSD": bucket.usage.estimatedCostUSD
                    ] as [String: Any]
                } ?? NSNull(),
                "changePercent": jsonValue(trend.summary.changePercent),
                "isNewActivity": trend.summary.isNewActivity,
                "month": jsonObject(trend.month),
                "projectedMonthCostUSD": jsonValue(trend.projectedMonthCostUSD)
            ] as [String: Any]
        }

        if let projectBoard = local.projectBoard {
            localObject["projectBoard"] = [
                "recentProjects": projectBoard.recentProjects.prefix(8).map { jsonObject($0) },
                "allProjects": projectBoard.allProjects.prefix(8).map { jsonObject($0) }
            ] as [String: Any]
        }

        localObject["toolUsages"] = local.toolUsages.prefix(20).map { jsonObject($0) }
        localObject["skillUsages"] = local.skillUsages.prefix(20).map { jsonObject($0) }

        object["local"] = localObject
    }

    if let taskBoard = snapshot.taskBoard {
        object["taskBoard"] = [
            "refreshedAt": isoString(taskBoard.refreshedAt) ?? "",
            "totalCount": taskBoard.totalCount,
            "columns": taskBoard.columns.map { column in
                [
                    "id": column.id.rawValue,
                    "title": column.title,
                    "count": column.count,
                    "items": column.items.map { item in
                        [
                            "id": item.id,
                            "code": item.code,
                            "title": item.title,
                            "detail": item.detail,
                            "chip": item.chip,
                            "source": item.source.runtimeId,
                            "hasSummary": item.summary != nil,
                            "hasRecentReply": item.recentReply != nil,
                            "hasNavigationTarget": item.codexNavigationTarget != nil,
                            "createdAt": jsonValue(isoString(item.timing?.createdAt)),
                            "createdHasTime": item.timing?.createdHasTime ?? false,
                            "deadlineAt": jsonValue(isoString(item.timing?.deadlineAt)),
                            "deadlineHasTime": item.timing?.deadlineHasTime ?? false,
                            "progressPercent": jsonValue(item.progress?.percent),
                            "progressOrigin": jsonValue(item.progress?.origin.rawValue),
                            "updatedAt": jsonValue(isoString(item.updatedAt)),
                            "tokens": jsonValue(item.tokens)
                        ] as [String: Any]
                    }
                ] as [String: Any]
            }
        ] as [String: Any]
    }

    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { result, byte in
        (result << 8) + OSType(byte)
    }
}

private func debugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["CODEX_USAGE_WIDGET_DEBUG"] == "1" else { return }

    let formatter = ISO8601DateFormatter()
    let line = "\(formatter.string(from: Date())) \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/codexu.log")

    guard let data = line.data(using: .utf8) else { return }

    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

private func firstExecutablePath(_ paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class GlassHostingContainer<Content: View>: NSView {
    private let cornerRadius: CGFloat

    init(rootView: Content, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius

        let host = DraggableHostingView(rootView: rootView)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.tintColor = nil
            glass.contentView = host
            addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.autoresizingMask = [.width, .height]
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.wantsLayer = true
            material.layer?.cornerRadius = cornerRadius
            material.layer?.masksToBounds = true
            material.addSubview(host)
            addSubview(material)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

final class MainAppWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "codexU"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.fullScreenAuxiliary]
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let store = UsageStore()
    private let settings = AppSettings()
    private lazy var updateStore = AppUpdateStore(settings: settings)
    private var window: MainAppWindow?
    private var settingsWindow: NSWindow?
    private var titlebarToolbarController: NSTitlebarAccessoryViewController?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var statusPopoverEventMonitors: [Any] = []
    private var statusItemAppearanceObservation: NSKeyValueObservation?
    private var activeSpaceObserver: NSObjectProtocol?
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?
    private var cancellables = Set<AnyCancellable>()
    private let statusItemPresentationBuilder = StatusItemPresentationBuilder()
    private let statusItemRenderer = StatusItemRenderer()
    private var lastRenderedStatusItemPresentation: StatusItemPresentation?
    private var lastRenderedStatusItemAppearanceName: NSAppearance.Name?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        settings.themeMode.applyAppearance()
        setupMainMenu()
        debugLog("app launched bundle=\(Bundle.main.bundlePath)")

        createMainWindow()
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTaskBoardPollingActivity()
        }
        setupStatusItemIfNeeded()
        observeStatusItemUsage()
        observeSettings()
        settings.globalShortcutRegistration = { [weak self] shortcut in
            self?.replaceGlobalHotKey(with: shortcut) ?? .failure(.failed)
        }
        settings.globalShortcutUnregistration = { [weak self] in
            self?.unregisterGlobalHotKeyReference() ?? .failure(.failed)
        }
        if let shortcut = settings.globalShortcut,
           !registerGlobalHotKey(shortcut) {
            let defaultRegistered = shortcut == .default
                ? false
                : registerGlobalHotKey(.default)
            settings.handleInitialGlobalShortcutFailure(defaultRegistered: defaultRegistered)
        } else if settings.globalShortcut == nil {
            _ = installGlobalHotKeyHandler()
        }
        store.updateVisibleRuntimeScopes(settings.visibleRuntimeScopes)
        store.start()
        updateStore.startAutomaticCheck()
        if CommandLine.arguments.contains("--show-status-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.toggleStatusPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.statusPopover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                    self?.window?.orderOut(nil)
                }
            }
        }
    }

    private func createMainWindow() {
        let width = UsageWidgetView.widgetWidth
        let height = UsageWidgetView.widgetDefaultHeight
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: max(screenFrame.minX + 16, screenFrame.maxX - width - 28),
            y: max(screenFrame.minY + 16, screenFrame.maxY - height - 36)
        )

        let mainWindow = MainAppWindow(contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)))
        mainWindow.delegate = self
        mainWindow.minSize = CGSize(width: UsageWidgetView.widgetWidth, height: UsageWidgetView.widgetMinHeight)
        mainWindow.maxSize = CGSize(width: UsageWidgetView.widgetWidth, height: UsageWidgetView.widgetMaxHeight)
        mainWindow.contentMinSize = mainWindow.minSize
        mainWindow.contentMaxSize = mainWindow.maxSize
        mainWindow.contentView = GlassHostingContainer(
            rootView: UsageWidgetView(
                store: store,
                settings: settings,
                updateStore: updateStore
            ),
            cornerRadius: UsageWidgetView.windowCornerRadius
        )
        installTitlebarToolbar(on: mainWindow)
        window = mainWindow
        applyMainWindowLevel()
        showMainWindow()
    }

    private func installTitlebarToolbar(on window: NSWindow) {
        let toolbarView = NSHostingView(
            rootView: TitlebarToolbarView(
                store: store,
                settings: settings,
                onOpenSettings: { [weak self] in
                    self?.openSettingsWindow()
                }
            )
        )
        toolbarView.frame = NSRect(x: 0, y: 0, width: UsageWidgetView.widgetWidth - 24, height: 44)

        let controller = NSTitlebarAccessoryViewController()
        controller.layoutAttribute = .right
        controller.view = toolbarView
        window.addTitlebarAccessoryViewController(controller)
        titlebarToolbarController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeStatusPopover()
        statusItemAppearanceObservation = nil
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
        unregisterGlobalHotKey()
        store.stop()
    }

    func toggleMainWindow() {
        guard let window else { return }

        if window.isVisible, !window.isMiniaturized, window.isKeyWindow {
            window.orderOut(nil)
            updateTaskBoardPollingActivity()
            return
        }

        showMainWindow()
    }

    func applicationDidResignActive(_ notification: Notification) {
        closeStatusPopover()
        updateTaskBoardPollingActivity()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func applicationDidHide(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func applicationDidUnhide(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window {
            if settings.keepRunningWhenMainWindowClosed {
                hideMainWindowAfterClose()
            } else {
                NSApp.terminate(nil)
            }
            return false
        }
        return true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateTaskBoardPollingActivity()
    }

    private func showMainWindow() {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        setupStatusItemIfNeeded()
        closeStatusPopover()
        applyMainWindowLevel()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateTaskBoardPollingActivity()
    }

    private func hideMainWindowAfterClose() {
        closeStatusPopover()
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        updateTaskBoardPollingActivity()
    }

    private func applyMainWindowLevel() {
        window?.level = settings.keepMainWindowOnTop ? .floating : .normal
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func setupMainMenu() {
        let language = settings.language
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "codexU")
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(
            title: language.text("关于 codexU", "About codexU"),
            action: #selector(showAboutPanel),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: language.text("设置…", "Settings..."),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        ))
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: language.text("隐藏 codexU", "Hide codexU"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: language.text("隐藏其他", "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: language.text("全部显示", "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: language.text("退出 codexU", "Quit codexU"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        ))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: language.text("窗口", "Window"))
        windowMenuItem.submenu = windowMenu
        let minimizeItem = NSMenuItem(
            title: language.text("最小化", "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minimizeItem)
        let bringAllItem = NSMenuItem(
            title: language.text("全部前置", "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        bringAllItem.target = NSApp
        windowMenu.addItem(bringAllItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func openSettingsWindow() {
        closeStatusPopover()

        if settingsWindow == nil {
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = settings.language.text("设置", "Settings")
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.delegate = self
            settingsWindow.contentView = NSHostingView(
                rootView: SettingsPanelView(settings: settings, store: store, updateStore: updateStore)
            )
            settingsWindow.center()
            self.settingsWindow = settingsWindow
        }

        guard let settingsWindow else { return }
        settingsWindow.title = settings.language.text("设置", "Settings")
        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeSettings() {
        settings.$keepMainWindowOnTop
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyMainWindowLevel()
            }
            .store(in: &cancellables)

        settings.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] language in
                self?.settingsWindow?.title = language.text("设置", "Settings")
                self?.setupMainMenu()
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        settings.$themeMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        settings.$visibleRuntimeScopes
            .receive(on: RunLoop.main)
            .sink { [weak self] scopes in
                guard let self else { return }
                self.store.updateVisibleRuntimeScopes(scopes)
                self.statusPopover?.contentSize = CGSize(
                    width: 380,
                    height: runtimeStatusPopoverHeight(for: scopes.count)
                )
                self.updateStatusItem()
            }
            .store(in: &cancellables)

        settings.$statusItemPreferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        settings.$globalShortcut
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

    }

    @objc private func statusItemClicked() {
        toggleStatusPopover()
    }

    private func toggleStatusPopover() {
        if statusPopover?.isShown == true {
            closeStatusPopover()
            return
        }

        guard let button = statusItem?.button else { return }
        store.refreshIfStale(maximumAge: 5 * 60)
        let popover = NSPopover()
        popover.behavior = CommandLine.arguments.contains("--show-status-popover")
            ? .applicationDefined
            : .transient
        popover.animates = true
        popover.contentSize = CGSize(
            width: 380,
            height: runtimeStatusPopoverHeight(for: settings.visibleRuntimeScopes.count)
        )
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RuntimeStatusMenuView(
                store: store,
                settings: settings,
                updateStore: updateStore,
                openRuntime: { [weak self] scope in
                    self?.openMainWindow(selecting: scope)
                },
                openCurrent: { [weak self] in
                    self?.openMainWindow(selecting: nil)
                },
                openSettings: { [weak self] in
                    self?.openSettingsWindow()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        )
        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        updateTaskBoardPollingActivity()
        configureStatusPopoverWindow()
        DispatchQueue.main.async { [weak self] in
            self?.configureStatusPopoverWindow()
        }
        installStatusPopoverEventMonitors()
    }

    private func configureStatusPopoverWindow() {
        guard let window = statusPopover?.contentViewController?.view.window else { return }
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
    }

    private func openMainWindow(selecting scope: RuntimeScope?) {
        if let scope {
            store.selectRuntime(scope)
        }
        showMainWindow()
    }

    func popoverDidClose(_ notification: Notification) {
        statusPopover = nil
        removeStatusPopoverEventMonitors()
        updateTaskBoardPollingActivity()
    }

    private func closeStatusPopover() {
        statusPopover?.performClose(nil)
        statusPopover = nil
        removeStatusPopoverEventMonitors()
        updateTaskBoardPollingActivity()
    }

    private func updateTaskBoardPollingActivity() {
        guard let window else {
            store.setMainWindowActive(false)
            return
        }
        let mainWindowActive = window.isVisible
            && !window.isMiniaturized
            && window.isKeyWindow
            && window.isOnActiveSpace
            && window.occlusionState.contains(.visible)
            && NSApp.isActive
            && !NSApp.isHidden
        store.setMainWindowActive(mainWindowActive)
    }

    private func installStatusPopoverEventMonitors() {
        removeStatusPopoverEventMonitors()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeStatusPopover()
                return nil
            }
            if self.shouldCloseStatusPopover(for: event) {
                self.closeStatusPopover()
            }
            return event
        }) {
            statusPopoverEventMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeStatusPopover()
            }
        }) {
            statusPopoverEventMonitors.append(globalMonitor)
        }
    }

    private func shouldCloseStatusPopover(for event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown else {
            return false
        }
        if let popoverWindow = statusPopover?.contentViewController?.view.window, event.window === popoverWindow {
            return false
        }
        if let statusButtonWindow = statusItem?.button?.window, event.window === statusButtonWindow {
            return false
        }
        return true
    }

    private func removeStatusPopoverEventMonitors() {
        for monitor in statusPopoverEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        statusPopoverEventMonitors.removeAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        statusItemAppearanceObservation = button.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        updateStatusItem()
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func setupStatusItemIfNeeded() {
        guard statusItem == nil else {
            updateStatusItem()
            return
        }
        setupStatusItem()
    }

    private func observeStatusItemUsage() {
        store.$multiRuntimeSnapshot
            .combineLatest(store.$selectedRuntimeScope, store.$isRefreshing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let presentation = currentStatusItemPresentation()
        let appearance = button.effectiveAppearance

        // Skip redundant redraws. Mutating `button.image`/`length` triggers a
        // status-bar relayout, which re-fires the `effectiveAppearance` KVO
        // observer and calls back into this method. Without this guard the icon
        // repaints in a tight feedback loop, pinning a CPU core.
        if presentation == lastRenderedStatusItemPresentation,
           appearance.name == lastRenderedStatusItemAppearanceName {
            return
        }
        lastRenderedStatusItemPresentation = presentation
        lastRenderedStatusItemAppearanceName = appearance.name

        statusItem?.length = presentation.itemLength
        button.image = statusItemRenderer.render(
            presentation,
            appearance: appearance
        )
        button.toolTip = presentation.tooltip
        button.setAccessibilityLabel("codexU")
        button.setAccessibilityValue(presentation.accessibilityValue)
    }

    private func selectedRuntimeSummary() -> RuntimeMenuSummary? {
        store.runtimeSnapshot(for: store.selectedRuntimeScope)?.summary
    }

    private func currentStatusItemPresentation() -> StatusItemPresentation {
        let source = selectedRuntimeSummary().map(StatusItemSourceSnapshot.init(summary:))
            ?? StatusItemSourceSnapshot.unavailable(runtime: store.selectedRuntimeScope)
        return statusItemPresentationBuilder.build(
            source: source,
            preferences: settings.statusItemPreferences,
            language: settings.language,
            shortcutName: settings.globalShortcut?.displayName
        )
    }

    @discardableResult
    private func registerGlobalHotKey(_ shortcut: GlobalShortcut) -> Bool {
        debugLog("register global hotkey \(shortcut.displayName)")
        guard installGlobalHotKeyHandler() else { return false }
        let status = registerHotKeyReference(shortcut, id: 1, reference: &globalHotKeyRef)
        if status == noErr {
            debugLog("global hotkey registered")
        } else {
            debugLog("RegisterEventHotKey failed status=\(status)")
        }
        return status == noErr
    }

    @discardableResult
    private func installGlobalHotKeyHandler() -> Bool {
        guard globalHotKeyHandler == nil else { return true }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.toggleMainWindow()
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &globalHotKeyHandler
        )
        guard handlerStatus == noErr else {
            debugLog("InstallEventHandler failed status=\(handlerStatus)")
            return false
        }

        return true
    }

    private func replaceGlobalHotKey(
        with shortcut: GlobalShortcut
    ) -> Result<Void, GlobalShortcutRegistrationFailure> {
        guard installGlobalHotKeyHandler() else { return .failure(.failed) }
        let replacement: Result<EventHotKeyRef, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: globalHotKeyRef,
                registerCandidate: {
                    var candidateRef: EventHotKeyRef?
                    let status = registerHotKeyReference(
                        shortcut,
                        id: 2,
                        reference: &candidateRef
                    )
                    guard status == noErr, let candidateRef else {
                        debugLog("replacement hotkey registration failed status=\(status)")
                        return .failure(status == eventHotKeyExistsErr ? .occupied : .failed)
                    }
                    return .success(candidateRef)
                },
                unregister: { reference in
                    let status = UnregisterEventHotKey(reference)
                    guard status == noErr else {
                        debugLog("old hotkey unregistration failed status=\(status)")
                        return .failure(.failed)
                    }
                    return .success(())
                },
                rollbackCandidate: { reference in
                    let status = UnregisterEventHotKey(reference)
                    if status != noErr {
                        debugLog("candidate hotkey rollback failed status=\(status)")
                    }
                }
            )
        switch replacement {
        case .failure(let error):
            return .failure(error)
        case .success(let candidateRef):
            globalHotKeyRef = candidateRef
            debugLog("global hotkey replaced with \(shortcut.displayName)")
            return .success(())
        }
    }

    private func registerHotKeyReference(
        _ shortcut: GlobalShortcut,
        id: UInt32,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CDXU"), id: id)
        // Carbon can report conflicts only when the existing registration is
        // also exclusive. macOS does not expose other apps' nonexclusive
        // registrations for preflight inspection.
        return RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
    }

    private func unregisterGlobalHotKey() {
        _ = unregisterGlobalHotKeyReference()
        if let globalHotKeyHandler {
            RemoveEventHandler(globalHotKeyHandler)
        }
        globalHotKeyHandler = nil
    }

    private func unregisterGlobalHotKeyReference() -> Result<Void, GlobalShortcutRegistrationFailure> {
        guard let reference = globalHotKeyRef else { return .success(()) }
        let status = UnregisterEventHotKey(reference)
        guard status == noErr else {
            debugLog("global hotkey unregistration failed status=\(status)")
            return .failure(.failed)
        }
        globalHotKeyRef = nil
        return .success(())
    }
}

@main
struct codexUMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test-global-shortcut") {
            exit(GlobalShortcutSelfTest.run() ? 0 : 1)
        }

        if let helperIndex = CommandLine.arguments.firstIndex(of: "--hold-exclusive-hotkey"),
           CommandLine.arguments.indices.contains(helperIndex + 1) {
            GlobalShortcutSelfTest.holdExclusiveShortcut(
                readyFile: CommandLine.arguments[helperIndex + 1]
            )
        }

        if CommandLine.arguments.contains("--self-test-status-item") {
            exit(StatusItemPresentationSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-particle-animation") {
            exit(QuotaParticleAnimationSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-rate-limits") {
            exit(CodexRateLimitNormalizerSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-updates") {
            exit(AppUpdateSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-statistics-time-zone") {
            exit(StatisticsTimeZoneSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-task-navigation") {
            exit(TaskNavigationSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-local-system") {
            exit(LocalSystemMonitorSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-agent-selection") {
            exit(AgentSelectionSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-codex-token-events") {
            exit(CodexTokenEventNormalizerSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--dump-json") {
            dumpJSON(MultiRuntimeUsageReader().load())
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

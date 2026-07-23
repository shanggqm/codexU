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
    let resetCreditDetails: [ResetCreditDetail]?
}

struct ResetCreditDetail: Identifiable, Equatable {
    let id: String
    let expiresAt: Date?
}

struct ResetCreditDisclosure: Equatable {
    static let inlineDetailLimit = 2

    let totalCount: Int
    let details: [ResetCreditDetail]

    var fullDetails: [ResetCreditDetail] {
        Array(details.prefix(max(0, totalCount)))
    }

    var inlineDetails: [ResetCreditDetail] {
        Array(fullDetails.prefix(Self.inlineDetailLimit))
    }

    var hiddenCount: Int {
        max(0, totalCount - inlineDetails.count)
    }

    var missingDetailCount: Int {
        max(0, totalCount - fullDetails.count)
    }

    var showsHoverTooltip: Bool {
        !inlineDetails.isEmpty
    }
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

struct ModelUsageTrend: Identifiable, Equatable, Codable {
    let id: String
    let model: String?
    let dayBuckets: [UsageDayBucket]
    let summary: UsageTrendSummary
    let activeDayCount: Int
}

struct UsageTrend: Equatable, Codable {
    let dayBuckets: [UsageDayBucket]
    let heatmapWeeks: [[UsageHeatmapDay]]
    let heatmapThresholds: [Int64]
    let summary: UsageTrendSummary
    // `nil` means this runtime does not support model attribution; an empty
    // array means attribution is supported but no model record was found.
    let modelTrends: [ModelUsageTrend]?
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

struct TaskItem: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let chip: String
    let updatedAt: Date?
    let tokens: Int64?
    let kind: TaskColumnKind
    let threadID: String?
    let runtimeState: TaskRuntimeState
    let isRealtime: Bool
    let sourceKind: TaskSourceKind
    let displayState: TaskDisplayState
    let stateBasis: TaskStateBasis
    let rawStatus: String?
    let nextRunAt: Date?

    init(
        id: String,
        code: String,
        title: String,
        detail: String,
        chip: String,
        updatedAt: Date?,
        tokens: Int64?,
        kind: TaskColumnKind,
        threadID: String? = nil,
        runtimeState: TaskRuntimeState = .recorded,
        isRealtime: Bool = false,
        sourceKind: TaskSourceKind,
        displayState: TaskDisplayState,
        stateBasis: TaskStateBasis,
        rawStatus: String? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.detail = detail
        self.chip = chip
        self.updatedAt = updatedAt
        self.tokens = tokens
        self.kind = kind
        self.threadID = threadID
        self.runtimeState = runtimeState
        self.isRealtime = isRealtime
        self.sourceKind = sourceKind
        self.displayState = displayState
        self.stateBasis = stateBasis
        self.rawStatus = rawStatus
        self.nextRunAt = nextRunAt
    }
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
    let monthlyQuota: RateWindow?
    let credits: CreditsInfo?
    let cloudLifetimeTokens: Int64?
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
        monthlyQuota: nil,
        credits: nil,
        cloudLifetimeTokens: nil,
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
            monthlyQuota: monthlyQuota,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )
    }

    func replacingQuotaWindows(
        fiveHourQuota: RateWindow?,
        sevenDayQuota: RateWindow?,
        monthlyQuota: RateWindow?,
        credits: CreditsInfo?,
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
            monthlyQuota: monthlyQuota,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
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
    let usesReferencePricing: Bool
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
    let model: String?
    let eventIdentity: CodexTokenEventIdentity
}

private struct SkillLoadEvent: Codable {
    let path: String
    let date: Date?
}

private struct SessionUsageCacheEntry: Codable {
    let fileSize: Int64
    let modificationDate: Date?
    let forkedFromId: String?
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
    let forkBaselineTokensByThreadId: [String: Int64]
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
    @Published var visibleRuntimeScopes: [RuntimeScope] = RuntimeScope.allCases
    @Published var isRefreshing = false
    @Published private(set) var statisticsPreference = StatisticsTimeZonePreferenceStore.load()
    @Published private(set) var statisticsTransitionMessage: String?
    @Published private(set) var isSwitchingStatisticsTimeZone = false
    @Published private(set) var visualEnergyMode: VisualEnergyMode = .suspended
    @Published private(set) var codexLiveTasks: CodexTaskLiveSnapshot = .disconnected
    @Published private(set) var taskFocusRequest: TaskFocusRequest?

    private var fullTimer: Timer?
    private var taskBoardTimer: Timer?
    private var performanceSampleTimer: Timer?
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
    private var baseTaskBoards: [RuntimeScope: TaskBoard] = [:]
    private let statisticsSnapshotCacheLimit = 4
    private let statisticsSnapshotCacheTTL: TimeInterval = 3 * 60
    private let taskBoardRefreshInterval: TimeInterval = 60
    private let foregroundFullRefreshInterval: TimeInterval = 5 * 60
    private let backgroundFullRefreshInterval: TimeInterval = 15 * 60
    private let codexTaskClient: CodexTaskEventClient

    init(codexTaskClient: CodexTaskEventClient = CodexAppServerTaskClient()) {
        self.codexTaskClient = codexTaskClient
        self.codexTaskClient.onSnapshot = { [weak self] snapshot in
            self?.applyCodexLiveTasks(snapshot)
        }
    }

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
        codexTaskClient.start(reason: .startup)
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
        updateCodexTaskConnection()
        PerformanceMonitor.shared.recordResourceSample(windowVisible: isMainWindowActive)
        performanceSampleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            PerformanceMonitor.shared.recordResourceSample(windowVisible: self.isMainWindowActive)
        }
        performanceSampleTimer?.tolerance = 90
    }

    func stop() {
        hasStarted = false
        fullTimer?.invalidate()
        taskBoardTimer?.invalidate()
        statisticsRolloverTimer?.invalidate()
        statisticsFeedbackTimer?.invalidate()
        performanceSampleTimer?.invalidate()
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
        codexTaskClient.stop()
        PerformanceMonitor.shared.flush()
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
        isRefreshing = true
        let performanceSpan = PerformanceMonitor.shared.begin(.fullRefresh)

        DispatchQueue.global(qos: .utility).async {
            let multiSnapshot = MultiRuntimeUsageReader().load(
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
                PerformanceMonitor.shared.end(performanceSpan)
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
                leadership: cached.leadership,
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
        StatisticsContext(preference: preference, now: Date()).resolvedIdentifier
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
        let key = snapshot.statisticsIdentity.resolvedIdentifier
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
        updateCodexTaskConnection()
    }

    func requestTaskFocus(scope: RuntimeScope, threadID: String?) {
        selectRuntime(scope)
        taskFocusRequest = TaskFocusRequest(id: UUID(), runtimeScope: scope, threadID: threadID)
    }

    func attentionItems(for scopes: [RuntimeScope], updateResult: AppUpdateResult) -> [TaskAttentionItem] {
        var items: [TaskAttentionItem] = []
        for scope in scopes {
            guard let runtime = runtimeSnapshot(for: scope) else { continue }
            items.append(contentsOf: runtime.snapshot.taskBoard?.attentionItems(scope: scope) ?? [])
            if runtime.status == .unavailable || runtime.status == .stale || runtime.status == .snapshotNeeded {
                items.append(TaskAttentionItem(
                    id: "data-\(scope.runtimeId)-\(runtime.status.rawValue)",
                    kind: .dataIssue,
                    runtimeScope: scope,
                    threadID: nil,
                    title: scope.displayName,
                    since: runtime.snapshot.refreshedAt
                ))
            }
        }
        if updateResult.status == .updateAvailable {
            items.append(TaskAttentionItem(
                id: "update-\(updateResult.latestVersionLabel ?? "available")",
                kind: .update,
                runtimeScope: nil,
                threadID: nil,
                title: updateResult.latestVersionLabel ?? "codexU",
                since: updateResult.checkedAt
            ))
        }
        return items
    }

    func highestPriorityAttention(
        for scopes: [RuntimeScope],
        updateResult: AppUpdateResult
    ) -> TaskAttentionItem? {
        TaskAttentionSelector.highestPriority(attentionItems(for: scopes, updateResult: updateResult))
    }

    func runtimeSnapshot(for scope: RuntimeScope) -> RuntimeUsageSnapshot? {
        runtimeSnapshots.first { $0.scope == scope }
    }

    func updateVisibleRuntimeScopes(_ scopes: [RuntimeScope]) {
        visibleRuntimeScopes = scopes.isEmpty ? RuntimeScope.allCases : scopes
        if !visibleRuntimeScopes.contains(selectedRuntimeScope) {
            selectRuntime(visibleRuntimeScopes.first ?? selectedRuntimeScope)
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
        updateCodexTaskConnection()
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
        updateCodexTaskConnection()
    }

    func setStatusPopoverVisible(_ isVisible: Bool) {
        if isVisible {
            codexTaskClient.start(reason: .popover)
        } else if !isTaskBoardPollingEnabled {
            codexTaskClient.stopIfIdle()
        }
    }

    private func updateCodexTaskConnection() {
        if isTaskBoardPollingEnabled && selectedRuntimeScope == .codex {
            codexTaskClient.start(reason: .taskUI)
        } else {
            codexTaskClient.stopIfIdle()
        }
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
        let performanceSpan = PerformanceMonitor.shared.begin(.taskRefresh)
        let scope = selectedRuntimeScope
        let preference = statisticsPreference
        if scope == .codex {
            codexTaskClient.refreshThreads()
        }

        DispatchQueue.global(qos: .utility).async {
            let taskBoard = MultiRuntimeUsageReader().loadTaskBoard(
                scope: scope,
                statisticsPreference: preference
            )
            DispatchQueue.main.async {
                self.applyTaskBoard(taskBoard, for: scope)
                self.isRefreshingTaskBoard = false
                PerformanceMonitor.shared.end(performanceSpan, success: taskBoard != nil)
                if self.hasPendingRefresh {
                    self.hasPendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    private func apply(_ multiSnapshot: MultiRuntimeUsageSnapshot) {
        let performanceSpan = PerformanceMonitor.shared.begin(.statePublish)
        defer { PerformanceMonitor.shared.end(performanceSpan) }
        let reconciledRuntimes = RuntimeQuotaContinuity.reconcile(
            previous: runtimeSnapshots,
            incoming: multiSnapshot.runtimes
        )
        for runtime in reconciledRuntimes {
            if let board = runtime.snapshot.taskBoard {
                baseTaskBoards[runtime.scope] = board
            }
        }
        let displayedRuntimes = reconciledRuntimes.map { runtime -> RuntimeUsageSnapshot in
            guard runtime.scope == .codex,
                  let board = baseTaskBoards[.codex]
            else { return runtime }
            return runtime.replacingTaskBoard(board.merging(codexLiveTasks))
        }
        let reconciledSnapshot = MultiRuntimeUsageSnapshot(
            refreshedAt: multiSnapshot.refreshedAt,
            runtimes: displayedRuntimes,
            aggregate: AgentUsageAggregator().aggregate(displayedRuntimes, at: multiSnapshot.refreshedAt),
            leadership: multiSnapshot.leadership,
            statisticsIdentity: multiSnapshot.statisticsIdentity
        )
        let nextScope = reconciledSnapshot.defaultScope(
            preferred: selectedRuntimeScope,
            allowedScopes: visibleRuntimeScopes
        )
        multiRuntimeSnapshot = reconciledSnapshot
        runtimeSnapshots = displayedRuntimes
        selectedRuntimeScope = nextScope
        snapshot = reconciledSnapshot.displaySnapshot(for: nextScope)
    }

    private func applyTaskBoard(_ taskBoard: TaskBoard?, for scope: RuntimeScope) {
        if let taskBoard {
            baseTaskBoards[scope] = taskBoard
        }
        let displayedBoard = scope == .codex
            ? taskBoard?.merging(codexLiveTasks)
            : taskBoard
        publishTaskBoard(displayedBoard, for: scope)
    }

    private func applyCodexLiveTasks(_ liveTasks: CodexTaskLiveSnapshot) {
        codexLiveTasks = liveTasks
        guard let baseBoard = baseTaskBoards[.codex] else { return }
        publishTaskBoard(baseBoard.merging(liveTasks), for: .codex)
    }

    private func publishTaskBoard(_ taskBoard: TaskBoard?, for scope: RuntimeScope) {
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
            leadership: multiRuntimeSnapshot.leadership,
            statisticsIdentity: multiRuntimeSnapshot.statisticsIdentity
        )
        if selectedRuntimeScope == scope {
            snapshot = runtimeSnapshots[index].snapshot
        }
    }
}

final class CodexUsageReader {
    private let fileManager = FileManager.default
    private let localAnalyticsCacheVersion = 11
    private let sessionUsageCacheVersion = 8
    private static let memorySessionUsageCacheLimit = 64
    private static let persistentSessionUsageCacheLimit = 1_024
    private static let maximumPersistentCacheBytes: Int64 = 128 * 1_024 * 1_024
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

        return UsageSnapshot(
            refreshedAt: context.now,
            account: appServer.account,
            limitId: appServer.limitId,
            limitName: appServer.limitName,
            quotaReadSucceeded: appServer.quotaReadSucceeded,
            fiveHourQuota: appServer.fiveHourQuota,
            sevenDayQuota: appServer.sevenDayQuota,
            monthlyQuota: appServer.monthlyQuota,
            credits: appServer.credits,
            cloudLifetimeTokens: appServer.cloudLifetimeTokens,
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
        var monthlyQuota: RateWindow?
        var rateLimitDiagnostics: [String] = []
        var credits: CreditsInfo?
        var cloudLifetimeTokens: Int64?
    }

    private func readAppServer(messages: inout [String]) -> AppServerSnapshot {
        let performanceSpan = PerformanceMonitor.shared.begin(.appServerQuota)
        defer { PerformanceMonitor.shared.end(performanceSpan) }
        guard let codexPath = resolveCodexExecutablePath() else {
            messages.append("未找到 codex 可执行文件")
            return AppServerSnapshot()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            messages.append("app-server 启动失败")
            return AppServerSnapshot()
        }

        let writeLock = NSLock()
        let inputHandle = input.fileHandleForWriting
        var acceptsWrites = true
        func writeMessage(_ request: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: request) else { return }
            writeLock.lock()
            defer { writeLock.unlock() }
            guard acceptsWrites else { return }
            do {
                try inputHandle.write(contentsOf: data)
                try inputHandle.write(contentsOf: Data("\n".utf8))
            } catch {
                acceptsWrites = false
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
            default:
                break
            }
            lock.unlock()

            if [2, 3, 4].contains(id) {
                markComplete(id)
            }
        }

        let outputHandle = output.fileHandleForReading
        guard let outputDescriptor = try? POSIXPipeReader.duplicateDescriptor(for: outputHandle) else {
            writeLock.lock()
            acceptsWrites = false
            try? inputHandle.close()
            writeLock.unlock()
            terminate(process)
            try? outputHandle.close()
            messages.append("app-server 输出读取失败")
            return AppServerSnapshot()
        }
        let readerGroup = DispatchGroup()
        let maximumOutputBufferBytes = 1 * 1_024 * 1_024
        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                Darwin.close(outputDescriptor)
                readerGroup.leave()
            }
            while true {
                let data: Data
                do {
                    guard let next = try POSIXPipeReader.readChunk(
                        from: outputDescriptor,
                        maximumBytes: 64 * 1_024
                    ) else { break }
                    data = next
                } catch {
                    break
                }

                buffer.append(data)
                if buffer.count > maximumOutputBufferBytes {
                    lock.lock()
                    appServerMessages.append("app-server 输出超过安全上限")
                    lock.unlock()
                    [2, 3, 4].forEach(markComplete)
                    break
                }

                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty {
                        parseLine(line)
                    }
                }
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

        writeLock.lock()
        acceptsWrites = false
        try? inputHandle.close()
        writeLock.unlock()
        if process.isRunning {
            let pid = process.processIdentifier
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { Darwin.kill(pid, SIGKILL) }
            }
        }
        try? outputHandle.close()
        _ = readerGroup.wait(timeout: .now() + 1)

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
        snapshot.monthlyQuota = quotaReadSucceeded ? normalized.monthly : nil
        var diagnostics = rateLimitDiagnostics(for: normalized)
        if !hasWindowFields {
            diagnostics.append("Codex 额度响应缺少窗口字段，未将其视为当前无限制")
        }
        if hasMalformedWindow {
            diagnostics.append("Codex 额度窗口格式无法解析，未将其视为当前无限制")
        }
        snapshot.rateLimitDiagnostics = diagnostics

        var resetCredits: Int?
        var resetCreditDetails: [ResetCreditDetail]?
        if let reset = result["rateLimitResetCredits"] as? [String: Any] {
            resetCredits = CodexResetCreditNormalizer.normalizeAvailableCount(
                intValue(reset["availableCount"])
            )
            if let rawDetails = reset["credits"] as? [[String: Any]] {
                resetCreditDetails = rawDetails
                    .compactMap(parseResetCreditDetail)
                    .sorted { lhs, rhs in
                        switch (lhs.expiresAt, rhs.expiresAt) {
                        case let (left?, right?):
                            return left == right ? lhs.id < rhs.id : left < right
                        case (.some, .none):
                            return true
                        case (.none, .some):
                            return false
                        case (.none, .none):
                            return lhs.id < rhs.id
                        }
                    }
            }
        }

        if let credits = limits["credits"] as? [String: Any] {
            snapshot.credits = CreditsInfo(
                hasCredits: credits["hasCredits"] as? Bool ?? false,
                unlimited: credits["unlimited"] as? Bool ?? false,
                balance: stringValue(credits["balance"]),
                resetCredits: resetCredits,
                resetCreditDetails: resetCreditDetails
            )
        } else if resetCredits != nil {
            snapshot.credits = CreditsInfo(
                hasCredits: false,
                unlimited: false,
                balance: nil,
                resetCredits: resetCredits,
                resetCreditDetails: resetCreditDetails
            )
        }
    }

    private func parseResetCreditDetail(_ object: [String: Any]) -> ResetCreditDetail? {
        guard let id = object["id"] as? String,
              object["status"] as? String == "available"
        else { return nil }

        let expiresAt = doubleValue(object["expiresAt"])
            .map(Date.init(timeIntervalSince1970:))
        return ResetCreditDetail(id: id, expiresAt: expiresAt)
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
        if windows.monthlyMatchCount > 1 {
            messages.append("Codex 返回了重复的月额度窗口，已停止显示该窗口")
        }
        let missingDurationCount = windows.unclassified.filter {
            $0.windowDurationMins == nil
        }.count
        if missingDurationCount > 0 {
            messages.append("Codex 返回了缺少时长的额度窗口，未将其标注为 5 小时、7 天或月额度")
        }

        let unknownDurations = Set(windows.unclassified.compactMap(\.windowDurationMins)).sorted()
        if !unknownDurations.isEmpty {
            let values = unknownDurations.map(String.init).joined(separator: "、")
            messages.append("Codex 返回了未识别的额度窗口（\(values) 分钟），未将其标注为 5 小时、7 天或月额度")
        }

        return messages
    }

    private func parseCloudLifetimeTokens(_ result: [String: Any]) -> Int64? {
        guard let summary = result["summary"] as? [String: Any] else { return nil }
        return int64Value(summary["lifetimeTokens"])
    }

    private func readLocalUsage(context: RuntimeLoadContext, messages: inout [String]) -> LocalUsage? {
        guard let dbPath = firstExistingPath([
            NSHomeDirectory() + "/.codex/state_5.sqlite",
            NSHomeDirectory() + "/.codex/sqlite/state_5.sqlite"
        ]) else {
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

        let usageQuery = """
        SELECT id, tokens_used AS tokens, updated_at AS updatedAt
        FROM threads;
        """

        let recentQuery = """
        SELECT id, title, tokens_used AS tokens, updated_at AS updatedAt, model, cwd, archived
        FROM threads
        ORDER BY updated_at DESC
        LIMIT 5;
        """

        guard
            let usageObjects = Optional(runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: usageQuery)),
            let recentObjects = Optional(runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: recentQuery))
        else {
            messages.append("SQLite 查询失败")
            return nil
        }

        let rawAnalytics = readLocalAnalytics(
            sqlitePath: sqlitePath,
            dbPath: dbPath,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            statistics: context.statistics,
            messages: &messages
        )
        let forkBaselines = rawAnalytics.forkBaselineTokensByThreadId
        func adjustedTokens(_ object: [String: Any]) -> Int64 {
            let rawTokens = int64Value(object["tokens"]) ?? 0
            guard let threadId = object["id"] as? String else { return rawTokens }
            return max(rawTokens - (forkBaselines[threadId] ?? 0), 0)
        }

        let recent = recentObjects.map { object in
            LocalThread(
                id: object["id"] as? String ?? UUID().uuidString,
                title: object["title"] as? String ?? "Untitled",
                tokens: adjustedTokens(object),
                updatedAt: dateFromEpoch(object["updatedAt"]),
                model: object["model"] as? String,
                cwd: object["cwd"] as? String ?? "",
                archived: (intValue(object["archived"]) ?? 0) != 0
            )
        }

        var tokensByDay: [String: Int64] = [:]
        var lifetimeTokens: Int64 = 0
        var todayTokens: Int64 = 0
        var sevenDayTokens: Int64 = 0
        var lastUpdatedAt: Date?
        for object in usageObjects {
            guard let updatedAt = dateFromEpoch(object["updatedAt"]) else { continue }
            let tokens = adjustedTokens(object)
            lifetimeTokens += tokens
            if updatedAt >= sevenDayStart {
                sevenDayTokens += tokens
            }
            if updatedAt >= dayStart {
                todayTokens += tokens
            }
            if lastUpdatedAt == nil || updatedAt > (lastUpdatedAt ?? .distantPast) {
                lastUpdatedAt = updatedAt
            }
            let key = context.statistics.dayKey(for: updatedAt)
            tokensByDay[key, default: 0] += tokens
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

        let analytics = validatedLocalAnalytics(
            rawAnalytics,
            approximateTodayTokens: todayTokens,
            approximateSevenDayTokens: sevenDayTokens,
            messages: &messages
        )
        let allProjects = readAllTimeProjects(
            sqlitePath: sqlitePath,
            dbPath: dbPath,
            forkBaselines: forkBaselines
        )
        let projectBoard = ProjectBoard(
            recentProjects: analytics.recentProjects.isEmpty
                ? readApproximateRecentProjects(
                    sqlitePath: sqlitePath,
                    dbPath: dbPath,
                    sevenDayStart: sevenDayStart,
                    forkBaselines: forkBaselines
                )
                : analytics.recentProjects,
            allProjects: allProjects
        )

        return LocalUsage(
            lifetimeTokens: lifetimeTokens,
            todayTokens: todayTokens,
            sevenDayTokens: sevenDayTokens,
            threadCount: usageObjects.count,
            lastUpdatedAt: lastUpdatedAt,
            dailyBuckets: dailyBuckets,
            recentThreads: recent,
            detailedUsage: analytics.detailedUsage,
            usageTrend: analytics.usageTrend ?? readApproximateUsageTrend(
                sqlitePath: sqlitePath,
                dbPath: dbPath,
                dayStart: dayStart,
                sevenDayStart: sevenDayStart,
                calendar: calendar,
                forkBaselines: forkBaselines
            ),
            projectBoard: projectBoard,
            toolUsages: analytics.toolUsages,
            skillUsages: analytics.skillUsages
        )
    }

    private func validatedLocalAnalytics(
        _ analytics: LocalAnalytics,
        approximateTodayTokens: Int64,
        approximateSevenDayTokens: Int64,
        messages: inout [String]
    ) -> LocalAnalytics {
        guard let detailed = analytics.detailedUsage else { return analytics }

        let suspiciousToday = CodexDetailedUsageSanity.isSuspicious(
            detailed.today.tokens.visibleTotalTokens,
            comparedWith: approximateTodayTokens
        )
        let suspiciousSevenDay = CodexDetailedUsageSanity.isSuspicious(
            detailed.sevenDay.tokens.visibleTotalTokens,
            comparedWith: approximateSevenDayTokens
        )
        guard suspiciousToday || suspiciousSevenDay else { return analytics }

        messages.append("Codex token_count 精细统计与本机线程统计差异异常，已回退到线程口径")
        return LocalAnalytics(
            detailedUsage: nil,
            usageTrend: nil,
            recentProjects: [],
            toolUsages: analytics.toolUsages.map { usage in
                ToolUsage(
                    id: usage.id,
                    name: usage.name,
                    category: usage.category,
                    callCount: usage.callCount,
                    estimatedTokens: nil,
                    estimatedCostUSD: nil
                )
            },
            skillUsages: analytics.skillUsages,
            forkBaselineTokensByThreadId: analytics.forkBaselineTokensByThreadId
        )
    }

    private func readLocalAnalytics(
        sqlitePath: String,
        dbPath: String,
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
        let sources = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: sourceQuery).compactMap { object -> SessionUsageSource? in
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
            return LocalAnalytics(
                detailedUsage: nil,
                usageTrend: nil,
                recentProjects: [],
                toolUsages: [],
                skillUsages: [],
                forkBaselineTokensByThreadId: [:]
            )
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

        let persistentAnalyticsCache = readPersistentLocalAnalyticsCache()
        if let cached = persistentAnalyticsCache,
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.timeZoneIdentifier == statistics.resolvedIdentifier,
           cached.sourceFingerprint == sourceFingerprint {
            Self.localAnalyticsCache = cached
            writePersistentSessionUsageCache()
            return cached.analytics
        }

        defer { releaseSessionUsageWorkingSet() }

        var reusableSkillStaticInfo: [String: SkillStaticInfo] = [:]
        for skill in persistentAnalyticsCache?.analytics.skillUsages ?? [] {
            reusableSkillStaticInfo[skill.path] = SkillStaticInfo(
                tokenEstimate: skill.staticTokenEstimate,
                byteCount: skill.staticByteCount
            )
        }
        for skill in Self.localAnalyticsCache?.analytics.skillUsages ?? [] {
            reusableSkillStaticInfo[skill.path] = SkillStaticInfo(
                tokenEstimate: skill.staticTokenEstimate,
                byteCount: skill.staticByteCount
            )
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
        var dailyUsageByModel: [String: [String: PricedTokenUsage]] = [:]
        var modelNamesByID: [String: String] = [:]
        var recentProjectUsage: [String: ProjectUsageAccumulator] = [:]
        var toolUsage: [String: ToolUsageAccumulator] = [:]
        var skillUsage: [String: SkillUsageAccumulator] = [:]

        let sourceByThreadId = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.threadId, $0) }
        )
        var inheritedPrefixLengthByThreadId: [String: Int] = [:]
        var forkBaselineTokensByThreadId: [String: Int64] = [:]

        for source in sources {
            guard let entry = cachedSessionUsage(
                source: source,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter
            ),
            let parentId = entry.forkedFromId,
            let parentSource = sourceByThreadId[parentId],
            let parentEntry = cachedSessionUsage(
                source: parentSource,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter
            ) else { continue }

            let inheritedPrefixLength = CodexForkUsageDeduplicator.inheritedPrefixLength(
                child: entry.deltas.map(\.eventIdentity),
                parent: parentEntry.deltas.map(\.eventIdentity)
            )
            if inheritedPrefixLength > 0 {
                inheritedPrefixLengthByThreadId[source.threadId] = inheritedPrefixLength
                forkBaselineTokensByThreadId[source.threadId] = entry.deltas
                    .prefix(inheritedPrefixLength)
                    .reduce(0) { $0 + $1.tokens.totalTokens }
            }
        }

        for source in sources {
            guard let entry = cachedSessionUsage(
                source: source,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter
            ) else { continue }
            let inheritedPrefixLength = inheritedPrefixLengthByThreadId[source.threadId] ?? 0
            let effectiveDeltas = entry.deltas.dropFirst(inheritedPrefixLength)

            if entry.hasTokenEvents {
                accumulator.parsedFileCount += 1
                accumulator.tokenEventCount += max(entry.tokenEventCount - inheritedPrefixLength, 0)
            }

            var sessionUsage = PricedTokenUsage.zero
            for delta in effectiveDeltas {
                let model = resolvedModelUsageName(turnContextModel: delta.model, threadModel: source.model)
                let price = modelTokenPrice(for: model)
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

                    let modelID = modelUsageIdentifier(for: model)
                    var modelUsage = dailyUsageByModel[modelID] ?? [:]
                    var modelDayUsage = modelUsage[key] ?? .zero
                    modelDayUsage.add(tokens: delta.tokens, costUSD: cost)
                    modelUsage[key] = modelDayUsage
                    dailyUsageByModel[modelID] = modelUsage
                    if let model {
                        modelNamesByID[modelID] = model
                    }
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
        let skillUsages = makeSkillUsages(
            from: skillUsage,
            reusableStaticInfo: reusableSkillStaticInfo
        )

        guard accumulator.parsedFileCount > 0, accumulator.tokenEventCount > 0 else {
            messages.append("未找到 Codex token_count 事件")
            let analytics = LocalAnalytics(
                detailedUsage: nil,
                usageTrend: nil,
                recentProjects: [],
                toolUsages: toolUsage.values
                    .map { $0.makeUsage() }
                    .sorted { $0.callCount == $1.callCount ? $0.name < $1.name : $0.callCount > $1.callCount },
                skillUsages: skillUsages,
                forkBaselineTokensByThreadId: forkBaselineTokensByThreadId
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
                modelDailyUsage: dailyUsageByModel,
                modelNamesByID: modelNamesByID
            ),
            recentProjects: recentProjectUsage.values
                .map { $0.makeUsage() }
                .filter { $0.tokens > 0 }
                .sorted { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens },
            toolUsages: toolUsage.values
                .map { $0.makeUsage() }
                .sorted { $0.callCount == $1.callCount ? $0.name < $1.name : $0.callCount > $1.callCount },
            skillUsages: skillUsages,
            forkBaselineTokensByThreadId: forkBaselineTokensByThreadId
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
        modelDailyUsage: [String: [String: PricedTokenUsage]] = [:],
        modelNamesByID: [String: String] = [:]
    ) -> UsageTrend {
        let calendar = Calendar.current
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

        let dayOfMonth = max(calendar.component(.day, from: Date()), 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: Date())?.count ?? dayOfMonth
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
        let modelTrends = modelDailyUsage.compactMap { modelID, usage -> ModelUsageTrend? in
            let modelTrend = makeUsageTrend(
                dailyUsage: usage,
                dayStart: dayStart,
                sevenDayStart: sevenDayStart,
                trendStart: trendStart,
                monthStart: monthStart,
                sourceQuality: sourceQuality
            )
            guard modelTrend.activeDayCount > 0 else { return nil }
            return ModelUsageTrend(
                id: modelID,
                model: modelNamesByID[modelID],
                dayBuckets: modelTrend.dayBuckets,
                summary: modelTrend.summary,
                activeDayCount: modelTrend.activeDayCount
            )
        }
        .sorted { lhs, rhs in
            let lhsRecent = lhs.summary.sevenDay.tokens.visibleTotalTokens
            let rhsRecent = rhs.summary.sevenDay.tokens.visibleTotalTokens
            if lhsRecent != rhsRecent { return lhsRecent > rhsRecent }
            let lhsTotal = lhs.dayBuckets.reduce(Int64(0)) { $0 + $1.tokens }
            let rhsTotal = rhs.dayBuckets.reduce(Int64(0)) { $0 + $1.tokens }
            if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
            return (lhs.model ?? "") < (rhs.model ?? "")
        }

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
            modelTrends: modelTrends,
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
        dbPath: String,
        dayStart: Date,
        sevenDayStart: Date,
        calendar: Calendar,
        forkBaselines: [String: Int64]
    ) -> UsageTrend? {
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? sevenDayStart
        var monthComponents = calendar.dateComponents([.year, .month], from: Date())
        monthComponents.day = 1
        monthComponents.hour = 0
        monthComponents.minute = 0
        monthComponents.second = 0
        let monthStart = calendar.date(from: monthComponents) ?? dayStart

        let query = """
        SELECT id, updated_at AS updatedAt, tokens_used AS tokens, model
        FROM threads
        WHERE updated_at >= \(Int(trendStart.timeIntervalSince1970))
        ORDER BY updated_at ASC;
        """

        let rows = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query)
        guard !rows.isEmpty else { return nil }

        var dailyUsage: [String: PricedTokenUsage] = [:]
        var dailyUsageByModel: [String: [String: PricedTokenUsage]] = [:]
        var modelNamesByID: [String: String] = [:]
        for row in rows {
            guard let updatedAt = dateFromEpoch(row["updatedAt"]) else { continue }
            let key = localDayKey(updatedAt, calendar: calendar)
            let rawTokens = int64Value(row["tokens"]) ?? 0
            let threadId = row["id"] as? String ?? ""
            let tokens = max(rawTokens - (forkBaselines[threadId] ?? 0), 0)
            let tokenBreakdown = TokenBreakdown(
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: tokens
            )
            var usage = dailyUsage[key] ?? .zero
            usage.add(tokens: tokenBreakdown, costUSD: 0)
            dailyUsage[key] = usage

            let model = normalizedModelUsageName(row["model"] as? String)
            let modelID = modelUsageIdentifier(for: model)
            var modelUsage = dailyUsageByModel[modelID] ?? [:]
            var modelDayUsage = modelUsage[key] ?? .zero
            modelDayUsage.add(tokens: tokenBreakdown, costUSD: 0)
            modelUsage[key] = modelDayUsage
            dailyUsageByModel[modelID] = modelUsage
            if let model {
                modelNamesByID[modelID] = model
            }
        }

        return makeUsageTrend(
            dailyUsage: dailyUsage,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            trendStart: trendStart,
            monthStart: monthStart,
            sourceQuality: .approximate,
            modelDailyUsage: dailyUsageByModel,
            modelNamesByID: modelNamesByID
        )
    }

    private func readAllTimeProjects(
        sqlitePath: String,
        dbPath: String,
        forkBaselines: [String: Int64]
    ) -> [ProjectUsage] {
        readApproximateProjects(
            sqlitePath: sqlitePath,
            dbPath: dbPath,
            updatedSince: nil,
            forkBaselines: forkBaselines
        )
    }

    private func readApproximateRecentProjects(
        sqlitePath: String,
        dbPath: String,
        sevenDayStart: Date,
        forkBaselines: [String: Int64]
    ) -> [ProjectUsage] {
        readApproximateProjects(
            sqlitePath: sqlitePath,
            dbPath: dbPath,
            updatedSince: sevenDayStart,
            forkBaselines: forkBaselines
        )
    }

    private func readApproximateProjects(
        sqlitePath: String,
        dbPath: String,
        updatedSince: Date?,
        forkBaselines: [String: Int64]
    ) -> [ProjectUsage] {
        let dateFilter = updatedSince.map { "AND updated_at >= \(Int($0.timeIntervalSince1970))" } ?? ""
        let query = """
        SELECT id, cwd, tokens_used AS tokens, CASE WHEN recency_at > 0 THEN recency_at ELSE updated_at END AS lastActiveAt
        FROM threads
        WHERE tokens_used > 0
          \(dateFilter)
        """

        var totals: [String: (tokens: Int64, threadCount: Int, lastActiveAt: Date?)] = [:]
        for row in runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query) {
            let path = row["cwd"] as? String ?? ""
            let threadId = row["id"] as? String ?? ""
            let rawTokens = int64Value(row["tokens"]) ?? 0
            let tokens = max(rawTokens - (forkBaselines[threadId] ?? 0), 0)
            let lastActiveAt = dateFromEpoch(row["lastActiveAt"])
            var total = totals[path] ?? (tokens: 0, threadCount: 0, lastActiveAt: nil)
            total.tokens += tokens
            total.threadCount += 1
            if let lastActiveAt,
               total.lastActiveAt == nil || lastActiveAt > (total.lastActiveAt ?? .distantPast) {
                total.lastActiveAt = lastActiveAt
            }
            totals[path] = total
        }

        var projects: [ProjectUsage] = []
        for (path, total) in totals {
            guard total.tokens > 0 else { continue }
            projects.append(ProjectUsage(
                id: path.isEmpty ? "uncategorized" : path,
                name: path.isEmpty ? "未归类" : shortWorkspaceName(path),
                fullPath: path,
                tokens: total.tokens,
                estimatedCostUSD: nil,
                threadCount: total.threadCount,
                lastActiveAt: total.lastActiveAt,
                sourceQuality: .approximate
            ))
        }
        projects.sort { $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens }
        return Array(projects.prefix(24))
    }

    private func makeSkillUsages(
        from accumulators: [String: SkillUsageAccumulator],
        reusableStaticInfo: [String: SkillStaticInfo]
    ) -> [SkillUsage] {
        accumulators.values
            .map { accumulator in
                accumulator.makeUsage(
                    staticInfo: reusableStaticInfo[accumulator.path] ?? skillStaticInfo(for: accumulator.path)
                )
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
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize <= 4 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url) else {
            return SkillStaticInfo(tokenEstimate: nil, byteCount: nil)
        }

        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return SkillStaticInfo(
            tokenEstimate: estimateStaticTokens(text),
            byteCount: Int64(data.count)
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

        let eventPattern = #""type":"(session_meta|turn_context|token_count|function_call|custom_tool_call)""#
        let sessionMetaNeedle = Data(#""type":"session_meta""#.utf8)
        let turnContextNeedle = Data(#""type":"turn_context""#.utf8)
        let tokenCountNeedle = Data(#""type":"token_count""#.utf8)
        let functionCallNeedle = Data(#""type":"function_call""#.utf8)
        let customToolCallNeedle = Data(#""type":"custom_tool_call""#.utf8)
        if let parsed = parseSessionUsageWithGrep(
            url: url,
            eventPattern: eventPattern,
            sessionMetaNeedle: sessionMetaNeedle,
            turnContextNeedle: turnContextNeedle,
            tokenCountNeedle: tokenCountNeedle,
            functionCallNeedle: functionCallNeedle,
            customToolCallNeedle: customToolCallNeedle,
            fractionalFormatter: fractionalFormatter,
            plainFormatter: plainFormatter
        ) {
            let entry = SessionUsageCacheEntry(
                fileSize: fileSize,
                modificationDate: modificationDate,
                forkedFromId: parsed.forkedFromId,
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
        var forkedFromId: String?
        var activeModel: String?
        var counterState = CodexTokenCounterState()
        var sawTokenEvent = false
        var tokenEventCount = 0
        var deltas: [SessionUsageDelta] = []
        var toolCalls: [String: Int] = [:]
        var skillLoads: [SkillLoadEvent] = []
        let maximumSessionLineBytes = 4 * 1_024 * 1_024
        var droppingOversizedLine = false

        while true {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 10) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if !droppingOversizedLine, lineData.count <= maximumSessionLineBytes {
                    processSessionLine(
                        lineData,
                        sessionMetaNeedle: sessionMetaNeedle,
                        turnContextNeedle: turnContextNeedle,
                        tokenCountNeedle: tokenCountNeedle,
                        functionCallNeedle: functionCallNeedle,
                        customToolCallNeedle: customToolCallNeedle,
                        fractionalFormatter: fractionalFormatter,
                        plainFormatter: plainFormatter,
                        forkedFromId: &forkedFromId,
                        activeModel: &activeModel,
                        counterState: &counterState,
                        sawTokenEvent: &sawTokenEvent,
                        tokenEventCount: &tokenEventCount,
                        deltas: &deltas,
                        toolCalls: &toolCalls,
                        skillLoads: &skillLoads
                    )
                }
                droppingOversizedLine = false
            }
            if buffer.count > maximumSessionLineBytes {
                buffer.removeAll(keepingCapacity: false)
                droppingOversizedLine = true
            }
        }

        if !droppingOversizedLine, !buffer.isEmpty {
            processSessionLine(
                buffer,
                sessionMetaNeedle: sessionMetaNeedle,
                turnContextNeedle: turnContextNeedle,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                forkedFromId: &forkedFromId,
                activeModel: &activeModel,
                counterState: &counterState,
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
            forkedFromId: forkedFromId,
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
            if Self.persistentSessionUsageCache == nil {
                _ = persistentSessionUsageCache()
            }
            Self.persistentSessionUsageCache?[key] = entry
            Self.persistentSessionUsageCacheIsDirty = true
        }
        Self.sessionUsageCacheOrder.removeAll { $0 == key }
        Self.sessionUsageCacheOrder.append(key)
        while Self.sessionUsageCacheOrder.count > Self.memorySessionUsageCacheLimit {
            let evicted = Self.sessionUsageCacheOrder.removeFirst()
            Self.sessionUsageCache.removeValue(forKey: evicted)
        }
    }

    private func parseSessionUsageWithGrep(
        url: URL,
        eventPattern: String,
        sessionMetaNeedle: Data,
        turnContextNeedle: Data,
        tokenCountNeedle: Data,
        functionCallNeedle: Data,
        customToolCallNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter
    ) -> (forkedFromId: String?, hasTokenEvents: Bool, tokenEventCount: Int, deltas: [SessionUsageDelta], toolCalls: [String: Int], skillLoads: [SkillLoadEvent])? {
        let grepPath = "/usr/bin/grep"
        guard fileManager.isExecutableFile(atPath: grepPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: grepPath)
        process.arguments = ["-a", "-E", eventPattern, url.path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        guard let data = readBoundedProcessOutput(
            output.fileHandleForReading,
            process: process,
            maximumBytes: 32 * 1_024 * 1_024
        ) else {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }

        var buffer = data
        var forkedFromId: String?
        var activeModel: String?
        var counterState = CodexTokenCounterState()
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
                sessionMetaNeedle: sessionMetaNeedle,
                turnContextNeedle: turnContextNeedle,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                forkedFromId: &forkedFromId,
                activeModel: &activeModel,
                counterState: &counterState,
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
                sessionMetaNeedle: sessionMetaNeedle,
                turnContextNeedle: turnContextNeedle,
                tokenCountNeedle: tokenCountNeedle,
                functionCallNeedle: functionCallNeedle,
                customToolCallNeedle: customToolCallNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                forkedFromId: &forkedFromId,
                activeModel: &activeModel,
                counterState: &counterState,
                sawTokenEvent: &sawTokenEvent,
                tokenEventCount: &tokenEventCount,
                deltas: &deltas,
                toolCalls: &toolCalls,
                skillLoads: &skillLoads
            )
        }

        return (forkedFromId, sawTokenEvent, tokenEventCount, deltas, toolCalls, skillLoads)
    }

    private func processSessionLine(
        _ lineData: Data,
        sessionMetaNeedle: Data,
        turnContextNeedle: Data,
        tokenCountNeedle: Data,
        functionCallNeedle: Data,
        customToolCallNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter,
        forkedFromId: inout String?,
        activeModel: inout String?,
        counterState: inout CodexTokenCounterState,
        sawTokenEvent: inout Bool,
        tokenEventCount: inout Int,
        deltas: inout [SessionUsageDelta],
        toolCalls: inout [String: Int],
        skillLoads: inout [SkillLoadEvent]
    ) {
        let isSessionMeta = lineData.range(of: sessionMetaNeedle) != nil
        let isTurnContext = lineData.range(of: turnContextNeedle) != nil
        let isTokenEvent = lineData.range(of: tokenCountNeedle) != nil
        let isToolEvent = lineData.range(of: functionCallNeedle) != nil || lineData.range(of: customToolCallNeedle) != nil
        guard isSessionMeta || isTurnContext || isTokenEvent || isToolEvent,
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return }

        if object["type"] as? String == "session_meta" {
            if let parentId = payload["forked_from_id"] as? String, !parentId.isEmpty {
                forkedFromId = parentId
            }
            return
        }

        if object["type"] as? String == "turn_context" {
            applyTurnContextModel(payload["model"] as? String, to: &activeModel)
            return
        }

        guard let payloadType = payload["type"] as? String else { return }

        if payloadType == "function_call" || payloadType == "custom_tool_call" {
            if let name = payload["name"] as? String, !name.isEmpty {
                toolCalls[name, default: 0] += 1
            }
            let eventDate = (object["timestamp"] as? String).flatMap {
                fractionalFormatter.date(from: $0) ?? plainFormatter.date(from: $0)
            }
            for path in skillLoadPaths(in: payload) {
                skillLoads.append(SkillLoadEvent(path: path, date: eventDate))
            }
            return
        }

        guard payloadType == "token_count",
              let timestamp = object["timestamp"] as? String,
              let info = payload["info"] as? [String: Any],
              let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp)
        else { return }

        let cumulativeSample = (info["total_token_usage"] as? [String: Any]).map { usage in
            tokenCounterSample(from: usage)
        }
        let lastUsageSample = (info["last_token_usage"] as? [String: Any]).map { usage in
            tokenCounterSample(from: usage)
        }
        guard cumulativeSample != nil || lastUsageSample != nil else { return }

        sawTokenEvent = true
        tokenEventCount += 1

        guard let delta = CodexTokenCounterNormalizer.consume(
            cumulative: cumulativeSample,
            lastUsage: lastUsageSample,
            state: &counterState
        ) else { return }
        deltas.append(
            SessionUsageDelta(
                date: date,
                tokens: delta,
                model: activeModel,
                eventIdentity: CodexTokenEventIdentity(
                    cumulative: cumulativeSample,
                    lastUsage: lastUsageSample
                )
            )
        )
    }

    private func readTaskBoard(context: RuntimeLoadContext, messages: inout [String]) -> TaskBoard? {
        let calendar = context.statistics.calendar
        let now = context.now
        let dayStart = calendar.startOfDay(for: now)
        var activeItems: [TaskItem] = []
        var pendingItems: [TaskItem] = []
        var doneItems: [TaskItem] = []

        if let dbPath = firstExistingPath([
            NSHomeDirectory() + "/.codex/state_5.sqlite",
            NSHomeDirectory() + "/.codex/sqlite/state_5.sqlite"
        ]), let sqlitePath = firstExistingPath([
            "/usr/bin/sqlite3",
            "/opt/homebrew/bin/sqlite3",
            "/opt/homebrew/share/android-commandlinetools/platform-tools/sqlite3"
        ]) {
            let todayThreadsQuery = """
            SELECT id, title, preview, cwd, tokens_used AS tokens, updated_at AS updatedAt, recency_at AS recencyAt, model
            FROM threads
            WHERE archived = 0
              AND COALESCE(thread_source, '') <> 'subagent'
              AND preview <> ''
              AND (
                updated_at >= \(Int(dayStart.timeIntervalSince1970))
                OR recency_at >= \(Int(dayStart.timeIntervalSince1970))
                OR created_at >= \(Int(dayStart.timeIntervalSince1970))
              )
            ORDER BY recency_at DESC, updated_at DESC;
            """

            let archivedTodayQuery = """
            SELECT id, title, preview, cwd, tokens_used AS tokens, COALESCE(archived_at, updated_at) AS updatedAt, model
            FROM threads
            WHERE archived = 1
              AND COALESCE(thread_source, '') <> 'subagent'
              AND COALESCE(archived_at, updated_at) >= \(Int(dayStart.timeIntervalSince1970))
            ORDER BY COALESCE(archived_at, updated_at) DESC;
            """

            let todayThreads = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: todayThreadsQuery)
            for object in todayThreads {
                let updatedAt = dateFromEpoch(object["recencyAt"]) ?? dateFromEpoch(object["updatedAt"])
                let classification = TaskSourceClassifier.codexThread(updatedAt: updatedAt, now: now)
                let item = makeThreadTaskItem(
                    object: object,
                    updatedAt: updatedAt,
                    kind: classification.columnKind,
                    displayState: classification.displayState
                )
                if classification.columnKind == .active {
                    activeItems.append(item)
                } else {
                    pendingItems.append(item)
                }
            }

            doneItems = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: archivedTodayQuery).map { object in
                makeThreadTaskItem(
                    object: object,
                    updatedAt: dateFromEpoch(object["updatedAt"]),
                    kind: .done,
                    displayState: .archived
                )
            }
        } else {
            messages.append("任务看板未找到 SQLite 数据源")
        }

        activeItems = sortedTaskItems(activeItems)
        pendingItems = sortedTaskItems(pendingItems)
        doneItems = sortedTaskItems(doneItems)
        let scheduledItems = readAutomationTasks(now: now)

        return TaskBoard(refreshedAt: now, columns: [
            TaskColumn(id: .active, title: "最近活跃", count: activeItems.count, items: activeItems),
            TaskColumn(id: .pending, title: "待继续", count: pendingItems.count, items: pendingItems),
            TaskColumn(id: .scheduled, title: "定时", count: scheduledItems.count, items: scheduledItems),
            TaskColumn(id: .done, title: "今日归档", count: doneItems.count, items: doneItems)
        ])
    }

    private func makeThreadTaskItem(
        object: [String: Any],
        updatedAt: Date?,
        kind: TaskColumnKind,
        displayState: TaskDisplayState
    ) -> TaskItem {
        let rawId = object["id"] as? String ?? UUID().uuidString
        let title = normalizedTitle(object["title"] as? String, fallback: object["preview"] as? String)
        let cwd = object["cwd"] as? String ?? ""
        let tokens = int64Value(object["tokens"]).flatMap { $0 > 0 ? $0 : nil }
        let compactId = rawId.replacingOccurrences(of: "-", with: "")
        let code = "COD-" + compactId.suffix(4).uppercased()
        let chip = displayState.rawValue

        return TaskItem(
            id: rawId + kind.rawValue,
            code: String(code),
            title: title,
            detail: shortWorkspaceName(cwd),
            chip: chip,
            updatedAt: updatedAt,
            tokens: tokens,
            kind: kind,
            threadID: rawId,
            sourceKind: .codexThread,
            displayState: displayState,
            stateBasis: kind == .done ? .archive : .activityWindow
        )
    }

    private func readAutomationTasks(now: Date) -> [TaskItem] {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/automations")
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
            let schedule = TaskScheduleParser.presentation(rrule: fields["rrule"], now: now)

            items.append(TaskItem(
                id: "automation-" + id,
                code: "AUTO-" + id.prefix(4).uppercased(),
                title: name,
                detail: schedule.summary,
                chip: kind == "heartbeat" ? "Wake" : "Cron",
                updatedAt: nil,
                tokens: nil,
                kind: .scheduled,
                sourceKind: .codexAutomation,
                displayState: .scheduled,
                stateBasis: .scheduleConfig,
                nextRunAt: schedule.nextRunAt
            ))
        }

        return items.sorted { lhs, rhs in
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
        }
    }

    private func sortedTaskItems(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id < rhs.id
            }
        }
    }

    private func runSQLiteJSON(sqlitePath: String, dbPath: String, query: String) -> [[String: Any]] {
        let performanceSpan = PerformanceMonitor.shared.begin(.sqliteRead)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = ["-readonly", "-json", dbPath, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            PerformanceMonitor.shared.end(performanceSpan, success: false)
            return []
        }

        guard let data = readBoundedProcessOutput(
            output.fileHandleForReading,
            process: process,
            maximumBytes: 32 * 1_024 * 1_024
        ) else {
            PerformanceMonitor.shared.end(performanceSpan, success: false)
            return []
        }
        process.waitUntilExit()

        guard
            process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            PerformanceMonitor.shared.end(performanceSpan, success: false)
            return []
        }

        PerformanceMonitor.shared.end(performanceSpan)
        return json
    }

    private func readBoundedProcessOutput(
        _ handle: FileHandle,
        process: Process,
        maximumBytes: Int
    ) -> Data? {
        defer { try? handle.close() }
        var result = Data()
        while true {
            let chunk: Data
            do {
                guard let next = try handle.read(upToCount: 64 * 1_024),
                      !next.isEmpty else { break }
                chunk = next
            } catch {
                terminate(process)
                return nil
            }
            guard chunk.count <= maximumBytes,
                  result.count <= maximumBytes - chunk.count else {
                terminate(process)
                return nil
            }
            result.append(chunk)
        }
        return result
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func resolveCodexExecutablePath() -> String? {
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
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? 0) <= Self.maximumPersistentCacheBytes,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(LocalAnalyticsCacheEntry.self, from: data)
    }

    private func persistentSessionUsageCache() -> [String: SessionUsageCacheEntry] {
        if let cache = Self.persistentSessionUsageCache {
            return cache
        }

        guard let url = sessionUsageCacheURL(),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? 0) <= Self.maximumPersistentCacheBytes,
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
        guard entries.count > Self.persistentSessionUsageCacheLimit else { return entries }
        let retained = entries.sorted { lhs, rhs in
            let lhsDate = lhs.value.modificationDate ?? .distantPast
            let rhsDate = rhs.value.modificationDate ?? .distantPast
            return lhsDate == rhsDate ? lhs.key < rhs.key : lhsDate > rhsDate
        }.prefix(Self.persistentSessionUsageCacheLimit)
        return Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }

    private func releaseSessionUsageWorkingSet() {
        Self.sessionUsageCache.removeAll(keepingCapacity: false)
        Self.sessionUsageCacheOrder.removeAll(keepingCapacity: false)
        Self.persistentSessionUsageCache = nil
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
        var components: [String] = ["fork-prefix-v1", String(sources.count)]
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

private func tokenCounterSample(from usage: [String: Any]) -> CodexTokenCounterSample {
    CodexTokenCounterSample(
        inputTokens: int64Value(usage["input_tokens"]),
        cachedInputTokens: int64Value(usage["cached_input_tokens"]),
        outputTokens: int64Value(usage["output_tokens"]),
        reasoningOutputTokens: int64Value(usage["reasoning_output_tokens"]),
        totalTokens: int64Value(usage["total_tokens"])
    )
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

func estimateStaticTokens(_ text: String) -> Int64 {
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
        return ModelTokenPrice(model: "gpt-5.5-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.5") || normalized == "chat-latest" {
        return ModelTokenPrice(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.4-mini") {
        return ModelTokenPrice(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.4-nano") {
        return ModelTokenPrice(model: "gpt-5.4-nano", inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.4-pro") {
        return ModelTokenPrice(model: "gpt-5.4-pro", inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.4") {
        return ModelTokenPrice(model: "gpt-5.4", inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5.3-codex")
        || normalized.contains("gpt-5.2-codex")
        || normalized.contains("gpt-5.3-chat")
        || normalized.contains("gpt-5.2") {
        return ModelTokenPrice(model: "gpt-5.2-codex", inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14, usesReferencePricing: false)
    }
    if normalized.contains("gpt-5-codex") || normalized == "gpt-5" {
        return ModelTokenPrice(model: "gpt-5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10, usesReferencePricing: false)
    }

    return ModelTokenPrice(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30, usesReferencePricing: true)
}

func modelUsageUsesReferencePricing(_ model: String?) -> Bool {
    modelTokenPrice(for: model).usesReferencePricing
}

func normalizedModelUsageName(_ model: String?) -> String? {
    guard let model else { return nil }
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}

func applyTurnContextModel(_ turnContextModel: String?, to activeModel: inout String?) {
    activeModel = normalizedModelUsageName(turnContextModel)
}

func modelUsageIdentifier(for model: String?) -> String {
    normalizedModelUsageName(model)?.lowercased() ?? "unrecorded-model"
}

func resolvedModelUsageName(turnContextModel: String?, threadModel: String?) -> String? {
    normalizedModelUsageName(turnContextModel) ?? normalizedModelUsageName(threadModel)
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

enum PaletteSelectionResult: Equatable {
    case selected
    case unavailable
}

struct PaletteFallbackNotice: Equatable {
    let unavailableID: String
}

final class AppSettings: ObservableObject {
    private static let keepMainWindowOnTopKey = "codexU.keepMainWindowOnTop"
    private static let keepRunningWhenMainWindowClosedKey = "codexU.keepRunningWhenMainWindowClosed"
    private static let visibleRuntimeScopesKey = "codexU.visibleRuntimeScopes"
    private static let automaticUpdateChecksEnabledKey = "codexU.update.autoCheckEnabled"
    private static let skippedUpdateVersionKey = "codexU.update.skippedVersion"
    private static let paletteIDKey = "codexU.paletteID"

    private let defaults: UserDefaults
    let paletteCatalog: PaletteCatalog

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

    @Published var usageTrendWindow: UsageTrendWindow {
        didSet {
            usageTrendWindow.persist(defaults: defaults)
        }
    }

    @Published private(set) var paletteID: String
    @Published private(set) var paletteFallbackNotice: PaletteFallbackNotice?

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

    init(defaults: UserDefaults = .standard, paletteCatalog: PaletteCatalog = .loadFromMainBundle()) {
        self.defaults = defaults
        self.paletteCatalog = paletteCatalog
        let storedPaletteID = defaults.string(forKey: Self.paletteIDKey)
        if let storedPaletteID, paletteCatalog.contains(storedPaletteID) {
            paletteID = storedPaletteID
            paletteFallbackNotice = nil
        } else {
            paletteID = PaletteCatalog.defaultPaletteID
            paletteFallbackNotice = storedPaletteID.map(PaletteFallbackNotice.init(unavailableID:))
            defaults.set(PaletteCatalog.defaultPaletteID, forKey: Self.paletteIDKey)
        }
        language = WidgetLanguage.storedOrAutomatic(defaults: defaults)
        themeMode = WidgetThemeMode.storedOrAutomatic(defaults: defaults)
        particleAnimationMode = ParticleAnimationMode.storedOrDefault(defaults: defaults)
        usageTrendWindow = UsageTrendWindow.storedOrDefault(defaults: defaults)
        keepMainWindowOnTop = defaults.bool(forKey: Self.keepMainWindowOnTopKey)
        if defaults.object(forKey: Self.keepRunningWhenMainWindowClosedKey) == nil {
            keepRunningWhenMainWindowClosed = true
        } else {
            keepRunningWhenMainWindowClosed = defaults.bool(forKey: Self.keepRunningWhenMainWindowClosedKey)
        }
        if defaults.object(forKey: Self.automaticUpdateChecksEnabledKey) == nil {
            automaticUpdateChecksEnabled = true
        } else {
            automaticUpdateChecksEnabled = defaults.bool(forKey: Self.automaticUpdateChecksEnabledKey)
        }
        skippedUpdateVersion = defaults.string(forKey: Self.skippedUpdateVersionKey)
        visibleRuntimeScopes = Self.storedVisibleRuntimeScopes(defaults: defaults)
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
    func selectPalette(_ id: String) -> PaletteSelectionResult {
        guard paletteCatalog.contains(id) else {
            paletteFallbackNotice = PaletteFallbackNotice(unavailableID: id)
            return .unavailable
        }
        paletteID = id
        paletteFallbackNotice = nil
        defaults.set(id, forKey: Self.paletteIDKey)
        return .selected
    }

    func resetPalette() {
        _ = selectPalette(PaletteCatalog.defaultPaletteID)
    }

    func isRuntimeVisible(_ scope: RuntimeScope) -> Bool {
        visibleRuntimeScopes.contains(scope)
    }

    @discardableResult
    func setRuntime(_ scope: RuntimeScope, visible: Bool) -> Bool {
        if visible {
            visibleRuntimeScopes = Self.orderedRuntimeScopes(Set(visibleRuntimeScopes + [scope]))
            return true
        }
        guard visibleRuntimeScopes.count > 1 else {
            return false
        }
        visibleRuntimeScopes = visibleRuntimeScopes.filter { $0 != scope }
        return true
    }

    private static func storedVisibleRuntimeScopes(defaults: UserDefaults) -> [RuntimeScope] {
        guard let identifiers = defaults.array(forKey: visibleRuntimeScopesKey) as? [String] else {
            return RuntimeScope.allCases
        }
        let scopes = identifiers.compactMap(RuntimeScope.storedIdentifier)
        let ordered = orderedRuntimeScopes(Set(scopes))
        return ordered.isEmpty ? RuntimeScope.allCases : ordered
    }

    private static func orderedRuntimeScopes(_ scopes: Set<RuntimeScope>) -> [RuntimeScope] {
        RuntimeScope.allCases.filter { scopes.contains($0) }
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
    case leadership
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var selectedDashboardTab: DashboardTab = .tasks
    @State private var focusedThreadID: String?

    static let widgetDefaultWidth: CGFloat = 820
    static let widgetMinWidth: CGFloat = 820
    static let widgetMaxWidth: CGFloat = 1280
    static let widgetDefaultHeight: CGFloat = 720
    static let widgetMinHeight: CGFloat = 620
    static let windowCornerRadius: CGFloat = 18

    private var snapshot: UsageSnapshot { store.snapshot }
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
        .frame(
            minWidth: Self.widgetMinWidth,
            maxWidth: Self.widgetMaxWidth,
            minHeight: Self.widgetMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .appVisualEnvironment(
            catalog: settings.paletteCatalog,
            paletteID: settings.paletteID,
            appearance: PaletteAppearance(effectiveColorScheme)
        )
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(themeMode.preferredColorScheme)
        .readableForegroundHierarchy(effectiveColorScheme)
        .onAppear {
            themeMode.applyAppearance()
            store.setTaskBoardSelected(selectedDashboardTab == .tasks)
        }
        .onDisappear {
            store.setTaskBoardSelected(false)
        }
        .onChange(of: selectedDashboardTab) { tab in
            store.setTaskBoardSelected(tab == .tasks)
        }
        .onChange(of: store.taskFocusRequest) { request in
            guard let request else { return }
            selectedDashboardTab = .tasks
            focusedThreadID = request.threadID
            let requestID = request.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if store.taskFocusRequest?.id == requestID {
                    focusedThreadID = nil
                }
            }
        }
    }

    @ViewBuilder
    private var windowSurface: some View {
        staticWindowSurface(
            fill: FixedVisualPalette.windowScrim(
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
                        FixedVisualPalette.sectionStroke(
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
                    .fill(FixedVisualPalette.controlFill(effectiveColorScheme))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(FixedVisualPalette.controlStroke(effectiveColorScheme), lineWidth: 0.8)
                    )
            )
    }

    private var usageOverviewSection: some View {
        HStack(alignment: .top, spacing: 14) {
            LeadershipCommandRadiusButton(
                snapshot: store.multiRuntimeSnapshot.leadership,
                language: language,
                visualEnergyMode: store.visualEnergyMode
            ) {
                selectedDashboardTab = .leadership
            }
            .frame(width: 154)

            VStack(spacing: 8) {
                DualQuotaRing(
                    fiveHourQuota: snapshot.fiveHourQuota,
                    sevenDayQuota: snapshot.sevenDayQuota,
                    monthlyQuota: snapshot.monthlyQuota,
                    quotaReadSucceeded: snapshot.quotaReadSucceeded,
                    quotaIsStale: selectedQuotaIsStale,
                    language: language,
                    visualEnergyMode: store.visualEnergyMode,
                    animationMode: settings.particleAnimationMode
                )
                .frame(width: 145, height: 145)

                QuotaResetCompactSummary(
                    sevenDayQuota: snapshot.sevenDayQuota,
                    resetCredits: snapshot.credits?.resetCredits,
                    resetCreditDetails: snapshot.credits?.resetCreditDetails,
                    language: language
                )
                .frame(width: 154)
            }
            .zIndex(1)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    DetailedTokenMetricCard(
                        title: language.text("今日", "Today"),
                        systemName: "sun.max.fill",
                        usage: snapshot.local?.detailedUsage?.today,
                        fallbackTokens: snapshot.local?.todayTokens,
                        language: language
                    )
                    DetailedTokenMetricCard(
                        title: language.text("近 7 天", "Last 7 days"),
                        systemName: "calendar",
                        usage: snapshot.local?.detailedUsage?.sevenDay,
                        fallbackTokens: snapshot.local?.sevenDayTokens,
                        language: language
                    )
                    DetailedTokenMetricCard(
                        title: language.text("累计", "Lifetime"),
                        systemName: "sum",
                        usage: snapshot.local?.detailedUsage?.lifetime,
                        fallbackTokens: snapshot.local?.lifetimeTokens,
                        language: language
                    )
                }

                WoolProgressCard(usage: snapshot.local?.detailedUsage?.month, language: language)
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
        case .leadership:
            LeadershipDashboardPanel(
                snapshot: store.multiRuntimeSnapshot.leadership,
                language: language
            )
        case .usage:
            UsageTrendPanel(
                trend: snapshot.local?.usageTrend,
                runtimeScope: store.selectedRuntimeScope,
                language: language,
                window: $settings.usageTrendWindow
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
                TaskBoardColumnView(
                    column: column,
                    runtimeScope: store.selectedRuntimeScope,
                    language: language,
                    focusedThreadID: focusedThreadID,
                    onOpenSession: { threadID in
                        CodexSessionOpener.open(threadID: threadID)
                    }
                )
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
                .help(dataTrustHelp)
            if let shortcut = settings.globalShortcut {
                Text(shortcut.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dataTrustHelp: String {
        guard let runtime = store.runtimeSnapshot(for: store.selectedRuntimeScope) else {
            return language.text("数据暂不可用", "Data unavailable")
        }
        let status = runtime.status.localized(language)
        return language.text(
            "状态：\(status)\n额度：\(runtime.quotaSourceLabel)\n用量：\(runtime.usageSourceLabel)\n最后成功刷新：\(timeOnly(snapshot.refreshedAt, language: language))",
            "Status: \(status)\nQuota: \(runtime.quotaSourceLabel)\nUsage: \(runtime.usageSourceLabel)\nLast refresh: \(timeOnly(snapshot.refreshedAt, language: language))"
        )
    }

    private var taskBoardSummary: String {
        guard let board = snapshot.taskBoard else { return language.text("读取中", "Loading") }
        return language.text(
            "\(board.totalCount) 事项 · \(timeOnly(board.refreshedAt, language: language))",
            "\(board.totalCount) items · \(timeOnly(board.refreshedAt, language: language))"
        )
    }

    private var dashboardSummary: String {
        switch selectedDashboardTab {
        case .tasks:
            return taskBoardSummary
        case .leadership:
            guard let report = store.multiRuntimeSnapshot.leadership.defaultReport else {
                return language.text("正在建立记录", "Building history")
            }
            let score = report.score.map(String.init) ?? "--"
            return language.text(
                "Score \(score) · \(report.activeDayCount)/28 活跃日",
                "Score \(score) · \(report.activeDayCount)/28 active days"
            )
        case .usage:
            guard let trend = snapshot.local?.usageTrend else { return language.text("读取中", "Loading") }
            let quality = trend.sourceQuality == .approximate ? language.text("粗略统计", "Approx.") : language.text("精细统计", "Detailed")
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

    private var taskBoardColumns: [TaskColumn] {
        snapshot.taskBoard?.columns ?? [
            TaskColumn(id: .active, title: localizedTaskColumnTitle(.active, runtimeScope: store.selectedRuntimeScope, language: language), count: 0, items: []),
            TaskColumn(id: .pending, title: localizedTaskColumnTitle(.pending, runtimeScope: store.selectedRuntimeScope, language: language), count: 0, items: []),
            TaskColumn(id: .scheduled, title: localizedTaskColumnTitle(.scheduled, runtimeScope: store.selectedRuntimeScope, language: language), count: 0, items: []),
            TaskColumn(id: .done, title: localizedTaskColumnTitle(.done, runtimeScope: store.selectedRuntimeScope, language: language), count: 0, items: [])
        ]
    }

    private var shouldShowEnvironmentChecklist: Bool {
        if snapshot.messages.contains("正在读取 codexU 数据") { return false }
        let quotaUnavailable = snapshot.fiveHourQuota == nil
            && snapshot.sevenDayQuota == nil
            && snapshot.monthlyQuota == nil
        let hasQuotaProtocolWarning = snapshot.messages.contains { $0.contains("额度窗口") }
        return (!snapshot.messages.isEmpty && (quotaUnavailable || hasQuotaProtocolWarning || snapshot.local == nil))
            || snapshot.account == nil
            || snapshot.local == nil
    }

    private var environmentDiagnostics: [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        let messages = snapshot.messages.joined(separator: "\n")

        if store.selectedRuntimeScope == .claudeCode {
            if snapshot.fiveHourQuota == nil || snapshot.sevenDayQuota == nil {
                let isStale = messages.contains("快照已过期")
                items.append(DiagnosticItem(
                    id: isStale ? "claude-statusline-stale" : "claude-statusline-missing",
                    title: isStale
                        ? language.text("Claude Code 快照已过期", "Claude Code snapshot is stale")
                        : language.text("额度需要 Claude Code active session 快照", "Quota needs a Claude Code active session snapshot"),
                    detail: isStale
                        ? language.text("打开 Claude Code 后刷新；本机 token 统计仍可继续显示。", "Open Claude Code and refresh. Local token stats can still be shown.")
                        : language.text("首版只读取本地 statusLine 快照；没有快照时 5 小时和 7 日额度显示为 --。", "This version only reads a local statusLine snapshot. 5-hour and 7-day quota show -- without it."),
                    systemName: isStale ? "clock.badge.exclamationmark" : "waveform.path.ecg",
                    tint: isStale ? FixedVisualPalette.statusInfo : FixedVisualPalette.statusWarning
                ))
            }

            if snapshot.local == nil || snapshot.local?.detailedUsage == nil {
                items.append(DiagnosticItem(
                    id: "claude-local-usage",
                    title: language.text("暂无 Claude Code 本机用量记录", "No local Claude Code usage records yet"),
                    detail: language.text("本机 token 统计来自 ~/.claude/projects 下的 transcript JSONL，只读取 usage 和工具名称等结构化字段。", "Local token stats come from transcript JSONL under ~/.claude/projects and only read structured usage and tool names."),
                    systemName: "doc.text.magnifyingglass",
                    tint: FixedVisualPalette.statusInfo
                ))
            }

            if items.isEmpty {
                items = snapshot.messages.prefix(3).enumerated().map { index, message in
                    DiagnosticItem(
                        id: "claude-message-\(index)",
                        title: language.text("运行提示", "Runtime note"),
                        detail: localizedReaderMessage(message, language: language),
                        systemName: "info.circle.fill",
                        tint: FixedVisualPalette.statusInfo
                    )
                }
            }

            return items
        }

        if (snapshot.fiveHourQuota == nil
            && snapshot.sevenDayQuota == nil
            && snapshot.monthlyQuota == nil) || snapshot.account == nil {
            if messages.contains("未找到 codex") {
                items.append(DiagnosticItem(
                    id: "codex-missing",
                    title: language.text("未找到 Codex", "Codex not found"),
                    detail: language.text("请先安装 ChatGPT/Codex App，或确认 codex CLI 位于标准安装目录。", "Install the ChatGPT/Codex app first, or make sure the codex CLI is in a standard installation directory."),
                    systemName: "magnifyingglass",
                    tint: FixedVisualPalette.statusWarning
                ))
            } else if messages.contains("app-server") {
                items.append(DiagnosticItem(
                    id: "app-server",
                    title: language.text("Codex 账户接口暂不可用", "Codex account API unavailable"),
                    detail: language.text("确认 Codex 已登录后点击刷新；本机 token 统计仍可继续显示。", "Make sure Codex is signed in, then refresh. Local token stats can still be shown."),
                    systemName: "exclamationmark.triangle.fill",
                    tint: FixedVisualPalette.statusWarning
                ))
            } else {
                items.append(DiagnosticItem(
                    id: "quota-unavailable",
                    title: language.text("账户额度读取中", "Reading account quota"),
                    detail: language.text("如果长时间无数据，请确认 Codex 已安装并完成登录。", "If data does not appear, make sure Codex is installed and signed in."),
                    systemName: "person.crop.circle.badge.questionmark",
                    tint: FixedVisualPalette.statusInfo
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
                    tint: FixedVisualPalette.statusWarning
                ))
            } else if messages.contains("sqlite3") {
                items.append(DiagnosticItem(
                    id: "sqlite-cli",
                    title: language.text("未找到 sqlite3", "sqlite3 not found"),
                    detail: language.text("请安装 macOS Command Line Tools，或通过 Homebrew 安装 sqlite。", "Install macOS Command Line Tools, or install sqlite with Homebrew."),
                    systemName: "terminal",
                    tint: FixedVisualPalette.statusWarning
                ))
            } else {
                items.append(DiagnosticItem(
                    id: "local-usage",
                    title: language.text("本机统计暂不可用", "Local stats unavailable"),
                    detail: language.text("本机 token 和任务看板依赖 ~/.codex 的本地状态文件。", "Local tokens and the task board depend on Codex state files under ~/.codex."),
                    systemName: "chart.bar.doc.horizontal",
                    tint: FixedVisualPalette.statusInfo
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
                    tint: FixedVisualPalette.statusInfo
                )
            }
        }

        return items
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
    @Environment(\.visualTokens) private var visualTokens
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
            return visualTokens.selection.foreground.color
        }
        if isHovering, let hoverTint {
            return hoverTint
        }
        return Color.secondary
    }

    private var fillColor: Color {
        if isActive {
            return visualTokens.selection.fill.color
        }
        if isHovering {
            return FixedVisualPalette.controlSelectedFill(colorScheme)
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
                            isActive ? visualTokens.selection.stroke.color : Color.clear,
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
                    .fill(FixedVisualPalette.controlFill(effectiveColorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(FixedVisualPalette.controlStroke(effectiveColorScheme), lineWidth: 0.8)
                    )
            )
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topTrailing)
        .appVisualEnvironment(
            catalog: settings.paletteCatalog,
            paletteID: settings.paletteID,
            appearance: PaletteAppearance(effectiveColorScheme)
        )
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(themeMode.preferredColorScheme)
        .readableForegroundHierarchy(effectiveColorScheme)
    }
}

struct SettingsPanelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: AppUpdateStore
    let onOpenPaletteLibrary: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var language: WidgetLanguage { settings.language }

    var body: some View {
        ZStack {
            LiquidGlassWindowBackdrop(colorScheme: colorScheme)

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
                            width: settingsAccessoryColumnWidth
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
                            width: settingsAccessoryColumnWidth
                        )
                    }

                    SettingsPickerRow(
                        title: language.text("配色", "Color palette"),
                        detail: language.text("精选内置配色，同时适配浅色与深色", "Curated palettes for both Light and Dark appearances")
                    ) {
                        PaletteSettingsView(settings: settings, onOpenLibrary: onOpenPaletteLibrary)
                            .frame(width: settingsAccessoryColumnWidth)
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
                            width: settingsAccessoryColumnWidth
                        )
                    }
                }

                settingsSection(
                    title: "Runtime",
                    detail: language.text("展示范围", "Display")
                ) {
                    SettingsPickerRow(
                        title: language.text("展示 Runtime", "Visible runtimes"),
                        detail: language.text("主窗口和菜单栏浮窗中的 Runtime 范围", "Runtime scope in the main window and menu popover")
                    ) {
                        SettingsRuntimeMultiSelectControl(
                            selectedScopes: settings.visibleRuntimeScopes,
                            language: language
                        ) { scope in
                            settings.setRuntime(scope, visible: !settings.isRuntimeVisible(scope))
                        }
                        .help(runtimeSelectionHelp)
                        .accessibilityLabel(language.text("展示 Runtime", "Visible runtimes"))
                        .accessibilityValue(
                            settings.visibleRuntimeScopes
                                .map(\.displayName)
                                .joined(separator: ", ")
                        )
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
                            width: settingsAccessoryColumnWidth
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
                            .controlSize(.small)
                            .frame(
                                width: settingsAccessoryColumnWidth,
                                height: settingsControlVisualHeight
                            )
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
                                height: settingsControlVisualHeight
                            )

                            Button {
                                settings.resetGlobalShortcut()
                            } label: {
                                Text(language.text("恢复默认", "Restore Default"))
                                    .font(.system(size: settingsControlFontSize, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                    .frame(
                                        width: settingsShortcutActionWidth,
                                        height: settingsControlVisualHeight
                                    )
                            }
                            .buttonStyle(.borderless)
                            .disabled(
                                settings.globalShortcut == .default
                                    && settings.globalShortcutError == nil
                            )
                        }
                        .frame(width: settingsAccessoryColumnWidth, alignment: .trailing)
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
                .padding(.horizontal, 20)
                .padding(.top, settingsContentTopInset)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 480, alignment: .topLeading)
        .appVisualEnvironment(
            catalog: settings.paletteCatalog,
            paletteID: settings.paletteID,
            appearance: PaletteAppearance(colorScheme)
        )
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
            SettingsSectionTitle(title: title, detail: detail)
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
            "点击切换展示范围；至少需要保留一个 Runtime",
            "Click to change visibility; at least one runtime must stay visible"
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

private struct SettingsSectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: settingsSectionTitleFontSize, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(detail)
                .font(.system(size: settingsSectionDetailFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
    @Environment(\.visualTokens) private var visualTokens
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
                        .font(.system(size: settingsControlFontSize, weight: selection == option.value ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selection == option.value ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: settingsSegmentHeight)
                        .background(
                            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                                .fill(selection == option.value ? visualTokens.accent.primary.color : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])

                if index < options.count - 1 {
                    Rectangle()
                        .fill(FixedVisualPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: width, height: settingsControlVisualHeight)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous))
    }
}

struct SettingsRuntimeMultiSelectControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let selectedScopes: [RuntimeScope]
    let language: WidgetLanguage
    let onToggle: (RuntimeScope) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(RuntimeScope.allCases.enumerated()), id: \.element.id) { index, scope in
                Button {
                    onToggle(scope)
                } label: {
                    HStack(spacing: 6) {
                        RuntimeLogoView(scope: scope, size: 16)
                        Text(label(for: scope))
                            .font(.system(size: settingsControlFontSize, weight: isSelected(scope) ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(isSelected(scope) ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: settingsSegmentHeight)
                    .background(
                        RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                            .fill(isSelected(scope) ? visualTokens.accent.primary.color : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: scope))
                .accessibilityValue(isSelected(scope) ? language.text("已选择", "Selected") : language.text("未选择", "Not selected"))

                if index < RuntimeScope.allCases.count - 1 {
                    Rectangle()
                        .fill(FixedVisualPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: settingsAccessoryColumnWidth, height: settingsControlVisualHeight)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous))
    }

    private func isSelected(_ scope: RuntimeScope) -> Bool {
        selectedScopes.contains(scope)
    }

    private func label(for scope: RuntimeScope) -> String {
        switch scope {
        case .codex:
            return "Codex"
        case .claudeCode:
            return language.text("Claude Code", "Claude Code")
        }
    }
}

struct SettingsSwitchToggle: View {
    @Environment(\.visualTokens) private var visualTokens
    let isOn: Binding<Bool>
    var isDisabled = false
    var help: String?

    var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.regular)
            .tint(visualTokens.accent.primary.color)
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
                .font(.system(size: settingsControlFontSize, weight: .semibold, design: .rounded))
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
                .foregroundStyle(FixedVisualPalette.statusDanger)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: settingsRowTitleFontSize, weight: .semibold))
                    .foregroundStyle(FixedVisualPalette.statusDanger)
                Text(message)
                    .font(.system(size: settingsRowDetailFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentValue)
                    .font(.system(size: settingsRowDetailFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.statusDangerFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: settingsControlCornerRadius, style: .continuous)
                        .strokeBorder(FixedVisualPalette.statusDangerStroke(colorScheme), lineWidth: 0.8)
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
                    .font(.system(size: settingsRowTitleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: settingsRowDetailFontSize, weight: .regular))
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
                            .fill(selectedTab == tab ? FixedVisualPalette.controlSelectedFill(colorScheme) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedDashboardTabLabel(tab, language: language))

                if index < DashboardTab.allCases.count - 1 {
                    Rectangle()
                        .fill(FixedVisualPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FixedVisualPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(language.text("切换今日任务、AI 领导力、用量趋势和项目排行", "Switch between tasks, AI leadership, usage, and project rankings"))
        .accessibilityElement(children: .contain)
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
                        FixedVisualPalette.sectionFill(
                            colorScheme,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                FixedVisualPalette.sectionStroke(
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
                        FixedVisualPalette.cardFill(
                            colorScheme,
                            elevated: elevated,
                            reduceTransparency: reduceTransparency
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                FixedVisualPalette.cardStroke(
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
            FixedVisualPalette.secondaryText(colorScheme),
            FixedVisualPalette.tertiaryText(colorScheme)
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
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        ZStack {
            Circle()
                .stroke(FixedVisualPalette.surfaceTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: available ? CGFloat(max(0, min(1, percent / 100))) : 0.0)
                .stroke(
                    AngularGradient(
                        colors: [
                            visualTokens.accent.primary.color,
                            visualTokens.accent.primaryLight.color,
                            visualTokens.accent.highlight.color,
                            visualTokens.accent.primary.color
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

private extension QuotaWindowKind {
    var compactTitle: String {
        switch self {
        case .fiveHour: "5h"
        case .sevenDay: "7d"
        case .monthly: "mo"
        }
    }
}

private extension QuotaPaletteRole {
    func tokens(in visualTokens: ResolvedVisualTokens) -> QuotaRoleTokenSet {
        switch self {
        case .primary: visualTokens.quota.primary
        case .secondary: visualTokens.quota.secondary
        }
    }

    var ringAssetSlot: PaletteAssetSlot {
        switch self {
        case .primary: .quotaRingPrimary
        case .secondary: .quotaRingSecondary
        }
    }

    var capAssetSlot: PaletteAssetSlot {
        switch self {
        case .primary: .quotaCapPrimary
        case .secondary: .quotaCapSecondary
        }
    }
}

private enum QuotaRingPosition: Equatable {
    case outer
    case inner
}

private struct QuotaRingItem: Identifiable, Equatable {
    let kind: QuotaWindowKind
    let window: RateWindow
    let paletteRole: QuotaPaletteRole
    let position: QuotaRingPosition

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

    init(fiveHourQuota: RateWindow?, sevenDayQuota: RateWindow?, monthlyQuota: RateWindow?) {
        var windows: [(QuotaWindowKind, RateWindow)] = []
        if let fiveHourQuota {
            windows.append((.fiveHour, fiveHourQuota))
        }
        if let sevenDayQuota {
            windows.append((.sevenDay, sevenDayQuota))
        }
        if let monthlyQuota {
            windows.append((.monthly, monthlyQuota))
        }
        let activeKinds = Set(windows.map(\.0))
        self.items = windows.enumerated().map { index, entry in
            QuotaRingItem(
                kind: entry.0,
                window: entry.1,
                paletteRole: QuotaPaletteRoleResolver.role(
                    for: entry.0,
                    activeKinds: activeKinds
                ),
                position: index == 0 ? .outer : .inner
            )
        }
    }

    var topology: Topology {
        switch items.count {
        case 0: return .none
        case 1: return .single
        default: return .dual
        }
    }

    var particleLanes: [QuotaParticleLane] {
        switch topology {
        case .none:
            return []
        case .single:
            return items.prefix(1).map {
                QuotaParticleLane(
                    radius: QuotaRingGeometry.outerRadius,
                    progress: $0.particleProgress,
                    maximumCount: 17,
                    phaseOffset: 0
                )
            }
        case .dual:
            return [
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
        guard topology == .dual, item.position == .inner else {
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
    let monthlyQuota: RateWindow?
    let quotaReadSucceeded: Bool
    let quotaIsStale: Bool
    let language: WidgetLanguage
    let visualEnergyMode: VisualEnergyMode
    let animationMode: ParticleAnimationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visualTokens) private var visualTokens
    @State private var isPointerOverRing = false

    private var presentation: QuotaRingPresentation {
        QuotaRingPresentation(
            fiveHourQuota: fiveHourQuota,
            sevenDayQuota: sevenDayQuota,
            monthlyQuota: monthlyQuota
        )
    }

    var body: some View {
        ZStack {
            ForEach(presentation.items) { item in
                QuotaRingSegment(
                    percent: item.window.remainingPercent,
                    tokens: item.paletteRole.tokens(in: visualTokens),
                    ringAsset: visualTokens.assets[item.paletteRole.ringAssetSlot],
                    capAsset: visualTokens.assets[item.paletteRole.capAssetSlot],
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
                    .fill(FixedVisualPalette.surfaceTrack)
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
                    .fill(FixedVisualPalette.surfaceTrack)
                    .frame(
                        width: QuotaRingGeometry.dualCenterDiameter,
                        height: QuotaRingGeometry.dualCenterDiameter
                    )
                VStack(spacing: 4) {
                    ForEach(presentation.items) { item in
                        QuotaRingLabel(
                            title: item.kind.compactTitle,
                            value: item.remainingText,
                            color: item.paletteRole.tokens(in: visualTokens).label.color
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

            VStack(spacing: 0) {
                OverviewVisualHeader(
                    title: language.text("用量", "Usage"),
                    systemName: nil,
                    badge: nil
                )
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    let tokens: QuotaRoleTokenSet
    let ringAsset: PaletteAssetDescriptor?
    let capAsset: PaletteAssetDescriptor?
    let lineWidth: CGFloat

    var body: some View {
        let progress = CGFloat(max(0, min(1, percent / 100)))
        ZStack {
            Circle()
                .strokeBorder(tokens.track.color, lineWidth: lineWidth)

            if progress > 0.001 {
                if let ringAsset {
                    PaletteRingArtwork(descriptor: ringAsset, progress: progress, lineWidth: lineWidth)
                } else {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                colors: [tokens.start.color, tokens.end.color],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(max(1, Double(progress) * 360))
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                if let capAsset {
                    PaletteRingCap(descriptor: capAsset, progress: progress, lineWidth: lineWidth)
                }
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
            particle.backgroundColor = FixedVisualPalette.dataFlowParticle.cgColor
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
        let fullMonthly = quotaWindow(usedPercent: 0, durationMins: 43_800)
        let noQuotaPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: nil,
            monthlyQuota: nil
        )
        let fiveHourOnlyPresentation = QuotaRingPresentation(
            fiveHourQuota: fullFiveHour,
            sevenDayQuota: nil,
            monthlyQuota: nil
        )
        let sevenDayOnlyPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: fullSevenDay,
            monthlyQuota: nil
        )
        let monthlyOnlyPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: nil,
            monthlyQuota: fullMonthly
        )
        let dualPresentation = QuotaRingPresentation(
            fiveHourQuota: fullFiveHour,
            sevenDayQuota: fullSevenDay,
            monthlyQuota: nil
        )
        let bothLongPresentation = QuotaRingPresentation(
            fiveHourQuota: nil,
            sevenDayQuota: fullSevenDay,
            monthlyQuota: fullMonthly
        )

        expect(noQuotaPresentation.topology == .none, "zero quota windows should use the empty presentation")
        expect(noQuotaPresentation.items.isEmpty, "empty presentation should not expose reset rows")
        expect(noQuotaPresentation.particleLanes.isEmpty, "empty presentation should not expose particle lanes")
        expect(fiveHourOnlyPresentation.topology == .single, "5h-only quota should use a single ring")
        expect(
            fiveHourOnlyPresentation.items.map(\.kind) == [.fiveHour],
            "5h-only presentation should preserve the 5h semantic"
        )
        expect(sevenDayOnlyPresentation.topology == .single, "7d-only quota should use a single ring")
        expect(
            sevenDayOnlyPresentation.items.map(\.kind) == [.sevenDay],
            "7d-only presentation should preserve the 7d semantic"
        )
        expect(
            sevenDayOnlyPresentation.items.map(\.paletteRole) == [.secondary],
            "7d-only presentation must preserve the quota.secondary identity"
        )
        expect(
            monthlyOnlyPresentation.items.map(\.paletteRole) == [.secondary],
            "monthly-only presentation should use the documented secondary fallback"
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
            dualPresentation.items.map(\.paletteRole) == [.primary, .secondary],
            "5h and 7d must preserve their Palette Package semantic identities"
        )
        expect(
            bothLongPresentation.items.map(\.kind) == [.sevenDay, .monthly]
                && bothLongPresentation.items.map(\.paletteRole) == [.secondary, .primary]
                && bothLongPresentation.items.map(\.position) == [.outer, .inner],
            "7d should remain secondary while monthly uses the free primary fallback independent of ring geometry"
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
                && monthlyOnlyPresentation.items.count == 1
                && dualPresentation.items.count == 2
                && bothLongPresentation.items.count == 2,
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
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        VStack(spacing: 1) {
            Text(item.kind.compactTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(item.paletteRole.tokens(in: visualTokens).label.color)
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
        ZStack {
            OverviewPlaceholderGlyph(systemName: isAuthoritative ? "infinity" : "percent")
            Text(
                isAuthoritative
                    ? language.text("当前无额度限制", "No active quota limits")
                    : language.text("暂无额度数据", "No quota data")
            )
                .font(.system(size: 10, weight: .semibold))
                .offset(y: 35)
        }
        .foregroundStyle(.secondary)
        .frame(
            width: QuotaRingGeometry.singleCenterDiameter,
            height: QuotaRingGeometry.singleCenterDiameter
        )
        .accessibilityElement(children: .combine)
    }
}

private struct QuotaResetCompactSummary: View {
    let sevenDayQuota: RateWindow?
    let resetCredits: Int?
    let resetCreditDetails: [ResetCreditDetail]?
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 4) {
            OverviewFactTile(
                systemName: "calendar.badge.clock",
                value: sevenDayResetValue,
                label: language.text("7d 重置", "7d reset")
            )
            .help(sevenDayResetHelp)

            OverviewFactTile(
                systemName: "arrow.counterclockwise.circle.fill",
                value: resetCredits.map(String.init) ?? "--",
                label: language.text("可用重置", "Resets")
            )
            .help(resetCreditHelp)
        }
        .accessibilityElement(children: .contain)
    }

    private var sevenDayResetValue: String {
        guard let resetsAt = sevenDayQuota?.resetsAt else { return "--" }
        return resetDateTime(resetsAt, language: language)
    }

    private var sevenDayResetHelp: String {
        guard let resetsAt = sevenDayQuota?.resetsAt else {
            return language.text("7d 重置时间暂不可用", "7d reset time is unavailable")
        }
        let value = resetDateTime(resetsAt, language: language)
        return language.text("7d 额度将在 \(value) 重置", "7d quota resets at \(value)")
    }

    private var resetCreditHelp: String {
        guard let count = resetCredits else {
            return language.text("可用重置次数暂不可用", "Available reset count is unavailable")
        }

        var lines = [language.text("可用重置次数：\(count)", "Available resets: \(count)")]
        let details = Array((resetCreditDetails ?? []).prefix(max(count, 0)))
        for (index, detail) in details.enumerated() {
            let value: String
            if let expiresAt = detail.expiresAt {
                value = language.text(
                    "\(resetDateTime(expiresAt, language: language)) 到期",
                    "Expires \(resetDateTime(expiresAt, language: language))"
                )
            } else {
                value = language.text("未提供到期时间", "Expiry unavailable")
            }
            lines.append(language.text("第 \(index + 1) 次：\(value)", "Reset \(index + 1): \(value)"))
        }
        if count > details.count {
            let missing = count - details.count
            lines.append(language.text("其余 \(missing) 次：未提供到期时间", "Other \(missing): expiry unavailable"))
        }
        return lines.joined(separator: "\n")
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
    @Environment(\.visualTokens) private var visualTokens

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
                    .fill(FixedVisualPalette.surfaceTrack)
                    .frame(height: 58)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bucket.tokens == 0 ? visualTokens.data.zero.color : visualTokens.data.series[0].color.opacity(bucket.label == "今天" ? 1 : 0.58))
                    .frame(height: barHeight)
                    .overlay {
                        if bucket.tokens > 0, let asset = visualTokens.assets[.chartBar] {
                            PaletteAssetFill(descriptor: asset)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
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
    let language: WidgetLanguage
    @Environment(\.visualTokens) private var visualTokens

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
                            .fill(FixedVisualPalette.surfaceTrack)
                    )
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(formatUSD(usage?.estimatedCostUSD))
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
                    color: visualTokens.data.tokenInput.color
                )
                TokenSplitLegendRow(
                    title: language.text("缓存", "Cached"),
                    value: usage?.tokens.billableCachedInputTokens,
                    color: visualTokens.data.tokenCached.color
                )
                TokenSplitLegendRow(
                    title: language.text("输出", "Output"),
                    value: usage?.tokens.outputTokens,
                    color: visualTokens.data.tokenOutput.color
                )
            }
        }
        .padding(dashboardCardPadding)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .cardBackground(cornerRadius: dashboardCardCornerRadius)
    }
}

struct TokenSplitBar: View {
    let tokens: TokenBreakdown?
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        GeometryReader { geometry in
            let splitTotal = tokens?.splitTotalTokens ?? 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FixedVisualPalette.surfaceTrack)

                if let tokens, splitTotal > 0 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(visualTokens.data.tokenInput.color)
                            .frame(width: segmentWidth(tokens.uncachedInputTokens, total: splitTotal, available: geometry.size.width))
                        Rectangle()
                            .fill(visualTokens.data.tokenCached.color)
                            .frame(width: segmentWidth(tokens.billableCachedInputTokens, total: splitTotal, available: geometry.size.width))
                        Rectangle()
                            .fill(visualTokens.data.tokenOutput.color)
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
}

private let subscriptionMilestones: [SubscriptionMilestone] = [
    SubscriptionMilestone(id: "plus", title: "Plus", amountUSD: 20),
    SubscriptionMilestone(id: "pro100", title: "Pro100", amountUSD: 100),
    SubscriptionMilestone(id: "pro200", title: "Pro200", amountUSD: 200)
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

struct WoolProgressCard: View {
    let usage: PricedTokenUsage?
    let language: WidgetLanguage
    @Environment(\.visualTokens) private var visualTokens

    private var cost: Double {
        usage?.estimatedCostUSD ?? 0
    }

    private var maxValue: Double {
        max(quotaValueMonthlyMaxUSD, subscriptionMilestones.map(\.amountUSD).max() ?? 200)
    }

    private var accent: Color {
        if cost >= 200 { return visualTokens.data.milestones[2].color }
        if cost >= 100 { return visualTokens.data.milestones[1].color }
        if cost >= 20 { return visualTokens.data.milestones[0].color }
        return FixedVisualPalette.statusWarning
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
                            .fill(milestoneColor(milestone))
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

    private func milestoneColor(_ milestone: SubscriptionMilestone) -> Color {
        let index = subscriptionMilestones.firstIndex(where: { $0.id == milestone.id }) ?? 0
        return visualTokens.data.milestones[min(index, visualTokens.data.milestones.count - 1)].color
    }
}

struct QuotaValueProgressBar: View {
    let currentValue: Double
    let maxValue: Double
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = valueOffset(currentValue, width: width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(FixedVisualPalette.surfaceTrack)
                    .frame(height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: visualTokens.data.valueProgress.map(\.color), startPoint: .leading, endPoint: .trailing))
                    .frame(width: currentValue > 0 ? max(5, progressWidth) : 0, height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .overlay {
                        if let asset = visualTokens.assets[.progressLinear], currentValue > 0 {
                            PaletteAssetFill(descriptor: asset)
                                .frame(width: max(5, progressWidth), height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                ForEach(subscriptionMilestones) { milestone in
                    let x = valueOffset(milestone.amountUSD, width: width)
                    Circle()
                        .fill(milestoneColor(milestone))
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

    private func milestoneColor(_ milestone: SubscriptionMilestone) -> Color {
        let index = subscriptionMilestones.firstIndex(where: { $0.id == milestone.id }) ?? 0
        return visualTokens.data.milestones[min(index, visualTokens.data.milestones.count - 1)].color
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
    @Environment(\.visualTokens) private var visualTokens

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
                        .fill(bucket.tokens == 0 ? visualTokens.data.zero.color : visualTokens.data.series[0].color.opacity(bucket.label == "今天" ? 1 : 0.55))
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
    var prefersOpaqueSurface = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Text(payload.title)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            VStack(spacing: compact ? 2 : 4) {
                ForEach(payload.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
                        Text(row.label)
                            .font(.system(size: compact ? 8 : 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.78 : 1)
                        Spacer(minLength: compact ? 6 : 8)
                        Text(row.value)
                            .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.72 : 0.78)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 8 : 9)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    prefersOpaqueSurface
                        ? FixedVisualPalette.tooltipFill(colorScheme)
                        : FixedVisualPalette.cardFill(colorScheme, elevated: true)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(FixedVisualPalette.cardStroke(colorScheme, elevated: true), lineWidth: 0.9)
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
        return ChartTooltipPayload(
            title: title,
            rows: [
                ChartTooltipRow(id: "runtime", label: "Runtime", value: runtimeScope.displayName),
                ChartTooltipRow(id: "total", label: language.text("总量", "Total"), value: "0 tokens"),
                ChartTooltipRow(id: "status", label: language.text("状态", "Status"), value: language.text("无本机记录", "No local records")),
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
    @Binding var window: UsageTrendWindow

    var body: some View {
        if let trend {
            VStack(alignment: .leading, spacing: usageTrendCardSpacing) {
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
                        if showsModelAttribution(for: trend) {
                            ModelActivityOverviewCard(
                                trend: trend,
                                language: language,
                                window: window
                            )
                                .frame(
                                    width: usageTrendSevenDayCardWidth(
                                        containerWidth: geometry.size.width,
                                        weekCount: trend.heatmapWeeks.count
                                    ),
                                    height: usageTrendCardHeight,
                                    alignment: .topLeading
                                )
                        } else {
                            UsageSevenDaySummaryCard(
                                trend: trend,
                                runtimeScope: runtimeScope,
                                language: language
                            )
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
                }
                .frame(height: usageTrendCardHeight)

                if showsModelAttribution(for: trend) {
                    ModelUsageAreaChartCard(
                        trend: trend,
                        runtimeScope: runtimeScope,
                        language: language,
                        window: $window
                    )
                        .frame(height: usageTrendAreaChartHeight)
                }
            }
            .frame(height: usageTrendPanelHeight(showsModelAreaChart: showsModelAttribution(for: trend)))
        } else {
            AnalyticsEmptyState(
                systemName: "chart.bar.doc.horizontal",
                title: language.text("暂无用量趋势", "No usage trend"),
                detail: language.text("完成一次 Codex 会话后，这里会显示最近半年的每日 token 热力图和模型趋势。", "After one Codex session, this panel shows a daily token heatmap and model trend for the last six months.")
            )
        }
    }

    private func showsModelAttribution(for trend: UsageTrend) -> Bool {
        runtimeScope == .codex && trend.modelTrends != nil
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
        if trend.summary.isNewActivity { return FixedVisualPalette.statusSuccess }
        guard let change = trend.summary.changePercent else { return FixedVisualPalette.statusNeutral }
        return change >= 0 ? FixedVisualPalette.statusSuccess : FixedVisualPalette.statusWarning
    }
}

struct SevenDayLineChart: View {
    let buckets: [UsageDayBucket]
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    @State private var hoveredBucket: UsageDayBucket?
    @State private var hoverAnchor: CGPoint = .zero
    @Environment(\.visualTokens) private var visualTokens

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
                                .fill(FixedVisualPalette.surfaceTrack.opacity(0.45))
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
                        visualTokens.data.series[1].color,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(buckets[index].tokens > 0 ? visualTokens.data.series[1].color : FixedVisualPalette.surfaceTrack)
                            .frame(width: hoveredBucket?.id == buckets[index].id ? 8 : 6, height: hoveredBucket?.id == buckets[index].id ? 8 : 6)
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

struct ModelUsageAreaChartCard: View {
    let trend: UsageTrend
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    @Binding var window: UsageTrendWindow
    @State private var metric: UsageTrendMetric = .tokens
    @Environment(\.visualTokens) private var visualTokens

    private var series: [ModelUsageAreaSeries] {
        ModelUsageAreaSeriesBuilder.build(from: trend, window: window)
    }

    private var totalBuckets: [UsageDayBucket] {
        ModelUsageAreaSeriesBuilder.dateBuckets(from: trend, window: window)
    }

    private var colorMap: ModelUsageSeriesColorMap {
        ModelUsageSeriesColorMap(series: series, visualTokens: visualTokens)
    }

    private var costAvailable: Bool {
        trend.sourceQuality == .detailed && trend.dayBuckets.contains { bucket in
            bucket.tokens > 0 && bucket.usage.estimatedCostUSD > 0
        }
    }

    private var usesReferencePricing: Bool {
        series.contains(where: \.usesReferencePricing)
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("模型用量趋势", "Model usage trend"),
                    systemName: "chart.xyaxis.line"
                ) {
                    HStack(spacing: 6) {
                        InfoChip(
                            title: language.text("口径", "Source"),
                            value: sourceQualityText(trend.sourceQuality, language: language)
                        )
                        Picker("", selection: $window) {
                            ForEach(UsageTrendWindow.allCases) { option in
                                Text(windowLabel(option))
                                    .tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.mini)
                        .frame(width: 92, height: dashboardHeaderControlHeight)
                        .help(windowHelp)
                        .accessibilityLabel(language.text("趋势时间范围", "Trend time range"))
                        .accessibilityValue(windowLabel(window))
                        Picker("", selection: $metric) {
                            Text(language.text("Token", "Tokens"))
                                .tag(UsageTrendMetric.tokens)
                            Text(language.text(
                                usesReferencePricing ? "参考费用" : "估算费用",
                                usesReferencePricing ? "Ref. cost" : "Est. cost"
                            ))
                                .tag(UsageTrendMetric.estimatedCostUSD)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .frame(width: 148, height: dashboardHeaderControlHeight)
                        .disabled(!costAvailable)
                        .help(metricHelp)
                    }
                }

                ModelUsageSummaryStrip(
                    summary: metricSummary,
                    metric: metric,
                    language: language
                )

                if series.isEmpty {
                    AnalyticsEmptyState(
                        systemName: "chart.xyaxis.line",
                        title: language.text("暂无模型记录", "No model records"),
                        detail: language.text("解析到 token 后，这里会显示不同模型的每日用量。", "Daily model usage appears after token events are parsed.")
                    )
                    .frame(maxWidth: .infinity, minHeight: usageTrendAreaPlotHeight)
                } else {
                    ModelUsageAreaChart(
                        series: series,
                        metric: metric,
                        runtimeScope: runtimeScope,
                        language: language,
                        colorMap: colorMap,
                        window: window,
                        totalBuckets: totalBuckets
                    )
                    .frame(height: usageTrendAreaPlotHeight)

                    ModelUsageLegend(
                        series: series,
                        language: language,
                        colorMap: colorMap,
                        showsTotal: true
                    )
                        .frame(height: usageTrendLegendHeight)
                }
            }
        }
        .onChange(of: trend.sourceQuality) { quality in
            if quality != .detailed {
                metric = .tokens
            }
        }
        .onChange(of: costAvailable) { available in
            if !available {
                metric = .tokens
            }
        }
    }

    private var metricSummary: ModelUsageMetricSummary? {
        guard metric == .tokens || costAvailable else { return nil }
        return ModelUsageMetricSummary.make(from: trend, metric: metric)
    }

    private var metricHelp: String {
        if costAvailable {
            if usesReferencePricing {
                return language.text(
                    "部分模型没有独立价格，费用按 GPT-5.5 价格作参考折算；不代表官方账单。",
                    "Some models have no dedicated price, so cost uses GPT-5.5 pricing as a reference; this is not an official bill."
                )
            }
            return language.text(
                "切换每日 token 与 API 等效估算费用；费用不代表官方账单。",
                "Switch between daily tokens and API-equivalent estimated cost; this is not an official bill."
            )
        }
        return language.text(
            "粗略线程口径没有输入/缓存/输出拆分，估算费用暂不可用。",
            "Approximate thread data has no input/cache/output split, so estimated cost is unavailable."
        )
    }

    private func windowLabel(_ option: UsageTrendWindow) -> String {
        language.text("最近 \(option.dayCount) 天", "Last \(option.dayCount) days")
    }

    private var windowHelp: String {
        language.text(
            "选择模型面积图的日期范围；数据最多可回溯半年。",
            "Choose the model area chart range; data is available for up to six months."
        )
    }
}

private struct ModelUsageSummaryStrip: View {
    let summary: ModelUsageMetricSummary?
    let metric: UsageTrendMetric
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 8) {
            summaryItem(
                title: language.text("近 7 日", "Last 7 days"),
                value: summary.map { valueText($0.recentValue) } ?? unavailableText,
                tint: FixedVisualPalette.statusNeutral
            )
            summaryItem(
                title: language.text("日均", "Daily average"),
                value: summary.map { valueText($0.dailyAverageValue) } ?? unavailableText,
                tint: FixedVisualPalette.statusNeutral
            )
            summaryItem(
                title: language.text("较前 7 日", "Vs. previous 7 days"),
                value: changeText,
                tint: changeTint
            )
        }
        .frame(height: usageTrendSummaryStripHeight)
    }

    private var unavailableText: String {
        language.text("不可用", "Unavailable")
    }

    private var changeText: String {
        guard let summary else { return unavailableText }
        if summary.isNewActivity {
            return language.text("新增", "New")
        }
        guard let change = summary.changePercent else { return "--" }
        return formatSignedPercent(change)
    }

    private var changeTint: Color {
        guard let summary else { return FixedVisualPalette.statusNeutral }
        if summary.isNewActivity { return FixedVisualPalette.statusSuccess }
        guard let change = summary.changePercent else { return FixedVisualPalette.statusNeutral }
        return change >= 0 ? FixedVisualPalette.statusSuccess : FixedVisualPalette.statusWarning
    }

    private func valueText(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return "\(formatTokens(Int64(value.rounded()))) tokens"
        case .estimatedCostUSD:
            return formatUSD(value)
        }
    }

    private func summaryItem(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.62))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ModelUsageSeriesColorMap {
    let colors: [PaletteColor]
    private let indexByID: [String: Int]

    init(series: [ModelUsageAreaSeries], visualTokens: ResolvedVisualTokens) {
        let resolvedColors = visualTokens.data.modelSeries ?? visualTokens.data.series
        colors = resolvedColors.isEmpty ? [PaletteColor(rgba: 0x2866F7FF)] : resolvedColors

        var available = Set(colors.indices)
        if series.contains(where: \.isAggregate), let aggregateIndex = colors.indices.last {
            available.remove(aggregateIndex)
        }

        var mapping: [String: Int] = [:]
        for item in series where !item.isAggregate {
            let preferred = stableModelColorSlot(for: item.id, count: colors.count)
            let slot: Int
            if available.contains(preferred) {
                slot = preferred
                available.remove(preferred)
            } else if let fallback = available.sorted().first {
                slot = fallback
                available.remove(fallback)
            } else {
                slot = preferred
            }
            mapping[item.id] = slot
        }
        if let aggregate = series.first(where: \.isAggregate), let aggregateIndex = colors.indices.last {
            mapping[aggregate.id] = aggregateIndex
        }
        indexByID = mapping
    }

    func color(for series: ModelUsageAreaSeries) -> Color {
        let index = indexByID[series.id] ?? stableModelColorSlot(for: series.id, count: colors.count)
        return colors[index].color
    }
}

private func stableModelColorSlot(for modelID: String, count: Int) -> Int {
    guard count > 0 else { return 0 }
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in modelID.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(count))
}

private struct ModelUsageLegend: View {
    let series: [ModelUsageAreaSeries]
    let language: WidgetLanguage
    let colorMap: ModelUsageSeriesColorMap
    let showsTotal: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if showsTotal {
                    HStack(spacing: 5) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 4))
                            path.addLine(to: CGPoint(x: 16, y: 4))
                        }
                        .stroke(
                            FixedVisualPalette.statusNeutral,
                            style: StrokeStyle(lineWidth: 1.8, dash: [3, 2])
                        )
                        .frame(width: 16, height: 8)
                        Text(language.text("总用量", "Total usage"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }

                ForEach(series) { item in
                    HStack(spacing: 5) {
                        Capsule(style: .continuous)
                            .fill(colorMap.color(for: item))
                            .frame(width: 16, height: 3)
                        Text(seriesLabel(item))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func seriesLabel(_ item: ModelUsageAreaSeries) -> String {
        if item.isAggregate {
            return language.text("其他模型", "Other models")
        }
        return modelUsageLabel(item.model, language: language)
    }
}

private struct ModelUsageAreaChart: View {
    let series: [ModelUsageAreaSeries]
    let metric: UsageTrendMetric
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    let colorMap: ModelUsageSeriesColorMap
    let window: UsageTrendWindow
    let totalBuckets: [UsageDayBucket]
    @State private var hoveredDayIndex: Int?
    @State private var hoverAnchor: CGPoint = .zero

    private let plotLeading: CGFloat = 48
    private let plotTrailing: CGFloat = 8
    private let plotTop: CGFloat = 8
    private let plotBottom: CGFloat = 22

    private var referenceBuckets: [UsageDayBucket] {
        totalBuckets
    }

    private var maximumValue: Double {
        max(
            (
                series.flatMap { $0.dayBuckets.map { metric.value(for: $0) } }
                    + totalBuckets.map { metric.value(for: $0) }
            ).max() ?? 0,
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                let plot = plotRect(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    gridView(plot: plot, size: geometry.size)

                    ForEach(series) { item in
                        seriesLayer(item, plot: plot)
                    }

                    totalSeriesLayer(plot: plot)

                    if let hoveredDayIndex, referenceBuckets.indices.contains(hoveredDayIndex) {
                        let x = chartX(index: hoveredDayIndex, plot: plot, count: referenceBuckets.count)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: plot.minY))
                            path.addLine(to: CGPoint(x: x, y: plot.maxY))
                        }
                        .stroke(
                            FixedVisualPalette.surfaceTrack,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )

                        ForEach(series) { item in
                            let point = chartPoints(for: item, plot: plot)[hoveredDayIndex]
                            Circle()
                                .fill(colorMap.color(for: item))
                                .frame(width: 7, height: 7)
                                .position(point)
                        }

                        let totalPoint = chartPoints(for: totalBuckets, plot: plot)[hoveredDayIndex]
                        Circle()
                            .fill(FixedVisualPalette.statusNeutral)
                            .frame(width: 7, height: 7)
                            .position(totalPoint)
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.001))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHover(location: location, plot: plot)
                            case .ended:
                                hoveredDayIndex = nil
                            }
                        }

                    if let hoveredDayIndex, referenceBuckets.indices.contains(hoveredDayIndex) {
                        let payload = tooltipPayload(for: hoveredDayIndex)
                        let compactTooltip = ChartTooltipLayout.isCompact(rowCount: payload.rows.count)
                        ChartTooltipView(payload: payload, compact: compactTooltip)
                            .frame(width: chartTooltipWidth)
                            .position(
                                chartTooltipPosition(
                                    anchor: hoverAnchor,
                                    containerSize: geometry.size,
                                    rowCount: payload.rows.count,
                                    compact: compactTooltip
                                )
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .zIndex(10)
                    }
                }
            }
            .frame(height: max(1, usageTrendAreaPlotHeight - usageTrendAreaAxisHeight - 2))

            axisLabels
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            language.text(
                "按模型显示最近 \(window.dayCount) 天用量的面积图",
                "Area chart showing model usage for the last \(window.dayCount) days"
            )
        )
    }

    @ViewBuilder
    private func seriesLayer(_ item: ModelUsageAreaSeries, plot: CGRect) -> some View {
        let points = chartPoints(for: item, plot: plot)
        areaPath(points: points, baseline: plot.maxY)
            .fill(colorMap.color(for: item).opacity(0.11))
        linePath(points: points)
            .stroke(
                colorMap.color(for: item),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
    }

    private func totalSeriesLayer(plot: CGRect) -> some View {
        linePath(points: chartPoints(for: totalBuckets, plot: plot))
            .stroke(
                FixedVisualPalette.statusNeutral,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4])
            )
    }

    private func gridView(plot: CGRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { index in
                let fraction = CGFloat(index) / 3
                let y = plot.minY + plot.height * fraction
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: y))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                .stroke(FixedVisualPalette.surfaceTrack.opacity(0.52), lineWidth: 1)

                Text(axisValueText(maximumValue * (1 - Double(fraction))))
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: plotLeading - 6, alignment: .trailing)
                    .position(x: (plotLeading - 6) / 2, y: y)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var axisLabels: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(axisIndices, id: \.self) { index in
                    Text(axisDateText(referenceBuckets[index].date))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 58)
                        .position(
                            x: axisX(index: index, width: geometry.size.width),
                            y: 8
                        )
                }
            }
        }
        .frame(height: 16)
    }

    private var axisIndices: [Int] {
        guard !referenceBuckets.isEmpty else { return [] }
        let values = [0, referenceBuckets.count / 4, referenceBuckets.count / 2, (referenceBuckets.count * 3) / 4, referenceBuckets.count - 1]
        return values.reduce(into: [Int]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: plotLeading,
            y: plotTop,
            width: max(1, size.width - plotLeading - plotTrailing),
            height: max(1, size.height - plotTop - plotBottom)
        )
    }

    private func chartPoints(for item: ModelUsageAreaSeries, plot: CGRect) -> [CGPoint] {
        guard !referenceBuckets.isEmpty else { return [] }
        let valuesByID = Dictionary(uniqueKeysWithValues: item.dayBuckets.map { ($0.id, metric.value(for: $0)) })
        return referenceBuckets.enumerated().map { index, reference in
            let value = valuesByID[reference.id] ?? 0
            let ratio = max(0, min(1, value / maximumValue))
            return CGPoint(
                x: chartX(index: index, plot: plot, count: referenceBuckets.count),
                y: plot.maxY - plot.height * CGFloat(ratio)
            )
        }
    }

    private func chartPoints(for buckets: [UsageDayBucket], plot: CGRect) -> [CGPoint] {
        guard !referenceBuckets.isEmpty else { return [] }
        let valuesByID = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, metric.value(for: $0)) })
        return referenceBuckets.enumerated().map { index, reference in
            let value = valuesByID[reference.id] ?? 0
            let ratio = max(0, min(1, value / maximumValue))
            return CGPoint(
                x: chartX(index: index, plot: plot, count: referenceBuckets.count),
                y: plot.maxY - plot.height * CGFloat(ratio)
            )
        }
    }

    private func chartX(index: Int, plot: CGRect, count: Int) -> CGFloat {
        plot.minX + plot.width * CGFloat(index) / CGFloat(max(count - 1, 1))
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(points: [CGPoint], baseline: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: baseline))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.closeSubpath()
        }
    }

    private func updateHover(location: CGPoint, plot: CGRect) {
        guard !referenceBuckets.isEmpty else { return }
        let clampedX = max(plot.minX, min(plot.maxX, location.x))
        let ratio = (clampedX - plot.minX) / max(plot.width, 1)
        let index = Int((ratio * CGFloat(max(referenceBuckets.count - 1, 0))).rounded())
        hoveredDayIndex = index
        hoverAnchor = CGPoint(
            x: chartX(index: index, plot: plot, count: referenceBuckets.count),
            y: plot.minY + 18
        )
    }

    private func tooltipPayload(for index: Int) -> ChartTooltipPayload {
        let date = referenceBuckets[index].date
        var rows = [
            ChartTooltipRow(
                id: "total",
                label: language.text("总用量", "Total usage"),
                value: metricValueText(metric.value(for: totalBuckets[index]))
            )
        ]
        rows.append(contentsOf: series.map { item in
            let bucket = item.dayBuckets[index]
            return ChartTooltipRow(
                id: item.id,
                label: seriesLabel(item),
                value: metricValueText(metric.value(for: bucket))
            )
        })
        rows.append(ChartTooltipRow(
            id: "runtime",
            label: language.text("运行时", "Runtime"),
            value: runtimeScope.displayName
        ))
        rows.append(ChartTooltipRow(
            id: "source",
            label: language.text("口径", "Source"),
            value: sourceQualityText(referenceBuckets[index].sourceQuality, language: language)
        ))
        return ChartTooltipPayload(title: fullDateText(date, language: language), rows: rows)
    }

    private func seriesLabel(_ item: ModelUsageAreaSeries) -> String {
        if item.isAggregate {
            return language.text("其他模型", "Other models")
        }
        return modelUsageLabel(item.model, language: language)
    }

    private func metricValueText(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return formatTokens(Int64(value.rounded())) + " tokens"
        case .estimatedCostUSD:
            return formatUSD(value)
        }
    }

    private func axisValueText(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return formatTokens(Int64(value.rounded()))
        case .estimatedCostUSD:
            return formatUSD(value)
        }
    }

    private func axisDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = language.isChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }

    private func axisX(index: Int, width: CGFloat) -> CGFloat {
        let raw = width * CGFloat(index) / CGFloat(max(referenceBuckets.count - 1, 1))
        let halfLabelWidth: CGFloat = 29
        return min(max(raw, halfLabelWidth), max(halfLabelWidth, width - halfLabelWidth))
    }
}

struct UsageHeatmapCard: View {
    let trend: UsageTrend
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    @Environment(\.visualTokens) private var visualTokens

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
                            .fill(heatmapColor(level: level, tokens: visualTokens))
                            .frame(width: heatmapCellSize, height: heatmapCellSize)
                    }
                    Text(language.text("多", "More"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .help(usageSourceHelp(language: language))
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
    @Environment(\.visualTokens) private var visualTokens

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
                                        .fill(heatmapColor(level: heatLevel(cell.tokens), tokens: visualTokens))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .strokeBorder(
                                                    hoveredCell?.id == cell.id ? visualTokens.selection.focusRing.color : Color.clear,
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
            return language.text("\(date) 无本地 token 记录", "No local token records on \(date)")
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

struct ModelActivityOverviewCard: View {
    let trend: UsageTrend
    let language: WidgetLanguage
    let window: UsageTrendWindow

    private var visibleBuckets: [UsageDayBucket] {
        ModelUsageAreaSeriesBuilder.dateBuckets(from: trend, window: window)
    }

    private var activeModelCount: Int {
        let visibleIDs = Set(visibleBuckets.map(\.id))
        return (trend.modelTrends ?? []).filter { modelTrend in
            modelTrend.dayBuckets.contains { bucket in
                visibleIDs.contains(bucket.id) && bucket.tokens > 0
            }
        }.count
    }

    private var activeDayCount: Int {
        visibleBuckets.filter { $0.tokens > 0 }.count
    }

    private var dailyAverageTokens: Int64 {
        let totalTokens = visibleBuckets.reduce(Int64(0)) { $0 + $1.tokens }
        return totalTokens / Int64(max(window.dayCount, 1))
    }

    private var topModelSeries: ModelUsageAreaSeries? {
        ModelUsageAreaSeriesBuilder
            .build(from: trend, window: window)
            .first(where: { !$0.isAggregate })
    }

    private var topModelTokens: Int64 {
        topModelSeries?.dayBuckets.reduce(Int64(0)) { $0 + $1.tokens } ?? 0
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: dashboardCardContentSpacing) {
                DashboardCardHeader(
                    title: language.text("模型活动概览", "Model activity"),
                    systemName: "person.3"
                ) {
                    InfoChip(
                        title: language.text("范围", "Range"),
                        value: windowLabel
                    )
                }

                VStack(alignment: .leading, spacing: dashboardListRowSpacing) {
                    activityRow(
                        title: language.text("用量最高模型", "Top model"),
                        value: topModelSeries.map { modelUsageLabel($0.model, language: language) }
                            ?? language.text("暂无模型记录", "No model records"),
                        detail: topModelSeries.map { _ in "\(formatTokens(topModelTokens)) tokens" }
                            ?? language.text("暂无可用数据", "No data")
                    )
                    activityRow(
                        title: language.text("活跃日期", "Active days"),
                        value: "\(activeDayCount) / \(window.dayCount)",
                        detail: language.text("有 token 记录的日期", "Days with token activity")
                    )
                    activityRow(
                        title: language.text("活跃模型", "Active models"),
                        value: "\(activeModelCount)",
                        detail: language.text("当前范围内有用量", "With usage in the selected range")
                    )
                    activityRow(
                        title: language.text("范围日均", "Range avg"),
                        value: "\(formatTokens(dailyAverageTokens)) tokens",
                        detail: language.text("按选定日期范围", "Across selected days")
                    )
                }
            }
        }
    }

    private var windowLabel: String {
        language.text("最近 \(window.dayCount) 天", "Last \(window.dayCount) days")
    }

    private func activityRow(title: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.42))
        )
    }
}

private func modelUsageLabel(_ model: String?, language: WidgetLanguage) -> String {
    normalizedModelUsageName(model) ?? language.text("未记录模型", "Unrecorded model")
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
    @Environment(\.visualTokens) private var visualTokens

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
                                tint: visualTokens.data.series[1].color
                            )
                            MetricTile(
                                title: language.text("新增估算", "New est."),
                                value: "\(newProjectCount)",
                                tint: FixedVisualPalette.statusSuccess
                            )
                        }
                        HStack(spacing: dashboardListRowSpacing) {
                            MetricTile(
                                title: "Top1",
                                value: topOneShare,
                                tint: visualTokens.data.series[0].color
                            )
                            MetricTile(
                                title: "Top3",
                                value: topThreeShare,
                                tint: visualTokens.data.series[2].color
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
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(visualTokens.data.series[1].color)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(visualTokens.data.series[1].color.opacity(0.12))
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
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.42))
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
    @Environment(\.visualTokens) private var visualTokens

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
                        .fill(FixedVisualPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(visualTokens.data.series[1].color.opacity(0.82))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.42))
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
    @Environment(\.visualTokens) private var visualTokens

    private var progress: Double {
        guard maxCalls > 0 else { return 0 }
        return max(0, min(1, Double(tool.callCount) / Double(maxCalls)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: toolCategoryIcon(tool.category))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(visualTokens.data.series[0].color)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(visualTokens.data.series[0].color.opacity(0.12))
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
                        .fill(FixedVisualPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(visualTokens.data.series[0].color.opacity(0.78))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.42))
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
    @Environment(\.visualTokens) private var visualTokens

    private var progress: Double {
        guard maxLoads > 0 else { return 0 }
        return max(0, min(1, Double(skill.loadCount) / Double(maxLoads)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(visualTokens.data.series[1].color)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(visualTokens.data.series[1].color.opacity(0.12))
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
                        .fill(FixedVisualPalette.surfaceTrack)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(visualTokens.data.series[1].color.opacity(0.78))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
        }
        .padding(dashboardRowPadding)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(FixedVisualPalette.surfaceTrack.opacity(0.42))
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
            return language.text("当前未定位", "not located")
        }
        return language.text("Skill.md \(formatTokens(tokens))", "Skill.md \(formatTokens(tokens))")
    }

    private var skillHelpText: String {
        guard let staticTokenEstimate = skill.staticTokenEstimate else {
            return language.text(
                "\(skill.name) · \(skill.loadCount) 次加载 · \(skill.threadCount) 线程 · Skill.md 当前未定位",
                "\(skill.name) · \(skill.loadCount)x loads · \(skill.threadCount) threads · Skill.md not currently located"
            )
        }
        let size = formatBytes(skill.staticByteCount)
        return language.text(
            "\(skill.name) · \(skill.loadCount) 次加载 · \(skill.threadCount) 线程 · Skill.md Token数 \(formatTokens(staticTokenEstimate)) · 当前文件 \(size) · \(displayHomePath(skill.path))",
            "\(skill.name) · \(skill.loadCount)x loads · \(skill.threadCount) threads · Skill.md tokens \(formatTokens(staticTokenEstimate)) · current file \(size) · \(displayHomePath(skill.path))"
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
    let runtimeScope: RuntimeScope
    let language: WidgetLanguage
    let focusedThreadID: String?
    let onOpenSession: (String) -> Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: taskColumnIcon(column.id, runtimeScope: runtimeScope))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(taskAccentForegroundColor(column.id, runtimeScope: runtimeScope, colorScheme: colorScheme))
                Text(localizedTaskColumnTitle(column.id, runtimeScope: runtimeScope, language: language))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(column.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
            .frame(height: dashboardCardHeaderHeight, alignment: .center)
            .help(localizedTaskColumnHelp(column.id, runtimeScope: runtimeScope, language: language))
            .accessibilityElement(children: .combine)

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
                    TaskIssueCard(
                        item: item,
                        language: language,
                        isFocused: item.threadID != nil && item.threadID == focusedThreadID,
                        onOpenSession: onOpenSession
                    )
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
                .fill(taskColumnFill(column.id, runtimeScope: runtimeScope))
                .overlay(
                    RoundedRectangle(cornerRadius: dashboardCardCornerRadius, style: .continuous)
                        .strokeBorder(taskAccentColor(column.id, runtimeScope: runtimeScope).opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

struct TaskIssueCard: View {
    let item: TaskItem
    let language: WidgetLanguage
    let isFocused: Bool
    let onOpenSession: (String) -> Bool
    @Environment(\.visualTokens) private var visualTokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sessionOpenFailed = false
    @State private var isHovering = false
    @State private var hasPointingHandCursor = false
    @FocusState private var hasKeyboardFocus: Bool

    @ViewBuilder
    var body: some View {
        if canOpenSession {
            Button {
                openSession()
            } label: {
                cardSurface
            }
            .buttonStyle(.plain)
            .focused($hasKeyboardFocus)
            .help(taskCardHelp)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityHint(language.text("打开对应的 Codex Session", "Opens the matching Codex session"))
            .onHover(perform: updateHoverState)
            .onDisappear(perform: releasePointingHandCursor)
        } else {
            cardSurface
                .help(taskCardHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel))
        }
    }

    private var canOpenSession: Bool {
        guard let threadID = item.threadID else { return false }
        return CodexSessionLink.url(threadID: threadID) != nil
    }

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .frame(minHeight: 28, alignment: .topLeading)

            HStack(spacing: 5) {
                if !item.detail.isEmpty {
                    Text(localizedTaskDetail(item.detail, language: language))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if let timeText = localizedTaskTime(item, language: language) {
                    Text(timeText)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 13)

            if sessionOpenFailed {
                Text(language.text("无法打开 Codex Session", "Could not open Codex session"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FixedVisualPalette.statusWarning)
            }

            HStack(spacing: 5) {
                TaskChip(
                    text: localizedTaskState(item, language: language),
                    displayState: item.displayState
                )
                Spacer(minLength: 4)
                Text(item.code)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if let tokens = item.tokens, tokens > 0 {
                    Text(formatTokens(tokens))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(dashboardRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .fill(isHovering ? visualTokens.selection.fill.color : Color.clear)
        )
        .cardBackground(cornerRadius: dashboardRowCornerRadius, elevated: true)
        .overlay(
            RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous)
                .strokeBorder(
                    (isFocused || hasKeyboardFocus)
                        ? FixedVisualPalette.statusInfo
                        : (isHovering ? visualTokens.selection.stroke.color : Color.clear),
                    lineWidth: (isFocused || hasKeyboardFocus) ? 1.5 : (isHovering ? 1.0 : 0)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: dashboardRowCornerRadius, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hasKeyboardFocus)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
    }

    private func updateHoverState(_ hovering: Bool) {
        isHovering = hovering
        guard hovering != hasPointingHandCursor else { return }
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        hasPointingHandCursor = hovering
    }

    private func releasePointingHandCursor() {
        isHovering = false
        guard hasPointingHandCursor else { return }
        NSCursor.pop()
        hasPointingHandCursor = false
    }

    private func openSession() {
        guard let threadID = item.threadID else { return }
        sessionOpenFailed = !onOpenSession(threadID)
    }

    private var taskCardHelp: String {
        var lines = [item.title]
        if !item.detail.isEmpty { lines.append(localizedTaskDetail(item.detail, language: language)) }
        lines.append(localizedTaskStateBasis(item.stateBasis, language: language))
        if canOpenSession { lines.append(language.text("点击在 Codex 中打开", "Click to open in Codex")) }
        return lines.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var parts = [
            item.title,
            localizedTaskState(item, language: language)
        ]
        if !item.detail.isEmpty { parts.append(localizedTaskDetail(item.detail, language: language)) }
        if let time = localizedTaskTime(item, language: language) { parts.append(time) }
        parts.append(canOpenSession
            ? language.text("可打开", "Openable")
            : language.text("不可打开", "Not openable"))
        return parts.joined(separator: "，")
    }
}

struct TaskChip: View {
    let text: String
    let displayState: TaskDisplayState
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private var chipAccentColor: Color {
        switch displayState {
        case .failed:
            return FixedVisualPalette.statusDanger
        case .running:
            return FixedVisualPalette.statusWarning
        case .completed:
            return FixedVisualPalette.statusSuccess
        case .blocked:
            return FixedVisualPalette.statusWarning
        case .recentlyActive:
            return FixedVisualPalette.statusWarning
        case .scheduled:
            return FixedVisualPalette.statusScheduled
        case .continueLater, .archived, .pending, .unknown:
            return FixedVisualPalette.statusNeutral
        }
    }

    private var chipForegroundColor: Color {
        guard colorScheme == .light else { return chipAccentColor }
        switch displayState {
        case .failed:
            return FixedVisualPalette.statusDangerLightText
        case .running, .blocked, .recentlyActive:
            return FixedVisualPalette.statusWarningLightText
        case .completed:
            return FixedVisualPalette.statusSuccessLightText
        case .scheduled:
            return FixedVisualPalette.statusScheduledLightText
        case .continueLater, .archived, .pending, .unknown:
            return FixedVisualPalette.statusNeutralLightText
        }
    }

    private var chipIcon: String {
        switch displayState {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .running:
            return "record.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .blocked:
            return "pause.circle.fill"
        case .scheduled:
            return "clock.fill"
        case .archived:
            return "archivebox.fill"
        case .unknown:
            return "questionmark.circle"
        case .recentlyActive:
            return "clock.badge.checkmark"
        case .continueLater, .pending:
            return "circle"
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
                .fill(FixedVisualPalette.surfaceTrack)
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
                .fill(FixedVisualPalette.surfaceTrack)
        )
    }
}

enum FixedVisualPalette {
    static let dataFlowParticle = NSColor.white

    static let statusSuccess = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let statusInfo = Color(red: 0.039, green: 0.518, blue: 1.000) // #0A84FF
    static let statusWarning = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let statusDanger = Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A
    static let statusNeutral = Color(red: 0.596, green: 0.596, blue: 0.616) // #98989D
    static let statusScheduled = Color(red: 0.545, green: 0.427, blue: 1.000) // #8B6DFF

    // Strong semantic foregrounds keep 9 pt labels readable on light glass.
    static let statusDangerLightText = Color(red: 0.706, green: 0.137, blue: 0.094) // #B42318
    static let statusWarningLightText = Color(red: 0.502, green: 0.294, blue: 0.000) // #804B00
    static let statusSuccessLightText = Color(red: 0.078, green: 0.439, blue: 0.224) // #147039
    static let statusNeutralLightText = Color(red: 0.329, green: 0.333, blue: 0.369) // #54555E
    static let statusScheduledLightText = Color(red: 0.384, green: 0.251, blue: 0.773) // #6240C5

    static let surfaceTrack = Color.primary.opacity(0.10)

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

    static func tooltipFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.41)
            : Color.white.opacity(0.46)
    }

    static func leadershipPlaqueFill(_ colorScheme: ColorScheme) -> Color {
        Color.black.opacity(colorScheme == .dark ? 0.58 : 0.52)
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

private let dashboardGridSpacing: CGFloat = 10
private let dashboardCardPadding: CGFloat = 10
private let dashboardCardCornerRadius: CGFloat = 10
private let dashboardCardHeaderHeight: CGFloat = 28
private let dashboardCardHeaderSpacing: CGFloat = 8
private let dashboardCardContentSpacing: CGFloat = 8
private let dashboardHeaderControlHeight: CGFloat = 24
let titlebarControlHeight: CGFloat = 18
private let dashboardTabSegmentWidth: CGFloat = 91
private let dashboardTabIconWidth: CGFloat = 14
private let dashboardTabHorizontalPadding: CGFloat = 8
private let dashboardCardIconSize: CGFloat = 12
private let dashboardCardIconFrame: CGFloat = 18
private let dashboardCardTitleSize: CGFloat = 11
private let dashboardListRowSpacing: CGFloat = 6
private let dashboardRowPadding: CGFloat = 7
private let dashboardRowCornerRadius: CGFloat = 8
let settingsAccessoryColumnWidth: CGFloat = 220
let settingsControlCornerRadius: CGFloat = 8
let settingsSegmentHeight: CGFloat = 30
let settingsControlVisualHeight: CGFloat = settingsSegmentHeight + 6
let settingsSectionTitleFontSize: CGFloat = 12.5
let settingsSectionDetailFontSize: CGFloat = 10
let settingsRowTitleFontSize: CGFloat = 11.5
let settingsRowDetailFontSize: CGFloat = 9.5
let settingsControlFontSize: CGFloat = 11
private let settingsContentTopInset: CGFloat = 12
private let settingsSwitchWidth: CGFloat = 56
private let settingsShortcutControlSpacing: CGFloat = 8
private let settingsShortcutRecorderWidth: CGFloat = 132
private let settingsShortcutActionWidth: CGFloat = settingsAccessoryColumnWidth
    - settingsShortcutRecorderWidth
    - settingsShortcutControlSpacing
private let usageTrendCardHeight: CGFloat = 214
private let usageTrendCardSpacing: CGFloat = dashboardGridSpacing
private let usageTrendAreaChartHeight: CGFloat = 344
private let usageTrendAreaPlotHeight: CGFloat = 210
private let usageTrendAreaAxisHeight: CGFloat = 16
private let usageTrendLegendHeight: CGFloat = 18
private let usageTrendSummaryStripHeight: CGFloat = 44
private let usageSevenDayMinimumCardWidth: CGFloat = 260
private let usageHeatmapCellSpacing: CGFloat = 4
private let usageHeatmapWeekdayLabelWidth: CGFloat = 20
private let usageHeatmapMonthLabelWidth: CGFloat = 42
private let usageHeatmapMonthLabelHeight: CGFloat = 16
private let heatmapCellSize: CGFloat = 10
private let chartTooltipWidth: CGFloat = 188

func runtimeStatusPopoverHeight(for runtimeCount: Int, hasAttention: Bool) -> CGFloat {
    if runtimeCount <= 1 {
        return hasAttention ? 302 : 246
    }
    return hasAttention ? 430 : 374
}

enum ChartTooltipLayout {
    static func isCompact(rowCount: Int) -> Bool {
        rowCount > 8
    }

    static func estimatedHeight(rowCount: Int, compact: Bool) -> CGFloat {
        let safeRowCount = max(rowCount, 0)
        return compact
            ? CGFloat(30 + safeRowCount * 12)
            : CGFloat(38 + safeRowCount * 17)
    }

    static func position(
        anchor: CGPoint,
        containerSize: CGSize,
        rowCount: Int,
        compact: Bool = false
    ) -> CGPoint {
        let tooltipHeight = estimatedHeight(rowCount: rowCount, compact: compact)
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
}

private func chartTooltipPosition(
    anchor: CGPoint,
    containerSize: CGSize,
    rowCount: Int,
    compact: Bool = false
) -> CGPoint {
    ChartTooltipLayout.position(
        anchor: anchor,
        containerSize: containerSize,
        rowCount: rowCount,
        compact: compact
    )
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

private func usageTrendPanelHeight(showsModelAreaChart: Bool) -> CGFloat {
    usageTrendCardHeight
        + (showsModelAreaChart ? usageTrendCardSpacing + usageTrendAreaChartHeight : 0)
}

private func localizedDashboardTitle(_ tab: DashboardTab, language: WidgetLanguage) -> String {
    switch tab {
    case .tasks:
        return language.text("今日任务看板", "Today's task board")
    case .leadership:
        return language.text("AI 领导力", "AI leadership")
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
    case .leadership:
        return language.text("AI 领导力", "Leadership")
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
    case .leadership:
        return "scope"
    case .usage:
        return "calendar"
    case .projects:
        return "folder"
    case .skills:
        return "puzzlepiece.extension"
    }
}

private func heatmapColor(level: Int, tokens: ResolvedVisualTokens) -> Color {
    tokens.data.heatmap[max(0, min(level, tokens.data.heatmap.count - 1))].color
}

private func sourceQualityText(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .detailed:
        return language.text("精细", "Detailed")
    case .approximate:
        return language.text("粗略", "Approx.")
    }
}

private func sourceQualityDetailText(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .detailed:
        return language.text("事件口径", "Event source")
    case .approximate:
        return language.text("线程口径", "Thread source")
    }
}

private func usageSourceTooltip(_ quality: UsageSourceQuality, language: WidgetLanguage) -> String {
    switch quality {
    case .detailed:
        return language.text("来自 token_count", "From token_count")
    case .approximate:
        return language.text("按线程更新时间", "By thread time")
    }
}

private func usageSourceHelp(language: WidgetLanguage) -> String {
    language.text(
        "使用本机 Codex session token_count 事件估算；缺失时回退到本机线程更新时间统计。API 等效价值为估算，不代表官方账单。",
        "Estimated from local Codex session token_count events. Falls back to thread updated_at when detailed events are unavailable. API-equivalent value is an estimate, not an official bill."
    )
}

private func shortWeekdayText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = "EEEEE"
    return formatter.string(from: date)
}

private func fullDateText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
    formatter.dateFormat = language.isChinese ? "M月d日 EEEE" : "MMM d, EEEE"
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

private func taskAccentColor(_ kind: TaskColumnKind, runtimeScope: RuntimeScope) -> Color {
    switch kind {
    case .active:
        return FixedVisualPalette.statusWarning
    case .pending:
        return FixedVisualPalette.statusNeutral
    case .scheduled:
        return FixedVisualPalette.statusScheduled
    case .done:
        return runtimeScope == .codex
            ? FixedVisualPalette.statusNeutral
            : FixedVisualPalette.statusSuccess
    }
}

private func taskAccentForegroundColor(
    _ kind: TaskColumnKind,
    runtimeScope: RuntimeScope,
    colorScheme: ColorScheme
) -> Color {
    guard colorScheme == .light else { return taskAccentColor(kind, runtimeScope: runtimeScope) }
    switch kind {
    case .active:
        return FixedVisualPalette.statusWarningLightText
    case .pending:
        return FixedVisualPalette.statusNeutralLightText
    case .scheduled:
        return FixedVisualPalette.statusScheduledLightText
    case .done:
        return runtimeScope == .codex
            ? FixedVisualPalette.statusNeutralLightText
            : FixedVisualPalette.statusSuccessLightText
    }
}

private func taskColumnFill(_ kind: TaskColumnKind, runtimeScope: RuntimeScope) -> Color {
    taskAccentColor(kind, runtimeScope: runtimeScope).opacity(0.065)
}

private func taskColumnIcon(_ kind: TaskColumnKind, runtimeScope: RuntimeScope) -> String {
    switch kind {
    case .active:
        return "record.circle"
    case .pending:
        return "circle"
    case .scheduled:
        return "clock"
    case .done:
        return runtimeScope == .codex ? "archivebox.fill" : "checkmark.circle.fill"
    }
}

private func localizedTaskColumnTitle(
    _ kind: TaskColumnKind,
    runtimeScope: RuntimeScope,
    language: WidgetLanguage
) -> String {
    switch kind {
    case .active:
        return runtimeScope == .codex
            ? language.text("最近活跃", "Recent")
            : language.text("进行中", "Active")
    case .pending:
        return runtimeScope == .codex
            ? language.text("待继续", "To continue")
            : language.text("待处理", "Pending")
    case .scheduled:
        return runtimeScope == .codex
            ? language.text("定时", "Scheduled")
            : language.text("计划中", "Planned")
    case .done:
        return runtimeScope == .codex
            ? language.text("今日归档", "Archived today")
            : language.text("已完成", "Completed")
    }
}

private func localizedTaskColumnHelp(
    _ kind: TaskColumnKind,
    runtimeScope: RuntimeScope,
    language: WidgetLanguage
) -> String {
    if runtimeScope == .claudeCode {
        return language.text(
            "状态来自本机 Claude Code task 记录。",
            "Status comes from local Claude Code task records."
        )
    }
    switch kind {
    case .active:
        return language.text(
            "最近 2 小时有本地活动，不代表任务仍在执行。",
            "Local activity in the last 2 hours; this does not mean the task is still running."
        )
    case .pending:
        return language.text(
            "今天未归档、但最近 2 小时没有活动的 Session。",
            "Today's unarchived sessions without activity in the last 2 hours."
        )
    case .scheduled:
        return language.text(
            "来自本机启用中的 Codex automation 配置。",
            "From enabled local Codex automation configurations."
        )
    case .done:
        return language.text(
            "今天归档的 Codex Session，不代表任务结果成功。",
            "Codex sessions archived today; this does not imply a successful result."
        )
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
    if detail.hasPrefix("工作日") {
        return detail.replacingOccurrences(of: "工作日", with: "Weekdays")
    }
    if detail.hasPrefix("每天") {
        return detail.replacingOccurrences(of: "每天", with: "Daily")
    }
    if detail.hasPrefix("每周") {
        let suffix = detail.dropFirst(2)
        let components = suffix.split(separator: " ", maxSplits: 1).map(String.init)
        let weekdays = components.first?.compactMap { character -> String? in
            switch character {
            case "一": return "Mon"
            case "二": return "Tue"
            case "三": return "Wed"
            case "四": return "Thu"
            case "五": return "Fri"
            case "六": return "Sat"
            case "日": return "Sun"
            default: return nil
            }
        }.joined(separator: "/") ?? "Weekly"
        return [weekdays.isEmpty ? "Weekly" : weekdays, components.count > 1 ? components[1] : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }
    if detail.hasPrefix("每 "), detail.hasSuffix(" 分钟") {
        return detail
            .replacingOccurrences(of: "每 ", with: "Every ")
            .replacingOccurrences(of: " 分钟", with: " minutes")
    }
    return detail
        .replacingOccurrences(of: "每小时", with: "Hourly")
        .replacingOccurrences(of: "每分钟", with: "Every minute")
        .replacingOccurrences(of: "定时", with: "Scheduled")
}

private func localizedTaskState(_ item: TaskItem, language: WidgetLanguage) -> String {
    switch item.displayState {
    case .recentlyActive:
        return language.text("最近活跃", "Recently active")
    case .continueLater:
        return language.text("待继续", "To continue")
    case .scheduled:
        return item.sourceKind == .claudeTask
            ? language.text("计划中", "Planned")
            : language.text("定时", "Scheduled")
    case .archived:
        return language.text("今日归档", "Archived today")
    case .running:
        return language.text("进行中", "Running")
    case .pending:
        return language.text("待处理", "Pending")
    case .failed:
        return language.text("失败", "Failed")
    case .blocked:
        return language.text("阻塞", "Blocked")
    case .completed:
        return language.text("已完成", "Completed")
    case .unknown:
        return language.text("状态未知", "Unknown status")
    }
}

private func localizedTaskStateBasis(_ basis: TaskStateBasis, language: WidgetLanguage) -> String {
    switch basis {
    case .activityWindow:
        return language.text(
            "依据：本机 Codex Session 最近 2 小时活动时间。",
            "Basis: local Codex session activity in the last 2 hours."
        )
    case .archive:
        return language.text(
            "依据：本机 Codex Session 今天已归档；不代表成功。",
            "Basis: the local Codex session was archived today; this does not imply success."
        )
    case .scheduleConfig:
        return language.text(
            "依据：本机已启用的 automation 配置。",
            "Basis: an enabled local automation configuration."
        )
    case .explicit:
        return language.text(
            "依据：本机 Claude Code task 状态。",
            "Basis: the local Claude Code task status."
        )
    }
}

private func localizedTaskTime(_ item: TaskItem, language: WidgetLanguage) -> String? {
    if let nextRunAt = item.nextRunAt {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
        if calendar.isDateInToday(nextRunAt) {
            formatter.dateFormat = "HH:mm"
            return language.text("下次 今天 \(formatter.string(from: nextRunAt))", "Next today \(formatter.string(from: nextRunAt))")
        }
        let currentYear = calendar.component(.year, from: Date())
        formatter.dateFormat = calendar.component(.year, from: nextRunAt) == currentYear
            ? "M/d HH:mm"
            : "yyyy/M/d HH:mm"
        return language.text("下次 \(formatter.string(from: nextRunAt))", "Next \(formatter.string(from: nextRunAt))")
    }

    guard let updatedAt = item.updatedAt else { return nil }
    let relative = relativeTimeText(updatedAt, language: language)
    switch item.stateBasis {
    case .activityWindow:
        return language.text("活动 \(relative)", "Active \(relative)")
    case .archive:
        return language.text("归档 \(relative)", "Archived \(relative)")
    case .explicit:
        return language.text("更新 \(relative)", "Updated \(relative)")
    case .scheduleConfig:
        return nil
    }
}

private func localizedReaderMessage(_ message: String, language: WidgetLanguage) -> String {
    guard !language.isChinese else { return message }
    if message == "正在读取 codexU 数据" { return "Reading codexU data" }
    if message.contains("未找到 codex") { return "Codex executable not found" }
    if message.contains("app-server 启动失败") { return "Failed to start app-server" }
    if message.contains("app-server 响应超时") { return "app-server response timed out" }
    if message.contains("app-server 输出读取失败") { return "Failed to read app-server output" }
    if message.contains("未找到 Codex state_5.sqlite") { return "Codex state_5.sqlite not found" }
    if message.contains("未找到 sqlite3") { return "sqlite3 not found" }
    if message.contains("SQLite 查询失败") { return "SQLite query failed" }
    if message.contains("未找到 Codex session 日志") { return "Codex session logs not found" }
    if message.contains("未找到 Codex token_count 事件") { return "Codex token_count events not found" }
    if message.contains("任务看板未找到 SQLite 数据源") { return "Task board SQLite data source not found" }
    if message.contains("额度响应缺少窗口字段") {
        return "Codex quota response is missing window fields, so it was not treated as having no active limits"
    }
    if message.contains("额度窗口格式无法解析") {
        return "Codex quota window could not be parsed, so it was not treated as having no active limits"
    }
    if message.contains("重复的 5 小时额度窗口") { return "Codex returned duplicate 5-hour quota windows, so that quota is hidden" }
    if message.contains("重复的 7 天额度窗口") { return "Codex returned duplicate 7-day quota windows, so that quota is hidden" }
    if message.contains("重复的月额度窗口") { return "Codex returned duplicate monthly quota windows, so that quota is hidden" }
    if message.contains("同时返回了 7 天与月额度窗口") {
        return "Codex returned both 7-day and monthly quota windows; the 7-day window is shown first"
    }
    if message.contains("缺少时长的额度窗口") {
        return "Codex returned a quota window without a duration, so it was not labeled as 5h, 7d, or monthly"
    }
    if message.contains("未识别的额度窗口") {
        return message
            .replacingOccurrences(
                of: "Codex 返回了未识别的额度窗口（",
                with: "Codex returned an unknown quota window ("
            )
            .replacingOccurrences(
                of: " 分钟），未将其标注为 5 小时、7 天或月额度",
                with: " minutes), so it was not labeled as 5h, 7d, or monthly"
            )
            .replacingOccurrences(
                of: " 分钟），未将其标注为 5 小时或 7 天",
                with: " minutes), so it was not labeled as 5h, 7d, or monthly"
            )
    }
    if message.contains("app-server") { return message.replacingOccurrences(of: "未知错误", with: "Unknown error") }
    return message
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

#if compiler(>=6.2) && CODEXU_HAS_LIQUID_GLASS
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.tintColor = nil
            glass.contentView = host
            addSubview(glass)
        } else {
            installMaterialFallback(host: host)
        }
#else
        installMaterialFallback(host: host)
#endif
    }

    private func installMaterialFallback(host: NSView) {
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
    private let startupPerformanceSpan = PerformanceMonitor.shared.begin(.appStartup)
    private let store = UsageStore()
    private let paletteCatalog = PaletteCatalog.loadFromMainBundle()
    private lazy var settings = AppSettings(paletteCatalog: paletteCatalog)
    private lazy var updateStore = AppUpdateStore(settings: settings)
    private var window: MainAppWindow?
    private var settingsWindow: NSWindow?
    private var paletteLibraryWindow: NSWindow?
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
    private var lastRenderedStatusItemPaletteIdentity: PaletteRenderIdentity?

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
        PerformanceMonitor.shared.end(startupPerformanceSpan)
    }

    private func createMainWindow() {
        let width = UsageWidgetView.widgetDefaultWidth
        let height = UsageWidgetView.widgetDefaultHeight
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: max(screenFrame.minX + 16, screenFrame.maxX - width - 28),
            y: max(screenFrame.minY + 16, screenFrame.maxY - height - 36)
        )

        let mainWindow = MainAppWindow(contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)))
        mainWindow.delegate = self
        mainWindow.minSize = CGSize(width: UsageWidgetView.widgetMinWidth, height: UsageWidgetView.widgetMinHeight)
        mainWindow.maxSize = CGSize(width: UsageWidgetView.widgetMaxWidth, height: .greatestFiniteMagnitude)
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
        _ = mainWindow.setFrameAutosaveName("codexU.mainWindow")
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
        toolbarView.frame = NSRect(x: 0, y: 0, width: UsageWidgetView.widgetDefaultWidth - 24, height: 44)

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
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = settings.language.text("设置", "Settings")
            settingsWindow.titleVisibility = .hidden
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.isOpaque = false
            settingsWindow.backgroundColor = .clear
            settingsWindow.hasShadow = true
            settingsWindow.isMovableByWindowBackground = true
            settingsWindow.acceptsMouseMovedEvents = true
            settingsWindow.delegate = self
            settingsWindow.contentView = GlassHostingContainer(
                rootView: SettingsPanelView(
                    settings: settings,
                    store: store,
                    updateStore: updateStore,
                    onOpenPaletteLibrary: { [weak self] in self?.openPaletteLibraryWindow() }
                ),
                cornerRadius: 20
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

    private func openPaletteLibraryWindow() {
        if paletteLibraryWindow == nil {
            let paletteLibraryWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            paletteLibraryWindow.title = settings.language.text("配色库", "Palette Library")
            paletteLibraryWindow.titleVisibility = .hidden
            paletteLibraryWindow.titlebarAppearsTransparent = true
            paletteLibraryWindow.isReleasedWhenClosed = false
            paletteLibraryWindow.isOpaque = false
            paletteLibraryWindow.backgroundColor = .clear
            paletteLibraryWindow.hasShadow = true
            paletteLibraryWindow.isMovableByWindowBackground = true
            paletteLibraryWindow.acceptsMouseMovedEvents = true
            paletteLibraryWindow.delegate = self
            paletteLibraryWindow.contentMinSize = NSSize(width: 660, height: 320)
            paletteLibraryWindow.contentView = GlassHostingContainer(
                rootView: PaletteLibraryView(settings: settings),
                cornerRadius: 20
            )
            paletteLibraryWindow.center()
            self.paletteLibraryWindow = paletteLibraryWindow
        }

        guard let paletteLibraryWindow else { return }
        paletteLibraryWindow.title = settings.language.text("配色库", "Palette Library")
        if paletteLibraryWindow.isMiniaturized {
            paletteLibraryWindow.deminiaturize(nil)
        }
        paletteLibraryWindow.makeKeyAndOrderFront(nil)
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
                self?.paletteLibraryWindow?.title = language.text("配色库", "Palette Library")
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

        settings.$paletteID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.lastRenderedStatusItemPaletteIdentity = nil
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
                    height: runtimeStatusPopoverHeight(
                        for: scopes.count,
                        hasAttention: self.currentPopoverAttention != nil
                    )
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
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = CGSize(
            width: 380,
            height: runtimeStatusPopoverHeight(
                for: settings.visibleRuntimeScopes.count,
                hasAttention: currentPopoverAttention != nil
            )
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
                openAttention: { [weak self] item in
                    self?.openAttentionItem(item)
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
        store.setStatusPopoverVisible(true)
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

    private var currentPopoverAttention: TaskAttentionItem? {
        store.highestPriorityAttention(
            for: settings.visibleRuntimeScopes,
            updateResult: updateStore.result
        )
    }

    private func openAttentionItem(_ item: TaskAttentionItem) {
        if item.kind == .update {
            updateStore.openPreferredUpdateURL()
            return
        }
        let scope = item.runtimeScope ?? store.selectedRuntimeScope
        if item.threadID != nil {
            store.requestTaskFocus(scope: scope, threadID: item.threadID)
        } else {
            store.selectRuntime(scope)
        }
        showMainWindow()
    }

    private func updateStatusPopoverSize() {
        guard statusPopover?.isShown == true else { return }
        statusPopover?.contentSize = CGSize(
            width: 380,
            height: runtimeStatusPopoverHeight(
                for: settings.visibleRuntimeScopes.count,
                hasAttention: currentPopoverAttention != nil
            )
        )
    }

    func popoverDidClose(_ notification: Notification) {
        statusPopover = nil
        removeStatusPopoverEventMonitors()
        updateTaskBoardPollingActivity()
        store.setStatusPopoverVisible(false)
    }

    private func closeStatusPopover() {
        statusPopover?.performClose(nil)
        statusPopover = nil
        removeStatusPopoverEventMonitors()
        updateTaskBoardPollingActivity()
        store.setStatusPopoverVisible(false)
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
                self?.updateStatusPopoverSize()
            }
            .store(in: &cancellables)

        store.$runtimeSnapshots
            .combineLatest(updateStore.$result)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateStatusPopoverSize()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let presentation = currentStatusItemPresentation()
        let appearance = button.effectiveAppearance
        let paletteAppearance: PaletteAppearance = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        let visualTokens = paletteCatalog.resolve(id: settings.paletteID, appearance: paletteAppearance)

        // Skip redundant redraws. Mutating `button.image`/`length` triggers a
        // status-bar relayout, which re-fires the `effectiveAppearance` KVO
        // observer and calls back into this method. Without this guard the icon
        // repaints in a tight feedback loop, pinning a CPU core.
        if presentation == lastRenderedStatusItemPresentation,
           appearance.name == lastRenderedStatusItemAppearanceName,
           visualTokens.identity == lastRenderedStatusItemPaletteIdentity {
            return
        }
        lastRenderedStatusItemPresentation = presentation
        lastRenderedStatusItemAppearanceName = appearance.name
        lastRenderedStatusItemPaletteIdentity = visualTokens.identity

        let performanceSpan = PerformanceMonitor.shared.begin(.statusRender)
        statusItem?.length = presentation.itemLength
        button.image = statusItemRenderer.render(
            presentation,
            tokens: visualTokens,
            appearance: appearance
        )
        button.toolTip = presentation.tooltip
        button.setAccessibilityLabel("codexU")
        button.setAccessibilityValue(presentation.accessibilityValue)
        PerformanceMonitor.shared.end(performanceSpan)
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

        if CommandLine.arguments.contains("--self-test-palettes") {
            exit(PaletteCatalogSelfTest.run() ? 0 : 1)
        }

        if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-palette-previews"),
           CommandLine.arguments.indices.contains(previewIndex + 1) {
            _ = NSApplication.shared
            let outputURL = URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1], isDirectory: true)
            exit(PalettePreviewRenderer.renderBuiltIns(to: outputURL) ? 0 : 1)
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

        if CommandLine.arguments.contains("--self-test-token-counter") {
            exit(CodexTokenCounterNormalizerSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-model-usage-trend") {
            exit(ModelUsageTrendSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-app-server-pipe") {
            exit(POSIXPipeReaderSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-task-runtime") {
            exit(TaskRuntimeSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-leadership-model") {
            exit(LeadershipModelSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-claude-skill-paths") {
            exit(ClaudeSkillPathResolverSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-codex-session-link") {
            exit(CodexSessionLinkSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-performance-monitor") {
            exit(PerformanceMonitorSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-phase-one-gate") {
            exit(PhaseOneGateSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--evaluate-phase-one-gate") {
            exit(PhaseOneGateCommand.run(arguments: CommandLine.arguments))
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

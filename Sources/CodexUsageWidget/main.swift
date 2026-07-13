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

struct TaskItem: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let chip: String
    let updatedAt: Date?
    let tokens: Int64?
    let kind: TaskColumnKind
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
    let primary: RateWindow?
    let secondary: RateWindow?
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
        primary: nil,
        secondary: nil,
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
            primary: primary,
            secondary: secondary,
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
    let databaseFingerprint: String
    let sourceFingerprint: String
    let analytics: LocalAnalytics
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

    private var fullTimer: Timer?
    private var taskBoardTimer: Timer?
    private var statisticsRolloverTimer: Timer?
    private var systemTimeZoneObserver: NSObjectProtocol?
    private var isRefreshingTaskBoard = false
    private var refreshGeneration: UInt64 = 0
    private var hasPendingRefresh = false
    private var statisticsSnapshotCache: [String: StatisticsSnapshotCacheEntry] = [:]
    private var statisticsSnapshotCacheOrder: [String] = []
    private var statisticsFeedbackTimer: Timer?
    private let statisticsSnapshotCacheLimit = 4
    private let statisticsSnapshotCacheTTL: TimeInterval = 3 * 60

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
        scheduleStatisticsRollover()
        fullTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        taskBoardTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshTaskBoard()
        }
    }

    func stop() {
        fullTimer?.invalidate()
        taskBoardTimer?.invalidate()
        statisticsRolloverTimer?.invalidate()
        statisticsFeedbackTimer?.invalidate()
        if let systemTimeZoneObserver {
            NotificationCenter.default.removeObserver(systemTimeZoneObserver)
            self.systemTimeZoneObserver = nil
        }
    }

    func refresh(queueIfBusy: Bool = false) {
        guard !isRefreshing else {
            if queueIfBusy {
                hasPendingRefresh = true
            }
            return
        }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let preference = statisticsPreference
        isRefreshing = true

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

    private func refreshTaskBoard() {
        guard !isRefreshing, !isRefreshingTaskBoard else { return }
        isRefreshingTaskBoard = true
        let scope = selectedRuntimeScope

        DispatchQueue.global(qos: .utility).async {
            let taskBoard = MultiRuntimeUsageReader().loadTaskBoard(
                scope: scope,
                statisticsPreference: self.statisticsPreference
            )
            DispatchQueue.main.async {
                self.applyTaskBoard(taskBoard, for: scope)
                self.isRefreshingTaskBoard = false
            }
        }
    }

    private func apply(_ multiSnapshot: MultiRuntimeUsageSnapshot) {
        let nextScope = multiSnapshot.defaultScope(
            preferred: selectedRuntimeScope,
            allowedScopes: visibleRuntimeScopes
        )
        multiRuntimeSnapshot = multiSnapshot
        runtimeSnapshots = multiSnapshot.runtimes
        selectedRuntimeScope = nextScope
        snapshot = multiSnapshot.displaySnapshot(for: nextScope)
    }

    private func applyTaskBoard(_ taskBoard: TaskBoard?, for scope: RuntimeScope) {
        guard let index = runtimeSnapshots.firstIndex(where: { $0.scope == scope }) else {
            snapshot = snapshot.replacingTaskBoard(taskBoard)
            return
        }

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
    private let localAnalyticsCacheVersion = 6
    private let sessionUsageCacheVersion = 4
    private static var sessionUsageCache: [String: SessionUsageCacheEntry] = [:]
    private static var persistentSessionUsageCache: [String: SessionUsageCacheEntry]?
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
            primary: appServer.primary,
            secondary: appServer.secondary,
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
        var primary: RateWindow?
        var secondary: RateWindow?
        var credits: CreditsInfo?
        var cloudLifetimeTokens: Int64?
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
        messages.append(contentsOf: appServerMessages)
        let finalSnapshot = snapshot
        lock.unlock()

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
        snapshot.primary = parseRateWindow(limits["primary"])
        snapshot.secondary = parseRateWindow(limits["secondary"])

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

        guard
            let totalsObject = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: totalsQuery).first,
            let recentObjects = Optional(runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: recentQuery)),
            let dailyObjects = Optional(runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: dailyQuery))
        else {
            messages.append("SQLite 查询失败")
            return nil
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
            dbPath: dbPath,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            statistics: context.statistics,
            messages: &messages
        )
        let allProjects = readAllTimeProjects(sqlitePath: sqlitePath, dbPath: dbPath)
        let projectBoard = ProjectBoard(
            recentProjects: analytics.recentProjects.isEmpty
                ? readApproximateRecentProjects(sqlitePath: sqlitePath, dbPath: dbPath, sevenDayStart: sevenDayStart)
                : analytics.recentProjects,
            allProjects: allProjects
        )

        return LocalUsage(
            lifetimeTokens: int64Value(totalsObject["lifetimeTokens"]) ?? 0,
            todayTokens: int64Value(totalsObject["todayTokens"]) ?? 0,
            sevenDayTokens: int64Value(totalsObject["sevenDayTokens"]) ?? 0,
            threadCount: intValue(totalsObject["threadCount"]) ?? 0,
            lastUpdatedAt: dateFromEpoch(totalsObject["lastUpdatedAt"]),
            dailyBuckets: dailyBuckets,
            recentThreads: recent,
            detailedUsage: analytics.detailedUsage,
            usageTrend: analytics.usageTrend ?? readApproximateUsageTrend(
                sqlitePath: sqlitePath,
                dbPath: dbPath,
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
            return LocalAnalytics(detailedUsage: nil, usageTrend: nil, recentProjects: [], toolUsages: [], skillUsages: [])
        }

        let dayKey = statistics.dayKey(for: dayStart)
        let databaseFingerprint = fileFingerprint(paths: [
            dbPath,
            dbPath + "-wal",
            dbPath + "-shm"
        ])
        let sourceFingerprint = sessionSourcesFingerprint(sources)

        if let cached = Self.localAnalyticsCache,
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.timeZoneIdentifier == statistics.resolvedIdentifier,
           cached.databaseFingerprint == databaseFingerprint,
           cached.sourceFingerprint == sourceFingerprint {
            return cached.analytics
        }

        if let cached = readPersistentLocalAnalyticsCache(),
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.timeZoneIdentifier == statistics.resolvedIdentifier,
           cached.databaseFingerprint == databaseFingerprint,
           cached.sourceFingerprint == sourceFingerprint {
            Self.localAnalyticsCache = cached
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
                databaseFingerprint: databaseFingerprint,
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
                sourceQuality: .detailed
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
            databaseFingerprint: databaseFingerprint,
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
        sourceQuality: UsageSourceQuality
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
        dbPath: String,
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

        let rows = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query)
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
            sourceQuality: .approximate
        )
    }

    private func readAllTimeProjects(sqlitePath: String, dbPath: String) -> [ProjectUsage] {
        let query = """
        SELECT cwd, COUNT(*) AS threadCount, COALESCE(SUM(tokens_used), 0) AS tokens, MAX(CASE WHEN recency_at > 0 THEN recency_at ELSE updated_at END) AS lastActiveAt
        FROM threads
        WHERE tokens_used > 0
        GROUP BY cwd
        ORDER BY tokens DESC
        LIMIT 24;
        """

        return runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query).map { row in
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

    private func readApproximateRecentProjects(
        sqlitePath: String,
        dbPath: String,
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

        return runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query).map { row in
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
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
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
        if let cached = Self.sessionUsageCache[source.rolloutPath],
           sameSessionFileIdentity(cached, fileSize: fileSize, modificationDate: modificationDate) {
            return cached
        }

        if let cached = persistentSessionUsageCache()[source.rolloutPath],
           sameSessionFileIdentity(cached, fileSize: fileSize, modificationDate: modificationDate) {
            Self.sessionUsageCache[source.rolloutPath] = cached
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
            Self.sessionUsageCache[source.rolloutPath] = entry
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
        Self.sessionUsageCache[source.rolloutPath] = entry
        return entry
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
              let totalUsage = info["total_token_usage"] as? [String: Any],
              let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp)
        else { return }

        sawTokenEvent = true
        tokenEventCount += 1

        let current = TokenBreakdown(
            inputTokens: int64Value(totalUsage["input_tokens"]) ?? 0,
            cachedInputTokens: int64Value(totalUsage["cached_input_tokens"]) ?? 0,
            outputTokens: int64Value(totalUsage["output_tokens"]) ?? 0,
            reasoningOutputTokens: int64Value(totalUsage["reasoning_output_tokens"]) ?? 0,
            totalTokens: int64Value(totalUsage["total_tokens"]) ?? 0
        )

        var delta = current.delta(from: previous)
        if delta.hasNegativeValue {
            delta = current
        }
        previous = current

        guard !delta.isZero else { return }
        deltas.append(SessionUsageDelta(date: date, tokens: delta))
    }

    private func readTaskBoard(context: RuntimeLoadContext, messages: inout [String]) -> TaskBoard? {
        let calendar = context.statistics.calendar
        let now = context.now
        let dayStart = calendar.startOfDay(for: now)
        let activeCutoff = now.addingTimeInterval(-2 * 60 * 60)

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

        let scheduledItems = readAutomationTasks()

        return TaskBoard(refreshedAt: Date(), columns: [
            TaskColumn(id: .active, title: "进行中", count: activeItems.count, items: activeItems),
            TaskColumn(id: .pending, title: "待处理", count: pendingItems.count, items: pendingItems),
            TaskColumn(id: .scheduled, title: "定时", count: scheduledItems.count, items: scheduledItems),
            TaskColumn(id: .done, title: "完成", count: doneItems.count, items: doneItems)
        ])
    }

    private func makeThreadTaskItem(object: [String: Any], updatedAt: Date?, kind: TaskColumnKind) -> TaskItem {
        let rawId = object["id"] as? String ?? UUID().uuidString
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

        return TaskItem(
            id: rawId + kind.rawValue,
            code: String(code),
            title: title,
            detail: detailParts.joined(separator: " · "),
            chip: chip,
            updatedAt: updatedAt,
            tokens: tokens,
            kind: kind
        )
    }

    private func readAutomationTasks() -> [TaskItem] {
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
            let schedule = scheduleSummary(fields["rrule"])
            let detail = [kind.uppercased(), schedule].filter { !$0.isEmpty }.joined(separator: " · ")

            items.append(TaskItem(
                id: "automation-" + id,
                code: "AUTO-" + id.prefix(4).uppercased(),
                title: name,
                detail: detail,
                chip: kind == "heartbeat" ? "Wake" : "Cron",
                updatedAt: dateFromEpoch(fields["updated_at"]),
                tokens: nil,
                kind: .scheduled
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

        Self.persistentSessionUsageCache = diskCache.entries
        return diskCache.entries
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
        guard let url = sessionUsageCacheURL() else { return }
        let mergedEntries = persistentSessionUsageCache().merging(Self.sessionUsageCache) { _, new in new }
        Self.persistentSessionUsageCache = mergedEntries

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(SessionUsageDiskCache(version: sessionUsageCacheVersion, entries: mergedEntries))
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("failed to write session usage cache: \(error.localizedDescription)")
        }
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

    private func fileFingerprint(paths: [String]) -> String {
        var components: [String] = []
        for path in paths {
            components.append(path)
            guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
                components.append("missing")
                continue
            }
            components.append(String((attributes[.size] as? NSNumber)?.int64Value ?? -1))
            let modifiedMs = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1) * 1000)
            components.append(String(modifiedMs))
        }
        return components.joined(separator: "|")
    }

    private func sessionSourcesFingerprint(_ sources: [SessionUsageSource]) -> String {
        var components: [String] = [String(sources.count)]
        for source in sources {
            components.append(source.threadId)
            components.append(source.rolloutPath)
            components.append(source.model ?? "")
            components.append(source.cwd)
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

final class AppSettings: ObservableObject {
    private static let keepMainWindowOnTopKey = "codexU.keepMainWindowOnTop"
    private static let keepRunningWhenMainWindowClosedKey = "codexU.keepRunningWhenMainWindowClosed"
    private static let visibleRuntimeScopesKey = "codexU.visibleRuntimeScopes"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = WidgetLanguage.storedOrAutomatic(defaults: defaults)
        themeMode = WidgetThemeMode.storedOrAutomatic(defaults: defaults)
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
    @State private var selectedDashboardTab: DashboardTab = .tasks

    static let widgetWidth: CGFloat = 820
    static let widgetDefaultHeight: CGFloat = 720
    static let widgetMinHeight: CGFloat = 620
    static let widgetMaxHeight: CGFloat = 920
    static let windowCornerRadius: CGFloat = 18

    private var snapshot: UsageSnapshot { store.snapshot }
    private var primary: RateWindow? { snapshot.primary }
    private var language: WidgetLanguage { settings.language }
    private var themeMode: WidgetThemeMode { settings.themeMode }
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
        .onAppear {
            themeMode.applyAppearance()
        }
    }

    @ViewBuilder
    private var windowSurface: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(WidgetPalette.sectionTint(effectiveColorScheme)),
                    in: .rect(cornerRadius: Self.windowCornerRadius, style: .continuous)
                )
        } else {
            RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
                .fill(WidgetPalette.sectionFill(effectiveColorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.sectionStroke(effectiveColorScheme), lineWidth: 0.8)
                )
        }
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
                    .fill(WidgetPalette.controlFill(effectiveColorScheme))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(WidgetPalette.controlStroke(effectiveColorScheme), lineWidth: 0.8)
                    )
            )
    }

    private var usageOverviewSection: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(spacing: 8) {
                DualQuotaRing(
                    primary: snapshot.primary,
                    secondary: snapshot.secondary,
                    language: language
                )
                .frame(width: 145, height: 145)

                QuotaResetSummary(
                    primary: snapshot.primary,
                    secondary: snapshot.secondary,
                    language: language
                )
                .frame(width: 154)
            }

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
        case .usage:
            UsageTrendPanel(
                trend: snapshot.local?.usageTrend,
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
            TaskColumn(id: .active, title: localizedTaskColumnTitle(.active, language: language), count: 0, items: []),
            TaskColumn(id: .pending, title: localizedTaskColumnTitle(.pending, language: language), count: 0, items: []),
            TaskColumn(id: .scheduled, title: localizedTaskColumnTitle(.scheduled, language: language), count: 0, items: []),
            TaskColumn(id: .done, title: localizedTaskColumnTitle(.done, language: language), count: 0, items: [])
        ]
    }

    private var shouldShowEnvironmentChecklist: Bool {
        if snapshot.messages.contains("正在读取 codexU 数据") { return false }
        return (!snapshot.messages.isEmpty && (snapshot.primary == nil || snapshot.local == nil))
            || snapshot.account == nil
            || snapshot.local == nil
    }

    private var environmentDiagnostics: [DiagnosticItem] {
        var items: [DiagnosticItem] = []
        let messages = snapshot.messages.joined(separator: "\n")

        if store.selectedRuntimeScope == .claudeCode {
            if snapshot.primary == nil || snapshot.secondary == nil {
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
                    tint: isStale ? WidgetPalette.statusInfo : WidgetPalette.statusWarning
                ))
            }

            if snapshot.local == nil || snapshot.local?.detailedUsage == nil {
                items.append(DiagnosticItem(
                    id: "claude-local-usage",
                    title: language.text("暂无 Claude Code 本机用量记录", "No local Claude Code usage records yet"),
                    detail: language.text("本机 token 统计来自 ~/.claude/projects 下的 transcript JSONL，只读取 usage 和工具名称等结构化字段。", "Local token stats come from transcript JSONL under ~/.claude/projects and only read structured usage and tool names."),
                    systemName: "doc.text.magnifyingglass",
                    tint: WidgetPalette.statusInfo
                ))
            }

            if items.isEmpty {
                items = snapshot.messages.prefix(3).enumerated().map { index, message in
                    DiagnosticItem(
                        id: "claude-message-\(index)",
                        title: language.text("运行提示", "Runtime note"),
                        detail: localizedReaderMessage(message, language: language),
                        systemName: "info.circle.fill",
                        tint: WidgetPalette.statusInfo
                    )
                }
            }

            return items
        }

        if snapshot.primary == nil || snapshot.account == nil {
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

struct SettingsRuntimeMultiSelectControl: View {
    @Environment(\.colorScheme) private var colorScheme
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
                            .font(.system(size: 12, weight: isSelected(scope) ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
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
                .accessibilityLabel(label(for: scope))
                .accessibilityValue(isSelected(scope) ? language.text("已选择", "Selected") : language.text("未选择", "Not selected"))

                if index < RuntimeScope.allCases.count - 1 {
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(WidgetPalette.sectionTint(colorScheme)),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WidgetPalette.sectionFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(WidgetPalette.sectionStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
    }
}

struct CardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(WidgetPalette.cardFill(colorScheme, elevated: elevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(WidgetPalette.cardStroke(colorScheme, elevated: elevated), lineWidth: 0.8)
                    )
            )
    }
}

extension View {
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

struct DualQuotaRing: View {
    let primary: RateWindow?
    let secondary: RateWindow?
    let language: WidgetLanguage

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        ZStack {
            QuotaRingSegment(
                percent: primary?.remainingPercent ?? 0,
                available: primary != nil,
                startColor: quotaPrimaryStartColor,
                endColor: quotaPrimaryEndColor,
                trackColor: quotaPrimaryTrackColor,
                lineWidth: 16
            )
            .frame(width: 145, height: 145)

            QuotaRingSegment(
                percent: secondary?.remainingPercent ?? 0,
                available: secondary != nil,
                startColor: quotaSecondaryStartColor,
                endColor: quotaSecondaryEndColor,
                trackColor: quotaSecondaryTrackColor,
                lineWidth: 16
            )
            .frame(width: 107, height: 107)

            if !accessibilityReduceMotion,
               primary != nil || secondary != nil {
                DualQuotaRingParticles(
                    primaryProgress: progress(primary),
                    secondaryProgress: progress(secondary)
                )
                .frame(width: 145, height: 145)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Circle()
                .fill(WidgetPalette.surfaceTrack)
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                QuotaRingLabel(
                    title: "5h",
                    value: remainingText(primary),
                    color: quotaPrimaryColor
                )
                QuotaRingLabel(
                    title: "7d",
                    value: remainingText(secondary),
                    color: quotaSecondaryColor
                )
                Text(language.text("剩余", "left"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func remainingText(_ window: RateWindow?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private func progress(_ window: RateWindow?) -> CGFloat? {
        window.map { CGFloat(max(0, min(1, $0.remainingPercent / 100))) }
    }
}

struct QuotaRingSegment: View {
    let percent: Double
    let available: Bool
    let startColor: RingRGBColor
    let endColor: RingRGBColor
    let trackColor: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let progress = available ? CGFloat(max(0, min(1, percent / 100))) : 0
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(0, (diameter - lineWidth) / 2)
            let startDegrees = -90.0

            if progress < 0.999 {
                let track = arcPath(
                    center: center,
                    radius: radius,
                    from: progress,
                    to: 1,
                    startDegrees: startDegrees
                )
                context.stroke(
                    track,
                    with: .color(trackColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
            }

            if progress > 0.001 {
                let segmentCount = max(240, Int(ceil(progress * 1_080)))
                let segmentLength = progress / CGFloat(segmentCount)
                let overlap = min(segmentLength * 0.65, CGFloat(0.001))
                for index in 0..<segmentCount {
                    let rawStart = CGFloat(index) / CGFloat(segmentCount) * progress
                    let rawEnd = CGFloat(index + 1) / CGFloat(segmentCount) * progress
                    let t0 = max(0, rawStart - overlap)
                    let t1 = min(progress, rawEnd + overlap)
                    let color = startColor.mixed(to: endColor, fraction: Double(index + 1) / Double(segmentCount)).color
                    let segment = arcPath(
                        center: center,
                        radius: radius,
                        from: t0,
                        to: t1,
                        startDegrees: startDegrees
                    )
                    context.stroke(
                        segment,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                }

                let startPoint = arcPoint(center: center, radius: radius, progress: 0, startDegrees: startDegrees)
                let endPoint = arcPoint(center: center, radius: radius, progress: progress, startDegrees: startDegrees)
                context.fill(
                    Path(ellipseIn: CGRect(x: startPoint.x - lineWidth / 2, y: startPoint.y - lineWidth / 2, width: lineWidth, height: lineWidth)),
                    with: .color(startColor.color)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: endPoint.x - lineWidth / 2, y: endPoint.y - lineWidth / 2, width: lineWidth, height: lineWidth)),
                    with: .color(endColor.color)
                )
            }
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat, startDegrees: Double) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees + Double(start) * 360),
            endAngle: .degrees(startDegrees + Double(end) * 360),
            clockwise: false
        )
        return path
    }

    private func arcPoint(center: CGPoint, radius: CGFloat, progress: CGFloat, startDegrees: Double) -> CGPoint {
        let radians = (startDegrees + Double(progress) * 360) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
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

    let primaryProgress: CGFloat?
    let secondaryProgress: CGFloat?

    func makeNSView(context: Context) -> QuotaRingParticleHostView {
        let view = QuotaRingParticleHostView()
        view.configure(primaryProgress: primaryProgress, secondaryProgress: secondaryProgress)
        return view
    }

    func updateNSView(_ nsView: QuotaRingParticleHostView, context: Context) {
        nsView.configure(primaryProgress: primaryProgress, secondaryProgress: secondaryProgress)
    }

    final class QuotaRingParticleHostView: NSView {
        private let particleContainer = CALayer()
        private var primaryProgress: CGFloat?
        private var secondaryProgress: CGFloat?
        private var renderedSize = CGSize.zero

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false
            particleContainer.masksToBounds = false
            particleContainer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(particleContainer)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            guard renderedSize != bounds.size else { return }
            renderedSize = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particleContainer.frame = bounds
            CATransaction.commit()
            rebuildAnimations()
        }

        func configure(primaryProgress: CGFloat?, secondaryProgress: CGFloat?) {
            let primary = clampedProgress(primaryProgress)
            let secondary = clampedProgress(secondaryProgress)
            guard !equalProgress(primary, self.primaryProgress)
                || !equalProgress(secondary, self.secondaryProgress)
            else { return }

            self.primaryProgress = primary
            self.secondaryProgress = secondary
            rebuildAnimations()
        }

        private func rebuildAnimations() {
            guard bounds.width > 0, bounds.height > 0 else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particleContainer.sublayers?.forEach { $0.removeFromSuperlayer() }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            addParticles(
                center: center,
                radius: 64.5,
                progress: primaryProgress,
                maximumCount: 17,
                phaseOffset: 0
            )
            addParticles(
                center: center,
                radius: 45.5,
                progress: secondaryProgress,
                maximumCount: 12,
                phaseOffset: 0.31
            )
            CATransaction.commit()
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

        private func equalProgress(_ lhs: CGFloat?, _ rhs: CGFloat?) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                true
            case let (.some(lhs), .some(rhs)):
                abs(lhs - rhs) < 0.0001
            default:
                false
            }
        }
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

struct QuotaResetSummary: View {
    let primary: RateWindow?
    let secondary: RateWindow?
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 4) {
            QuotaResetLine(
                title: "5h",
                window: primary,
                color: quotaPrimaryColor,
                language: language
            )
            QuotaResetLine(
                title: "7d",
                window: secondary,
                color: quotaSecondaryColor,
                language: language
            )
        }
    }
}

struct QuotaResetLine: View {
    let title: String
    let window: RateWindow?
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
        guard let resetsAt = window?.resetsAt else { return "--" }
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
                detail: language.text("完成一次 Codex 会话后，这里会显示最近半年的每日 token 热力图。", "After one Codex session, this panel shows a daily token heatmap for the last six months.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: taskColumnIcon(column.id))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(taskAccentColor(column.id))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.code)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let updatedAt = item.updatedAt {
                    Text(relativeTimeText(updatedAt, language: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
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
                TaskChip(text: item.chip, kind: item.kind)
                Spacer(minLength: 4)
                TaskAvatar(text: taskAvatarText(item), kind: item.kind)
            }
        }
        .padding(dashboardRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: dashboardRowCornerRadius, elevated: true)
    }
}

struct TaskAvatar: View {
    let text: String
    let kind: TaskColumnKind

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(taskAccentColor(kind).opacity(0.85))
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

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chipIcon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(chipColor.opacity(0.13))
        )
    }

    private var chipColor: Color {
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

    func mixed(to other: RingRGBColor, fraction: Double) -> RingRGBColor {
        let clamped = max(0, min(1, fraction))
        return RingRGBColor(
            red: red + (other.red - red) * clamped,
            green: green + (other.green - green) * clamped,
            blue: blue + (other.blue - blue) * clamped
        )
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

    static let statusSuccess = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let statusInfo = Color(red: 0.039, green: 0.518, blue: 1.000) // #0A84FF
    static let statusWarning = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let statusDanger = Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A
    static let statusNeutral = Color(red: 0.596, green: 0.596, blue: 0.616) // #98989D
    static let dataReasoning = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2
    static let dataFlowParticle = NSColor.white

    static let surfaceTrack = Color.primary.opacity(0.10)
    static let dataZero = statusNeutral.opacity(0.35)

    static func windowTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.028) : Color.white.opacity(0.050)
    }

    static func sectionTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.040) : Color.white.opacity(0.070)
    }

    static func sectionFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.070) : Color.white.opacity(0.460)
    }

    static func sectionStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.080) : Color.black.opacity(0.060)
    }

    static func cardFill(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(elevated ? 0.140 : 0.100)
        }
        return Color.white.opacity(elevated ? 0.760 : 0.560)
    }

    static func cardStroke(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(elevated ? 0.110 : 0.080)
        }
        return Color.black.opacity(elevated ? 0.075 : 0.055)
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

    if let primary = snapshot.primary {
        object["primary"] = [
            "usedPercent": primary.usedPercent,
            "remainingPercent": primary.remainingPercent,
            "windowDurationMins": jsonValue(primary.windowDurationMins),
            "resetsAt": jsonValue(isoString(primary.resetsAt))
        ] as [String: Any]
    }

    if let secondary = snapshot.secondary {
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
            glass.style = .clear
            glass.tintColor = nil
            glass.contentView = host
            addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.autoresizingMask = [.width, .height]
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
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
        unregisterGlobalHotKey()
        store.stop()
    }

    func toggleMainWindow() {
        guard let window else { return }

        if window.isVisible, !window.isMiniaturized, window.isKeyWindow {
            window.orderOut(nil)
            return
        }

        showMainWindow()
    }

    func applicationDidResignActive(_ notification: Notification) {
        closeStatusPopover()
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
    }

    private func hideMainWindowAfterClose() {
        closeStatusPopover()
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
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
        let popover = NSPopover()
        popover.behavior = .transient
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
    }

    private func closeStatusPopover() {
        statusPopover?.performClose(nil)
        statusPopover = nil
        removeStatusPopoverEventMonitors()
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

        if CommandLine.arguments.contains("--self-test-updates") {
            exit(AppUpdateSelfTest.run() ? 0 : 1)
        }

        if CommandLine.arguments.contains("--self-test-statistics-time-zone") {
            exit(StatisticsTimeZoneSelfTest.run() ? 0 : 1)
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

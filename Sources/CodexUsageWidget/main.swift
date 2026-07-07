import Cocoa
import Carbon.HIToolbox
import Combine
import ServiceManagement
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
    let databaseFingerprint: String
    let sourceFingerprint: String
    let analytics: LocalAnalytics
}

final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot = .empty
    @Published var isRefreshing = false

    private let fullRefreshInterval: TimeInterval = 300
    private let taskBoardRefreshInterval: TimeInterval = 10
    private var fullTimer: Timer?
    private var taskBoardTimer: Timer?
    private var isRefreshingTaskBoard = false

    func start() {
        refresh()
        fullTimer = Timer.scheduledTimer(withTimeInterval: fullRefreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        fullTimer?.tolerance = 60
        taskBoardTimer = Timer.scheduledTimer(withTimeInterval: taskBoardRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshTaskBoard()
        }
        taskBoardTimer?.tolerance = 2
    }

    func startMenuBarMode() {
        refreshQuotaOnly()
        fullTimer = Timer.scheduledTimer(withTimeInterval: fullRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshQuotaOnly()
        }
        fullTimer?.tolerance = 60
    }

    func stop() {
        fullTimer?.invalidate()
        taskBoardTimer?.invalidate()
        fullTimer = nil
        taskBoardTimer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let snapshot = CodexUsageReader().load()
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isRefreshing = false
            }
        }
    }

    func refreshQuotaOnly() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let snapshot = CodexUsageReader().loadQuotaSnapshot()
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isRefreshing = false
            }
        }
    }

    private func refreshTaskBoard() {
        guard !isRefreshing, !isRefreshingTaskBoard else { return }
        isRefreshingTaskBoard = true

        DispatchQueue.global(qos: .utility).async {
            let taskBoard = CodexUsageReader().loadTaskBoard()
            DispatchQueue.main.async {
                self.snapshot = self.snapshot.replacingTaskBoard(taskBoard)
                self.isRefreshingTaskBoard = false
            }
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

    func load() -> UsageSnapshot {
        var messages: [String] = []
        let appServer = readAppServer(messages: &messages)
        let local = readLocalUsage(messages: &messages)
        let taskBoard = readTaskBoard(messages: &messages)

        return UsageSnapshot(
            refreshedAt: Date(),
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

    func loadQuotaSnapshot() -> UsageSnapshot {
        var messages: [String] = []
        let appServer = readAppServer(messages: &messages)

        return UsageSnapshot(
            refreshedAt: Date(),
            account: appServer.account,
            limitId: appServer.limitId,
            limitName: appServer.limitName,
            primary: appServer.primary,
            secondary: appServer.secondary,
            credits: appServer.credits,
            cloudLifetimeTokens: appServer.cloudLifetimeTokens,
            local: nil,
            taskBoard: nil,
            messages: messages
        )
    }

    func loadTaskBoard() -> TaskBoard? {
        var messages: [String] = []
        return readTaskBoard(messages: &messages)
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
        guard let codexPath = firstExistingPath([
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]) else {
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

    private func readLocalUsage(messages: inout [String]) -> LocalUsage? {
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

        let calendar = Calendar.current
        let now = Date()
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
        SELECT date(updated_at, 'unixepoch', 'localtime') AS day, COALESCE(SUM(tokens_used), 0) AS tokens
        FROM threads
        WHERE updated_at >= \(Int(sevenDayStart.timeIntervalSince1970))
        GROUP BY day
        ORDER BY day ASC;
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

        let tokensByDay = Dictionary(uniqueKeysWithValues: dailyObjects.compactMap { object -> (String, Int64)? in
            guard let day = object["day"] as? String else { return nil }
            return (day, int64Value(object["tokens"]) ?? 0)
        })

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
                sevenDayStart: sevenDayStart
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
        messages: inout [String]
    ) -> LocalAnalytics {
        let calendar = Calendar.current
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

        let dayKey = localDayKey(dayStart, calendar: calendar)
        let databaseFingerprint = fileFingerprint(paths: [
            dbPath,
            dbPath + "-wal",
            dbPath + "-shm"
        ])
        let sourceFingerprint = sessionSourcesFingerprint(sources)

        if let cached = Self.localAnalyticsCache,
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.databaseFingerprint == databaseFingerprint,
           cached.sourceFingerprint == sourceFingerprint {
            return cached.analytics
        }

        if let cached = readPersistentLocalAnalyticsCache(),
           cached.version == localAnalyticsCacheVersion,
           cached.dayKey == dayKey,
           cached.databaseFingerprint == databaseFingerprint,
           cached.sourceFingerprint == sourceFingerprint {
            Self.localAnalyticsCache = cached
            return cached.analytics
        }

        var monthComponents = calendar.dateComponents([.year, .month], from: Date())
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
                    let key = localDayKey(delta.date, calendar: calendar)
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
        sevenDayStart: Date
    ) -> UsageTrend? {
        let calendar = Calendar.current
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? sevenDayStart
        var monthComponents = calendar.dateComponents([.year, .month], from: Date())
        monthComponents.day = 1
        monthComponents.hour = 0
        monthComponents.minute = 0
        monthComponents.second = 0
        let monthStart = calendar.date(from: monthComponents) ?? dayStart

        let query = """
        SELECT date(updated_at, 'unixepoch', 'localtime') AS day, COALESCE(SUM(tokens_used), 0) AS tokens
        FROM threads
        WHERE updated_at >= \(Int(trendStart.timeIntervalSince1970))
        GROUP BY day
        ORDER BY day ASC;
        """

        let rows = runSQLiteJSON(sqlitePath: sqlitePath, dbPath: dbPath, query: query)
        guard !rows.isEmpty else { return nil }

        var dailyUsage: [String: PricedTokenUsage] = [:]
        for row in rows {
            guard let key = row["day"] as? String else { continue }
            let tokens = int64Value(row["tokens"]) ?? 0
            dailyUsage[key] = PricedTokenUsage(
                tokens: TokenBreakdown(
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: tokens
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

    private func readTaskBoard(messages: inout [String]) -> TaskBoard? {
        let calendar = Calendar.current
        let now = Date()
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
            ORDER BY recency_at DESC, updated_at DESC
            LIMIT 24;
            """

            let archivedTodayQuery = """
            SELECT id, title, preview, cwd, tokens_used AS tokens, COALESCE(archived_at, updated_at) AS updatedAt, model
            FROM threads
            WHERE archived = 1
              AND COALESCE(archived_at, updated_at) >= \(Int(dayStart.timeIntervalSince1970))
            ORDER BY COALESCE(archived_at, updated_at) DESC
            LIMIT 12;
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
            TaskColumn(id: .active, title: "进行中", count: activeItems.count, items: Array(activeItems.prefix(3))),
            TaskColumn(id: .pending, title: "待处理", count: pendingItems.count, items: Array(pendingItems.prefix(3))),
            TaskColumn(id: .scheduled, title: "定时", count: scheduledItems.count, items: Array(scheduledItems.prefix(3))),
            TaskColumn(id: .done, title: "完成", count: doneItems.count, items: Array(doneItems.prefix(3)))
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

enum MenuBarQuotaStyle: String, CaseIterable, Equatable {
    case vertical
    case horizontal
    case ring
    case text

    static let storageKey = "codexU.menuBarQuotaStyle"

    static func stored(defaults: UserDefaults = .standard) -> MenuBarQuotaStyle {
        guard let rawValue = defaults.string(forKey: storageKey),
              let style = MenuBarQuotaStyle(rawValue: rawValue)
        else { return .vertical }
        return style
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    func title(language: WidgetLanguage) -> String {
        switch self {
        case .vertical:
            return language.text("垂直进度条", "Vertical bars")
        case .horizontal:
            return language.text("横向进度条", "Horizontal bars")
        case .ring:
            return language.text("环形进度条", "Rings")
        case .text:
            return language.text("纯文字", "Text only")
        }
    }
}

enum MenuBarQuotaCountMode: String, CaseIterable, Equatable {
    case remaining
    case used

    static let storageKey = "codexU.menuBarQuotaCountMode"

    static func stored(defaults: UserDefaults = .standard) -> MenuBarQuotaCountMode {
        guard let rawValue = defaults.string(forKey: storageKey),
              let mode = MenuBarQuotaCountMode(rawValue: rawValue)
        else { return .remaining }
        return mode
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    func title(language: WidgetLanguage) -> String {
        switch self {
        case .remaining:
            return language.text("倒计数：剩余额度", "Countdown: remaining")
        case .used:
            return language.text("正计数：已用额度", "Count up: used")
        }
    }

    func shortLabel(language: WidgetLanguage) -> String {
        switch self {
        case .remaining:
            return language.text("剩余", "left")
        case .used:
            return language.text("已用", "used")
        }
    }

    func percent(for window: RateWindow) -> Double {
        switch self {
        case .remaining:
            return window.remainingPercent
        case .used:
            return max(0, min(100, window.usedPercent))
        }
    }
}

enum MenuBarQuotaIndicatorPreference {
    static let storageKey = "codexU.showMenuBarQuotaIndicator"

    static func stored(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: storageKey) != nil else { return false }
        return defaults.bool(forKey: storageKey)
    }

    static func persist(_ isVisible: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isVisible, forKey: storageKey)
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
    @ObservedObject var windowState: WindowPresentationState
    @Environment(\.colorScheme) private var colorScheme
    @State private var language = WidgetLanguage.storedOrAutomatic()
    @State private var themeMode = WidgetThemeMode.storedOrAutomatic()
    @State private var selectedDashboardTab: DashboardTab = .tasks
    @State private var isQuotaIndicatorVisible = MenuBarQuotaIndicatorPreference.stored()
    let onPinnedFrontChange: (Bool) -> Void
    let onQuotaIndicatorVisibilityChange: (Bool) -> Void

    static let widgetWidth: CGFloat = 820
    static let widgetDefaultHeight: CGFloat = 720
    static let widgetMinHeight: CGFloat = 620
    static let widgetMaxHeight: CGFloat = 920

    private var snapshot: UsageSnapshot { store.snapshot }
    private var primary: RateWindow? { snapshot.primary }
    private var effectiveColorScheme: ColorScheme {
        themeMode.preferredColorScheme ?? colorScheme
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    widgetContent
                        .glassEffect(
                            .regular.tint(WidgetPalette.windowTint(effectiveColorScheme)),
                            in: .rect(cornerRadius: 24, style: .continuous)
                        )
                }
            } else {
                widgetContent
            }
        }
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(themeMode.preferredColorScheme)
        .onAppear {
            themeMode.applyAppearance()
        }
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: Self.widgetWidth, alignment: .topLeading)
        .frame(minHeight: Self.widgetMinHeight, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text("codexU")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            ThemeSwitch(themeMode: themeMode, language: language) { selectedMode in
                themeMode = selectedMode
                selectedMode.persist()
                selectedMode.applyAppearance()
            }
            LanguageSwitch(language: language) { selectedLanguage in
                language = selectedLanguage
                selectedLanguage.persist()
            }
            planPill
            headerActionGroup
        }
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

    private var planPill: some View {
        statusPill(planLabel)
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

    private var headerActionGroup: some View {
        let isPinned = windowState.isPinnedToFront

        return HStack(spacing: 2) {
            HeaderActionButton(
                systemName: isQuotaIndicatorVisible ? "chart.bar.fill" : "chart.bar",
                isActive: isQuotaIndicatorVisible,
                help: language.text("显示菜单栏额度", "Show menu bar quota"),
                accessibilityLabel: language.text("显示菜单栏额度", "Show menu bar quota"),
                accessibilityValue: isQuotaIndicatorVisible ? language.text("已开启", "On") : language.text("未开启", "Off")
            ) {
                isQuotaIndicatorVisible.toggle()
                MenuBarQuotaIndicatorPreference.persist(isQuotaIndicatorVisible)
                onQuotaIndicatorVisibilityChange(isQuotaIndicatorVisible)
            }

            HeaderActionButton(
                systemName: isPinned ? "pin.fill" : "pin",
                isActive: isPinned,
                help: language.text("固定前台", "Pin to front"),
                accessibilityLabel: language.text("固定前台", "Pin to front"),
                accessibilityValue: isPinned ? language.text("已开启", "On") : language.text("未开启", "Off")
            ) {
                onPinnedFrontChange(!isPinned)
            }

            HeaderActionButton(
                systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise",
                help: language.text("刷新", "Refresh"),
                accessibilityLabel: language.text("刷新", "Refresh")
            ) {
                store.refresh()
            }

            HeaderActionButton(
                systemName: "xmark",
                hoverTint: WidgetPalette.statusDanger,
                help: language.text("退出", "Quit"),
                accessibilityLabel: language.text("退出", "Quit")
            ) {
                NSApp.terminate(nil)
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
            UsageTrendPanel(trend: snapshot.local?.usageTrend, language: language)
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
            Spacer()
            Text("\(language.text("刷新", "Refreshed")) \(timeOnly(snapshot.refreshedAt, language: language))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("⌘U")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var planLabel: String {
        snapshot.account?.planType?.uppercased() ?? "LOCAL"
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

        if snapshot.primary == nil || snapshot.account == nil {
            if messages.contains("未找到 codex") {
                items.append(DiagnosticItem(
                    id: "codex-missing",
                    title: language.text("未找到 Codex", "Codex not found"),
                    detail: language.text("请先安装 Codex App，或确认 codex CLI 位于 /Applications/Codex.app、/opt/homebrew/bin 或 /usr/local/bin。", "Install Codex App first, or make sure the codex CLI is in /Applications/Codex.app, /opt/homebrew/bin, or /usr/local/bin."),
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
                .frame(width: headerActionButtonSize, height: headerActionButtonSize)
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
                maxValue: maxValue,
                accent: accent
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
    let accent: Color

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
                    .fill(accent)
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
            let remainingValue = max(maxValue - subscriptionCeiling, 1)
            fraction = subscriptionBand + (1 - subscriptionBand) * ((clamped - subscriptionCeiling) / remainingValue)
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

struct UsageTrendPanel: View {
    let trend: UsageTrend?
    let language: WidgetLanguage

    var body: some View {
        if let trend {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: usageTrendCardSpacing) {
                    UsageHeatmapCard(trend: trend, language: language)
                        .frame(
                            width: usageTrendHeatmapCardWidth(
                                containerWidth: geometry.size.width,
                                weekCount: trend.heatmapWeeks.count
                            ),
                            height: usageTrendCardHeight,
                            alignment: .topLeading
                        )
                    UsageSevenDaySummaryCard(trend: trend, language: language)
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

                UsageHeatmapView(trend: trend, language: language)

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
    let language: WidgetLanguage

    private let cellSize: CGFloat = heatmapCellSize
    private let cellSpacing: CGFloat = usageHeatmapCellSpacing
    private let weekdayLabelWidth: CGFloat = usageHeatmapWeekdayLabelWidth

    private struct MonthMarker: Identifiable {
        let id: Int
        let columnIndex: Int
        let title: String
    }

    var body: some View {
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
                    ForEach(Array(trend.heatmapWeeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { cell in
                                if cell.isFuture {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.clear)
                                        .frame(width: cellSize, height: cellSize)
                                } else {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(heatmapColor(level: heatLevel(cell.tokens)))
                                        .frame(width: cellSize, height: cellSize)
                                        .help(heatTooltip(cell))
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
        .padding(.top, 4)
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
}

struct UsageSevenDaySummaryCard: View {
    let trend: UsageTrend
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

                SevenDayLineChart(buckets: lastSevenDayBuckets, language: language)
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
    let language: WidgetLanguage

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
                        Circle()
                            .fill(buckets[index].tokens > 0 ? WidgetPalette.brandSecondary : WidgetPalette.surfaceTrack)
                            .frame(width: 6, height: 6)
                            .position(point)
                            .help(dayTooltip(buckets[index]))
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

    private func dayTooltip(_ bucket: UsageDayBucket) -> String {
        "\(fullDateText(bucket.date, language: language)) · \(formatTokens(bucket.tokens)) tokens"
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

private enum WidgetPalette {
    static let brandPrimaryRGB = RingRGBColor(red: 0.157, green: 0.400, blue: 0.969) // #2866F7
    static let brandPrimaryStrongRGB = RingRGBColor(red: 0.122, green: 0.349, blue: 0.929) // #1F59ED
    static let brandPrimaryLightRGB = RingRGBColor(red: 0.482, green: 0.627, blue: 1.000) // #7BA0FF
    static let brandSecondaryRGB = RingRGBColor(red: 0.545, green: 0.427, blue: 1.000) // #8B6DFF
    static let brandHighlightRGB = RingRGBColor(red: 0.855, green: 0.639, blue: 0.980) // #DAA3FA

    static let brandPrimary = brandPrimaryRGB.color
    static let brandPrimaryStrong = brandPrimaryStrongRGB.color
    static let brandPrimaryLight = brandPrimaryLightRGB.color
    static let brandSecondary = brandSecondaryRGB.color
    static let brandHighlight = brandHighlightRGB.color

    static let statusSuccess = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let statusInfo = Color(red: 0.039, green: 0.518, blue: 1.000) // #0A84FF
    static let statusWarning = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let statusDanger = Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A
    static let statusNeutral = Color(red: 0.596, green: 0.596, blue: 0.616) // #98989D
    static let dataReasoning = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2

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
private let headerActionButtonSize: CGFloat = 28
private let dashboardTabSegmentWidth: CGFloat = 96
private let dashboardTabIconWidth: CGFloat = 14
private let dashboardTabHorizontalPadding: CGFloat = 10
private let dashboardCardIconSize: CGFloat = 12
private let dashboardCardIconFrame: CGFloat = 18
private let dashboardCardTitleSize: CGFloat = 11
private let dashboardListRowSpacing: CGFloat = 6
private let dashboardRowPadding: CGFloat = 7
private let dashboardRowCornerRadius: CGFloat = 8
private let usageTrendCardHeight: CGFloat = 214
private let usageTrendCardSpacing: CGFloat = dashboardGridSpacing
private let usageSevenDayMinimumCardWidth: CGFloat = 260
private let usageHeatmapCellSpacing: CGFloat = 4
private let usageHeatmapWeekdayLabelWidth: CGFloat = 20
private let usageHeatmapMonthLabelWidth: CGFloat = 42
private let usageHeatmapMonthLabelHeight: CGFloat = 16
private let heatmapCellSize: CGFloat = 10

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
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func formatTokens(_ value: Int64?) -> String {
    guard let value else { return "--" }
    let absValue = abs(Double(value))
    if absValue >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if absValue >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
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

final class DesktopWidgetWindow: NSPanel {
    private static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        level = Self.desktopLevel
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func moveToDesktopLayer() {
        level = Self.desktopLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        orderFrontRegardless()
    }

    func moveToFrontLayer() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private struct QuotaRenderState: Equatable {
        let primary: RateWindow?
        let secondary: RateWindow?
        let messages: [String]
    }

    private let store = UsageStore()
    private let windowState = WindowPresentationState()
    private var window: DesktopWidgetWindow?
    private var mainStatusItem: NSStatusItem?
    private var quotaStatusItem: NSStatusItem?
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?
    private var isFrontMode = false
    private var menuBarStyle = MenuBarQuotaStyle.stored()
    private var quotaCountMode = MenuBarQuotaCountMode.stored()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        WidgetThemeMode.storedOrAutomatic().applyAppearance()
        debugLog("app launched bundle=\(Bundle.main.bundlePath)")

        createDesktopWidgetWindow()
        setupMainStatusItem()
        setQuotaStatusItemVisible(MenuBarQuotaIndicatorPreference.stored())
        observeStore()
        registerGlobalHotKey()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
        store.stop()
    }

    func toggleWindowLayer() {
        guard let window else { return }
        if windowState.isPinnedToFront {
            setPinnedToFront(false)
            return
        }

        if isFrontMode {
            leaveFrontModeIfNeeded()
        } else {
            window.moveToFrontLayer()
            isFrontMode = true
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        leaveFrontModeIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !NSApp.isActive, !self.windowState.isPinnedToFront else { return }
            self.leaveFrontModeIfNeeded()
        }
    }

    private func setPinnedToFront(_ isPinned: Bool) {
        guard let window else {
            windowState.isPinnedToFront = false
            return
        }

        windowState.isPinnedToFront = isPinned
        if isPinned {
            window.moveToFrontLayer()
            isFrontMode = true
        } else {
            leaveFrontModeIfNeeded(force: true)
        }
        updateMainStatusItemTooltip()
    }

    private func leaveFrontModeIfNeeded(force: Bool = false) {
        guard isFrontMode, let window else { return }
        guard force || !windowState.isPinnedToFront else { return }
        window.moveToDesktopLayer()
        isFrontMode = false
    }

    @objc private func statusItemClicked() {
        toggleWindowLayer()
    }

    private func createDesktopWidgetWindow() {
        let width = UsageWidgetView.widgetWidth
        let height = UsageWidgetView.widgetDefaultHeight
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: max(screenFrame.minX + 16, screenFrame.maxX - width - 28),
            y: max(screenFrame.minY + 16, screenFrame.maxY - height - 36)
        )

        let panel = DesktopWidgetWindow(contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)))
        panel.delegate = self
        panel.minSize = CGSize(width: UsageWidgetView.widgetWidth, height: UsageWidgetView.widgetMinHeight)
        panel.maxSize = CGSize(width: UsageWidgetView.widgetWidth, height: UsageWidgetView.widgetMaxHeight)
        panel.contentMinSize = panel.minSize
        panel.contentMaxSize = panel.maxSize
        panel.contentView = GlassHostingContainer(
            rootView: UsageWidgetView(
                store: store,
                windowState: windowState,
                onPinnedFrontChange: { [weak self] isPinned in
                    self?.setPinnedToFront(isPinned)
                },
                onQuotaIndicatorVisibilityChange: { [weak self] isVisible in
                    self?.setQuotaStatusItemVisible(isVisible)
                }
            ),
            cornerRadius: 24
        )
        panel.moveToDesktopLayer()
        window = panel
    }

    private func setupMainStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        mainStatusItem = item

        guard let button = item.button else { return }
        if let image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "codexU") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "C"
        }
        updateMainStatusItemTooltip()
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func updateMainStatusItemTooltip() {
        guard let button = mainStatusItem?.button else { return }
        button.toolTip = windowState.isPinnedToFront
            ? "codexU：已固定前台，点击或按 ⌘U 取消固定"
            : "codexU：点击临时唤到前台，快捷键 ⌘U"
    }

    private func setupQuotaStatusItem() {
        guard quotaStatusItem == nil else {
            updateQuotaStatusItem()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: menuBarImageSize(for: menuBarStyle).width + 4)
        quotaStatusItem = item

        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        item.menu = makeQuotaStatusMenu()
        updateQuotaStatusItem()
    }

    private func setQuotaStatusItemVisible(_ isVisible: Bool) {
        MenuBarQuotaIndicatorPreference.persist(isVisible)

        if isVisible {
            setupQuotaStatusItem()
        } else if let quotaStatusItem {
            NSStatusBar.system.removeStatusItem(quotaStatusItem)
            self.quotaStatusItem = nil
        }
    }

    private func observeStore() {
        store.$snapshot
            .map { snapshot in
                QuotaRenderState(
                    primary: snapshot.primary,
                    secondary: snapshot.secondary,
                    messages: snapshot.messages
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateQuotaStatusItem()
            }
            .store(in: &cancellables)
    }

    private func updateQuotaStatusItem() {
        guard let button = quotaStatusItem?.button else { return }
        quotaStatusItem?.length = menuBarImageSize(for: menuBarStyle).width + 4
        button.image = makeStatusBarImage(snapshot: store.snapshot, style: menuBarStyle)
        button.toolTip = statusTooltip(snapshot: store.snapshot)
    }

    private func makeQuotaStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateQuotaStatusMenu(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateQuotaStatusMenu(menu)
    }

    private func populateQuotaStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let language = WidgetLanguage.storedOrAutomatic()
        let snapshot = store.snapshot

        let titleItem = NSMenuItem(title: "codexU", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let primaryTitle = language.text("5 小时额度", "5-hour quota")
        let secondaryTitle = language.text("7 天额度", "7-day quota")
        menu.addItem(disabledMenuItem("\(primaryTitle)：\(quotaMenuText(snapshot.primary, language: language))"))
        menu.addItem(disabledMenuItem("\(language.text("重置", "Reset"))：\(resetMenuText(snapshot.primary, language: language))"))
        menu.addItem(disabledMenuItem("\(secondaryTitle)：\(quotaMenuText(snapshot.secondary, language: language))"))
        menu.addItem(disabledMenuItem("\(language.text("重置", "Reset"))：\(resetMenuText(snapshot.secondary, language: language))"))
        menu.addItem(disabledMenuItem("\(language.text("刷新时间", "Refreshed"))：\(timeOnly(snapshot.refreshedAt, language: language))"))

        if !snapshot.messages.isEmpty, snapshot.primary == nil || snapshot.secondary == nil {
            menu.addItem(disabledMenuItem(localizedReaderMessage(snapshot.messages[0], language: language)))
        }

        menu.addItem(NSMenuItem.separator())

        let styleMenu = NSMenu()
        for style in MenuBarQuotaStyle.allCases {
            let item = NSMenuItem(title: style.title(language: language), action: #selector(setMenuBarStyleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == menuBarStyle ? .on : .off
            styleMenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: language.text("显示方式", "Display style"), action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let countModeMenu = NSMenu()
        for mode in MenuBarQuotaCountMode.allCases {
            let item = NSMenuItem(title: mode.title(language: language), action: #selector(setQuotaCountModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == quotaCountMode ? .on : .off
            countModeMenu.addItem(item)
        }
        let countModeItem = NSMenuItem(title: language.text("计数方式", "Count mode"), action: nil, keyEquivalent: "")
        countModeItem.submenu = countModeMenu
        menu.addItem(countModeItem)

        let refreshItem = NSMenuItem(
            title: store.isRefreshing ? language.text("正在刷新...", "Refreshing...") : language.text("刷新额度", "Refresh quota"),
            action: #selector(refreshQuotaFromMenu),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !store.isRefreshing
        menu.addItem(refreshItem)

        let launchAtLoginItem = NSMenuItem(
            title: launchAtLoginMenuTitle(language: language),
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: language.text("退出 codexU", "Quit codexU"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func setMenuBarStyleFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = MenuBarQuotaStyle(rawValue: rawValue)
        else { return }
        menuBarStyle = style
        style.persist()
        updateQuotaStatusItem()
    }

    @objc private func setQuotaCountModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MenuBarQuotaCountMode(rawValue: rawValue)
        else { return }
        quotaCountMode = mode
        mode.persist()
        updateQuotaStatusItem()
    }

    @objc private func refreshQuotaFromMenu() {
        store.refresh()
    }

    @objc private func toggleLaunchAtLoginFromMenu() {
        let language = WidgetLanguage.storedOrAutomatic()
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showLaunchAtLoginError(error, language: language)
        }
        updateQuotaStatusItem()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func launchAtLoginMenuTitle(language: WidgetLanguage) -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return language.text("开机自动启动", "Launch at Login")
        case .requiresApproval:
            return language.text("开机自动启动（需系统确认）", "Launch at Login (needs approval)")
        case .notRegistered:
            return language.text("开机自动启动", "Launch at Login")
        case .notFound:
            return language.text("开机自动启动（不可用）", "Launch at Login (unavailable)")
        @unknown default:
            return language.text("开机自动启动", "Launch at Login")
        }
    }

    private func showLaunchAtLoginError(_ error: Error, language: WidgetLanguage) {
        let alert = NSAlert()
        alert.messageText = language.text("无法修改开机自动启动", "Could not change Launch at Login")
        alert.informativeText = language.text(
            "请确认 codexU 已安装到 Applications，并在系统设置 > 通用 > 登录项中允许。",
            "Make sure codexU is installed in Applications, then allow it in System Settings > General > Login Items."
        ) + "\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: language.text("好", "OK"))
        alert.runModal()
    }

    private func statusTooltip(snapshot: UsageSnapshot) -> String {
        let language = WidgetLanguage.storedOrAutomatic()
        guard snapshot.primary != nil || snapshot.secondary != nil else {
            return language.text("codexU：正在读取额度", "codexU: reading quota")
        }

        return "codexU: \(quotaCountMode.shortLabel(language: language)) · 5h \(quotaPercentText(snapshot.primary)) · 7d \(quotaPercentText(snapshot.secondary))"
    }

    private func quotaMenuText(_ window: RateWindow?, language: WidgetLanguage) -> String {
        guard let window else { return language.text("读取中", "Loading") }
        return "\(quotaPercentText(window)) \(quotaCountMode.shortLabel(language: language))"
    }

    private func resetMenuText(_ window: RateWindow?, language: WidgetLanguage) -> String {
        guard let resetsAt = window?.resetsAt else { return language.text("暂无", "Unavailable") }
        return resetDateTime(resetsAt, language: language)
    }

    private func quotaPercentText(_ window: RateWindow?) -> String {
        guard let window else { return "--%" }
        return "\(Int(quotaCountMode.percent(for: window).rounded()))%"
    }

    private func quotaNumberText(_ window: RateWindow?) -> String {
        guard let window else { return "--" }
        return "\(Int(quotaCountMode.percent(for: window).rounded()))"
    }

    private func quotaPercentValue(_ window: RateWindow?) -> Double? {
        guard let window else { return nil }
        return quotaCountMode.percent(for: window)
    }

    private func menuBarImageSize(for style: MenuBarQuotaStyle) -> NSSize {
        switch style {
        case .vertical:
            return NSSize(width: 64, height: 18)
        case .horizontal:
            return NSSize(width: 142, height: 22)
        case .ring:
            return NSSize(width: 54, height: 20)
        case .text:
            return NSSize(width: 96, height: 20)
        }
    }

    private func primaryQuotaColor(available: Bool) -> NSColor {
        available ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.38)
    }

    private func secondaryQuotaColor(available: Bool) -> NSColor {
        available ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.38)
    }

    private func makeStatusBarImage(snapshot: UsageSnapshot, style: MenuBarQuotaStyle) -> NSImage {
        let size = menuBarImageSize(for: style)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        switch style {
        case .vertical:
            drawVerticalQuotaBars(snapshot: snapshot, in: NSRect(origin: .zero, size: size))
        case .horizontal:
            drawHorizontalQuotaBars(snapshot: snapshot, in: NSRect(origin: .zero, size: size))
        case .ring:
            drawQuotaRings(snapshot: snapshot, in: NSRect(origin: .zero, size: size))
        case .text:
            drawTextQuota(snapshot: snapshot, in: NSRect(origin: .zero, size: size))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawVerticalQuotaBars(snapshot: UsageSnapshot, in rect: NSRect) {
        let trackColor = NSColor.labelColor.withAlphaComponent(0.18)
        let primaryColor = primaryQuotaColor(available: snapshot.primary != nil)
        let secondaryColor = secondaryQuotaColor(available: snapshot.secondary != nil)
        let barWidth: CGFloat = 4
        let barHeight: CGFloat = 14
        let y = rect.midY - barHeight / 2
        let primaryRect = NSRect(x: 2, y: y, width: barWidth, height: barHeight)
        let secondaryRect = NSRect(x: 30, y: y, width: barWidth, height: barHeight)

        drawVerticalQuotaBar(in: primaryRect, percent: quotaPercentValue(snapshot.primary), trackColor: trackColor, fillColor: primaryColor)
        drawVerticalQuotaBar(in: secondaryRect, percent: quotaPercentValue(snapshot.secondary), trackColor: trackColor, fillColor: secondaryColor)
        drawQuotaNumber(quotaNumberText(snapshot.primary), in: NSRect(x: 8, y: 1.7, width: 21, height: 14), color: primaryColor)
        drawQuotaNumber(quotaNumberText(snapshot.secondary), in: NSRect(x: 36, y: 1.7, width: 21, height: 14), color: secondaryColor)
    }

    private func drawVerticalQuotaBar(in rect: NSRect, percent: Double?, trackColor: NSColor, fillColor: NSColor) {
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        trackColor.setFill()
        trackPath.fill()

        guard let percent else { return }
        let progress = max(0, min(1, percent / 100))
        guard progress > 0 else { return }
        let fillHeight = max(1, rect.height * CGFloat(progress))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillHeight)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        fillColor.setFill()
        fillPath.fill()
    }

    private func drawHorizontalQuotaBars(snapshot: UsageSnapshot, in rect: NSRect) {
        let trackColor = NSColor.labelColor.withAlphaComponent(0.18)
        let primaryColor = primaryQuotaColor(available: snapshot.primary != nil)
        let secondaryColor = secondaryQuotaColor(available: snapshot.secondary != nil)
        let countdownColor = NSColor.labelColor.withAlphaComponent(0.52)
        let xOffset: CGFloat = 5
        let barWidth: CGFloat = 38
        let barHeight: CGFloat = 4
        let primaryRect = NSRect(x: xOffset + 20, y: 15.0, width: barWidth, height: barHeight)
        let secondaryRect = NSRect(x: xOffset + 20, y: 2.8, width: barWidth, height: barHeight)

        drawSmallQuotaLabel("5h", in: NSRect(x: xOffset, y: 10.8, width: 17, height: 12), color: primaryColor)
        drawSmallQuotaLabel("7d", in: NSRect(x: xOffset, y: -1.4, width: 17, height: 12), color: secondaryColor)
        drawHorizontalQuotaBar(in: primaryRect, percent: quotaPercentValue(snapshot.primary), trackColor: trackColor, fillColor: primaryColor)
        drawHorizontalQuotaBar(in: secondaryRect, percent: quotaPercentValue(snapshot.secondary), trackColor: trackColor, fillColor: secondaryColor)
        drawQuotaPercentNumber(quotaPercentText(snapshot.primary), in: NSRect(x: xOffset + 62, y: 10.8, width: 34, height: 12), color: primaryColor)
        drawQuotaPercentNumber(quotaPercentText(snapshot.secondary), in: NSRect(x: xOffset + 62, y: -1.4, width: 34, height: 12), color: secondaryColor)
        drawHorizontalCountdown(compactResetCountdown(snapshot.primary), in: NSRect(x: xOffset + 96, y: 11.0, width: 38, height: 11), color: countdownColor)
        drawHorizontalCountdown(compactResetCountdown(snapshot.secondary), in: NSRect(x: xOffset + 96, y: -1.2, width: 38, height: 11), color: countdownColor)
    }

    private func drawHorizontalQuotaBar(in rect: NSRect, percent: Double?, trackColor: NSColor, fillColor: NSColor) {
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        trackColor.setFill()
        trackPath.fill()

        guard let percent else { return }
        let progress = max(0, min(1, percent / 100))
        guard progress > 0 else { return }
        let fillWidth = max(1, rect.width * CGFloat(progress))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fillColor.setFill()
        fillPath.fill()
    }

    private func drawSmallQuotaLabel(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.2, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func drawHorizontalCountdown(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.0, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func drawQuotaRings(snapshot: UsageSnapshot, in rect: NSRect) {
        let trackColor = NSColor.labelColor.withAlphaComponent(0.18)
        let primaryColor = primaryQuotaColor(available: snapshot.primary != nil)
        let secondaryColor = secondaryQuotaColor(available: snapshot.secondary != nil)
        drawQuotaRing(
            center: NSPoint(x: 10.5, y: rect.midY),
            radius: 8.2,
            percent: quotaPercentValue(snapshot.primary),
            trackColor: trackColor,
            fillColor: primaryColor
        )
        drawCenteredQuotaNumber(quotaNumberText(snapshot.primary), in: NSRect(x: 1.7, y: 5.2, width: 17.6, height: 10), color: primaryColor)
        drawQuotaRing(
            center: NSPoint(x: 42.5, y: rect.midY),
            radius: 8.2,
            percent: quotaPercentValue(snapshot.secondary),
            trackColor: trackColor,
            fillColor: secondaryColor
        )
        drawCenteredQuotaNumber(quotaNumberText(snapshot.secondary), in: NSRect(x: 33.7, y: 5.2, width: 17.6, height: 10), color: secondaryColor)
    }

    private func drawQuotaRing(center: NSPoint, radius: CGFloat, percent: Double?, trackColor: NSColor, fillColor: NSColor) {
        let lineWidth: CGFloat = 1.7
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = lineWidth
        trackColor.setStroke()
        trackPath.stroke()

        guard let percent else { return }
        let progress = max(0, min(1, percent / 100))
        guard progress > 0 else { return }
        let progressPath = NSBezierPath()
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(progress) * 360,
            clockwise: true
        )
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = lineWidth
        fillColor.setStroke()
        progressPath.stroke()
    }

    private func drawTextQuota(snapshot: UsageSnapshot, in rect: NSRect) {
        let primaryColor = primaryQuotaColor(available: snapshot.primary != nil)
        let secondaryColor = secondaryQuotaColor(available: snapshot.secondary != nil)
        let countdownColor = NSColor.labelColor.withAlphaComponent(0.58)
        drawQuotaTextLine("5h \(quotaPercentText(snapshot.primary))", in: NSRect(x: 0, y: 10.0, width: 48, height: 10), color: primaryColor, alignment: .left)
        drawQuotaTextLine(compactResetCountdown(snapshot.primary), in: NSRect(x: 50, y: 10.0, width: 46, height: 10), color: countdownColor, alignment: .left)
        drawQuotaTextLine("7d \(quotaPercentText(snapshot.secondary))", in: NSRect(x: 0, y: -0.8, width: 48, height: 10), color: secondaryColor, alignment: .left)
        drawQuotaTextLine(compactResetCountdown(snapshot.secondary), in: NSRect(x: 50, y: -0.8, width: 46, height: 10), color: countdownColor, alignment: .left)
    }

    private func compactResetCountdown(_ window: RateWindow?) -> String {
        guard let resetsAt = window?.resetsAt else { return "--" }
        let remaining = max(0, Int(resetsAt.timeIntervalSince(Date()).rounded(.down)))
        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60

        if days > 0 {
            return "\(days)d\(hours)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    private func drawQuotaTextLine(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.4, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func drawQuotaNumber(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func drawQuotaPercentNumber(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.4, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func drawCenteredQuotaNumber(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: text.count >= 3 ? 7.0 : 7.9, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private func registerGlobalHotKey() {
        debugLog("register global hotkey command+u")
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
                    delegate.toggleWindowLayer()
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
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CDXU"), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_U),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &globalHotKeyRef
        )
        if hotKeyStatus == noErr {
            debugLog("global hotkey registered")
        } else {
            debugLog("RegisterEventHotKey failed status=\(hotKeyStatus)")
        }
    }

    private func unregisterGlobalHotKey() {
        if let globalHotKeyRef {
            UnregisterEventHotKey(globalHotKeyRef)
        }
        if let globalHotKeyHandler {
            RemoveEventHandler(globalHotKeyHandler)
        }
        globalHotKeyRef = nil
        globalHotKeyHandler = nil
    }
}

@main
struct codexUMain {
    static func main() {
        if CommandLine.arguments.contains("--dump-json") {
            dumpJSON(CodexUsageReader().load())
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

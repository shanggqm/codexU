import Cocoa
import Carbon.HIToolbox
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

struct TokenBreakdown: Equatable {
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

struct PricedTokenUsage: Equatable {
    var tokens: TokenBreakdown
    var estimatedCostUSD: Double

    static let zero = PricedTokenUsage(tokens: .zero, estimatedCostUSD: 0)

    mutating func add(tokens addedTokens: TokenBreakdown, costUSD: Double) {
        tokens.add(addedTokens)
        estimatedCostUSD += costUSD
    }
}

struct DetailedUsage: Equatable {
    let today: PricedTokenUsage
    let sevenDay: PricedTokenUsage
    let month: PricedTokenUsage
    let lifetime: PricedTokenUsage
    let parsedFileCount: Int
    let tokenEventCount: Int
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

    func mergingLocalData(from localSnapshot: UsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: localSnapshot.refreshedAt,
            account: account,
            limitId: limitId,
            limitName: limitName,
            primary: primary,
            secondary: secondary,
            credits: credits,
            cloudLifetimeTokens: cloudLifetimeTokens,
            local: localSnapshot.local,
            taskBoard: localSnapshot.taskBoard,
            messages: localSnapshot.messages
        )
    }

    func mergingAppServerData(from appServerSnapshot: UsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: Date(),
            account: appServerSnapshot.account,
            limitId: appServerSnapshot.limitId,
            limitName: appServerSnapshot.limitName,
            primary: appServerSnapshot.primary,
            secondary: appServerSnapshot.secondary,
            credits: appServerSnapshot.credits,
            cloudLifetimeTokens: appServerSnapshot.cloudLifetimeTokens,
            local: local,
            taskBoard: taskBoard,
            messages: appServerSnapshot.messages + (local == nil ? messages : [])
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
    let rolloutPath: String
    let model: String?
}

private struct SessionUsageDelta {
    let date: Date
    let tokens: TokenBreakdown
}

private struct SessionUsageCacheEntry {
    let fileSize: Int64
    let modificationDate: Date?
    let hasTokenEvents: Bool
    let tokenEventCount: Int
    let deltas: [SessionUsageDelta]
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

final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot = .empty
    @Published var isRefreshing = false
    @Published var language = WidgetLanguage.storedOrAutomatic()
    @Published var themeMode = WidgetThemeMode.storedOrAutomatic()

    private var fullTimer: Timer?
    private var taskBoardTimer: Timer?
    private var isRefreshingTaskBoard = false

    func start() {
        refresh()
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
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let reader = CodexUsageReader()
            let localSnapshot = reader.loadLocalData()
            DispatchQueue.main.async {
                self.snapshot = self.snapshot.mergingLocalData(from: localSnapshot)
            }

            let appServerSnapshot = reader.loadAppServerData()
            DispatchQueue.main.async {
                self.snapshot = self.snapshot.mergingAppServerData(from: appServerSnapshot)
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
    private static var sessionUsageCache: [String: SessionUsageCacheEntry] = [:]

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

    func loadTaskBoard() -> TaskBoard? {
        var messages: [String] = []
        return readTaskBoard(messages: &messages)
    }

    func loadLocalData() -> UsageSnapshot {
        var messages: [String] = []
        let local = readLocalUsage(messages: &messages)
        let taskBoard = readTaskBoard(messages: &messages)

        return UsageSnapshot(
            refreshedAt: Date(),
            account: nil,
            limitId: nil,
            limitName: nil,
            primary: nil,
            secondary: nil,
            credits: nil,
            cloudLifetimeTokens: nil,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )
    }

    func loadAppServerData() -> UsageSnapshot {
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

        let requiredResponseIds: Set<Int> = [2, 3]
        let responseGroup = DispatchGroup()
        requiredResponseIds.forEach { _ in responseGroup.enter() }

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

            if requiredResponseIds.contains(id) {
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

        if responseGroup.wait(timeout: .now() + 30) == .timedOut {
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

        let detailedUsage = readDetailedUsage(
            sqlitePath: sqlitePath,
            dbPath: dbPath,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            messages: &messages
        )

        return LocalUsage(
            lifetimeTokens: int64Value(totalsObject["lifetimeTokens"]) ?? 0,
            todayTokens: int64Value(totalsObject["todayTokens"]) ?? 0,
            sevenDayTokens: int64Value(totalsObject["sevenDayTokens"]) ?? 0,
            threadCount: intValue(totalsObject["threadCount"]) ?? 0,
            lastUpdatedAt: dateFromEpoch(totalsObject["lastUpdatedAt"]),
            dailyBuckets: dailyBuckets,
            recentThreads: recent,
            detailedUsage: detailedUsage
        )
    }

    private func readDetailedUsage(
        sqlitePath: String,
        dbPath: String,
        dayStart: Date,
        sevenDayStart: Date,
        messages: inout [String]
    ) -> DetailedUsage? {
        let sourceQuery = """
        SELECT rollout_path AS rolloutPath, model
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
            return SessionUsageSource(rolloutPath: path, model: object["model"] as? String)
        }

        guard !sources.isEmpty else {
            messages.append("未找到 Codex session 日志")
            return nil
        }

        let calendar = Calendar.current
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
            for delta in entry.deltas {
                accumulator.add(
                    delta.tokens,
                    at: delta.date,
                    price: price,
                    dayStart: dayStart,
                    sevenDayStart: sevenDayStart,
                    monthStart: monthStart
                )
            }
        }

        guard accumulator.parsedFileCount > 0, accumulator.tokenEventCount > 0 else {
            messages.append("未找到 Codex token_count 事件")
            return nil
        }

        return accumulator.makeUsage()
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
           cached.fileSize == fileSize,
           cached.modificationDate == modificationDate {
            return cached
        }

        let tokenCountNeedle = Data(#""type":"token_count""#.utf8)
        if let parsed = parseLatestSessionUsage(
            url: url,
            tokenCountNeedle: tokenCountNeedle,
            fractionalFormatter: fractionalFormatter,
            plainFormatter: plainFormatter
        ) {
            let entry = SessionUsageCacheEntry(
                fileSize: fileSize,
                modificationDate: modificationDate,
                hasTokenEvents: parsed.hasTokenEvents,
                tokenEventCount: parsed.tokenEventCount,
                deltas: parsed.deltas
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

        while true {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 10) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                processUsageLine(
                    lineData,
                    tokenCountNeedle: tokenCountNeedle,
                    fractionalFormatter: fractionalFormatter,
                    plainFormatter: plainFormatter,
                    previous: &previous,
                    sawTokenEvent: &sawTokenEvent,
                    tokenEventCount: &tokenEventCount,
                    deltas: &deltas
                )
            }
        }

        if !buffer.isEmpty {
            processUsageLine(
                buffer,
                tokenCountNeedle: tokenCountNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter,
                previous: &previous,
                sawTokenEvent: &sawTokenEvent,
                tokenEventCount: &tokenEventCount,
                deltas: &deltas
            )
        }

        let entry = SessionUsageCacheEntry(
            fileSize: fileSize,
            modificationDate: modificationDate,
            hasTokenEvents: sawTokenEvent,
            tokenEventCount: tokenEventCount,
            deltas: deltas
        )
        Self.sessionUsageCache[source.rolloutPath] = entry
        return entry
    }

    private func parseLatestSessionUsage(
        url: URL,
        tokenCountNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter
    ) -> (hasTokenEvents: Bool, tokenEventCount: Int, deltas: [SessionUsageDelta])? {
        // The latest token_count event is cumulative for one session, so tail-read it instead of parsing every intermediate event.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return nil
        }

        guard fileSize > 0 else {
            return (false, 0, [])
        }

        let chunkSize: UInt64 = 256 * 1024
        var offset = fileSize
        var buffer = Data()

        while offset > 0 {
            let readSize = min(chunkSize, offset)
            offset -= readSize

            do {
                try handle.seek(toOffset: offset)
                guard let chunk = try handle.read(upToCount: Int(readSize)) else { break }
                var combined = Data()
                combined.reserveCapacity(chunk.count + buffer.count)
                combined.append(chunk)
                combined.append(buffer)
                buffer = combined
            } catch {
                return nil
            }

            var searchEnd = buffer.endIndex
            while let newline = buffer[..<searchEnd].lastIndex(of: 10) {
                let lineStart = buffer.index(after: newline)
                if lineStart < searchEnd {
                    let lineData = buffer.subdata(in: lineStart..<searchEnd)
                    if let parsed = parseSingleSessionUsageLine(
                        lineData,
                        tokenCountNeedle: tokenCountNeedle,
                        fractionalFormatter: fractionalFormatter,
                        plainFormatter: plainFormatter
                    ) {
                        return parsed
                    }
                }
                searchEnd = newline
            }

            buffer = buffer.subdata(in: buffer.startIndex..<searchEnd)
        }

        if !buffer.isEmpty {
            if let parsed = parseSingleSessionUsageLine(
                buffer,
                tokenCountNeedle: tokenCountNeedle,
                fractionalFormatter: fractionalFormatter,
                plainFormatter: plainFormatter
            ) {
                return parsed
            }
        }

        return (false, 0, [])
    }

    private func parseSingleSessionUsageLine(
        _ lineData: Data,
        tokenCountNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter
    ) -> (hasTokenEvents: Bool, tokenEventCount: Int, deltas: [SessionUsageDelta])? {
        var previous = TokenBreakdown.zero
        var sawTokenEvent = false
        var tokenEventCount = 0
        var deltas: [SessionUsageDelta] = []

        processUsageLine(
            lineData,
            tokenCountNeedle: tokenCountNeedle,
            fractionalFormatter: fractionalFormatter,
            plainFormatter: plainFormatter,
            previous: &previous,
            sawTokenEvent: &sawTokenEvent,
            tokenEventCount: &tokenEventCount,
            deltas: &deltas
        )

        return sawTokenEvent ? (true, tokenEventCount, deltas) : nil
    }

    private func processUsageLine(
        _ lineData: Data,
        tokenCountNeedle: Data,
        fractionalFormatter: ISO8601DateFormatter,
        plainFormatter: ISO8601DateFormatter,
        previous: inout TokenBreakdown,
        sawTokenEvent: inout Bool,
        tokenEventCount: inout Int,
        deltas: inout [SessionUsageDelta]
    ) {
        guard lineData.range(of: tokenCountNeedle) != nil,
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let timestamp = object["timestamp"] as? String,
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
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

struct UsageWidgetView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    static let widgetWidth: CGFloat = 820
    static let widgetDefaultHeight: CGFloat = 720
    static let widgetMinHeight: CGFloat = 620
    static let widgetMaxHeight: CGFloat = 920

    private var snapshot: UsageSnapshot { store.snapshot }
    private var primary: RateWindow? { snapshot.primary }
    private var language: WidgetLanguage { store.language }
    private var themeMode: WidgetThemeMode { store.themeMode }
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
                    taskBoardSection
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
                store.themeMode = selectedMode
                selectedMode.persist()
                selectedMode.applyAppearance()
            }
            LanguageSwitch(language: language) { selectedLanguage in
                store.language = selectedLanguage
                selectedLanguage.persist()
            }
            planPill
            iconButton(systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise") {
                store.refresh()
            }
            iconButton(systemName: "xmark") {
                NSApp.terminate(nil)
            }
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

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .iconButtonStyle()
        .foregroundStyle(.secondary)
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

    private var taskBoardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: language.text("今日任务看板", "Today's task board"), detail: taskBoardSummary)
            HStack(alignment: .top, spacing: 8) {
                ForEach(taskBoardColumns) { column in
                    TaskBoardColumnView(column: column, language: language)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .padding(12)
        .sectionBackground()
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
        if store.isRefreshing, snapshot.local != nil, snapshot.account == nil { return false }
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

    func iconButtonStyle() -> some View {
        modifier(IconButtonStyleModifier())
    }
}

struct IconButtonStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WidgetPalette.controlFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
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
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .cardBackground(cornerRadius: 10)
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
        .padding(10)
        .cardBackground(cornerRadius: 10)
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
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .cardBackground(cornerRadius: 10)
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
        .padding(10)
        .frame(width: 132, alignment: .leading)
        .frame(minHeight: 78, alignment: .leading)
        .cardBackground(cornerRadius: 10)
    }

    private func miniBarHeight(_ tokens: Int64) -> CGFloat {
        let ratio = Double(tokens) / Double(maxTokens)
        return max(6, CGFloat(ratio) * 34)
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
        .padding(8)
        .frame(minHeight: 274, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(taskColumnFill(column.id))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 8, elevated: true)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = UsageStore()
    private var window: DesktopWidgetWindow?
    private var statusItem: NSStatusItem?
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?
    private var isFrontMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        WidgetThemeMode.storedOrAutomatic().applyAppearance()
        debugLog("app launched bundle=\(Bundle.main.bundlePath)")

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
        panel.contentView = GlassHostingContainer(rootView: UsageWidgetView(store: store), cornerRadius: 24)
        panel.moveToDesktopLayer()
        window = panel

        setupStatusItem()
        registerGlobalHotKey()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
        store.stop()
    }

    func toggleWindowLayer() {
        guard let window else { return }
        if isFrontMode {
            window.moveToDesktopLayer()
            isFrontMode = false
        } else {
            window.moveToFrontLayer()
            isFrontMode = true
        }
    }

    @objc private func statusItemClicked() {
        toggleWindowLayer()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }
        if let image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "codexU") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "C"
        }
        button.toolTip = "codexU：点击切换前台/桌面层，快捷键 ⌘U"
        button.target = self
        button.action = #selector(statusItemClicked)
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
        if CommandLine.arguments.contains("--dump-local-json") {
            dumpJSON(CodexUsageReader().loadLocalData())
            return
        }

        if CommandLine.arguments.contains("--dump-app-server-json") {
            dumpJSON(CodexUsageReader().loadAppServerData())
            return
        }

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

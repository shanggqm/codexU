import Foundation

struct HermesRuntimeProvider: RuntimeUsageProvider {
    let scope: RuntimeScope = .hermes

    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot {
        var messages: [String] = []
        let result = HermesStateReader().load(context: context, messages: &messages)
        if result.local == nil {
            messages.append("暂无 Hermes 默认 profile 本机用量记录")
        }

        let snapshot = UsageSnapshot(
            refreshedAt: context.now,
            account: result.databaseFound
                ? AccountInfo(type: "local", planType: "Hermes", emailPresent: false)
                : nil,
            limitId: scope.runtimeId,
            limitName: "Hermes local",
            quotaReadSucceeded: false,
            fiveHourQuota: nil,
            sevenDayQuota: nil,
            credits: nil,
            cloudLifetimeTokens: nil,
            cloudUsageTrend: nil,
            local: result.local,
            taskBoard: result.taskBoard,
            messages: messages
        )

        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: snapshot,
            status: result.databaseFound ? .localOnly : .unavailable,
            quotaSourceLabel: "No local Hermes quota source",
            usageSourceLabel: "Hermes default-profile state.db"
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        var messages: [String] = []
        return HermesStateReader().load(context: context, messages: &messages).taskBoard
    }
}

private struct HermesReadResult {
    let databaseFound: Bool
    let local: LocalUsage?
    let taskBoard: TaskBoard?
}

private struct HermesSessionRow {
    let id: String
    let source: String
    let model: String?
    let billingProvider: String?
    let title: String?
    let cwd: String
    let startedAt: Date
    let endedAt: Date?
    let lastActiveAt: Date
    let archived: Bool
    let tokens: TokenBreakdown
    let costUSD: Double
    let messageCount: Int
    let toolCallCount: Int

    var isCodexBacked: Bool {
        let provider = (billingProvider ?? "").lowercased()
        let modelName = (model ?? "").lowercased()
        return provider == "codex"
            || provider == "openai-codex"
            || provider.hasPrefix("codex-")
            || modelName.hasPrefix("codex/")
            || modelName.contains("openai-codex")
    }
}

private struct HermesToolRow {
    let sessionId: String
    let name: String
    let count: Int
}

private final class HermesStateReader {
    private let fileManager = FileManager.default

    func load(context: RuntimeLoadContext, messages: inout [String]) -> HermesReadResult {
        let database = context.homeDirectory
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("state.db")
        guard fileManager.fileExists(atPath: database.path) else {
            messages.append("未找到 ~/.hermes/state.db")
            return HermesReadResult(databaseFound: false, local: nil, taskBoard: nil)
        }
        guard let sqlitePath = hermesFirstExecutablePath([
            "/usr/bin/sqlite3",
            "/opt/homebrew/bin/sqlite3"
        ]) else {
            messages.append("未找到 sqlite3")
            return HermesReadResult(databaseFound: true, local: nil, taskBoard: nil)
        }

        let sessionColumns = schemaColumns(table: "sessions", sqlitePath: sqlitePath, database: database)
        guard sessionColumns.contains("id"), sessionColumns.contains("started_at") else {
            messages.append("Hermes state.db sessions schema 不受支持")
            return HermesReadResult(databaseFound: true, local: nil, taskBoard: nil)
        }

        let messageColumns = schemaColumns(table: "messages", sqlitePath: sqlitePath, database: database)
        let sessions = loadSessions(
            sqlitePath: sqlitePath,
            database: database,
            sessionColumns: sessionColumns,
            messageColumns: messageColumns
        )
        let codexBackedIds = Set(sessions.filter(\.isCodexBacked).map(\.id))
        let nativeSessions = sessions.filter { !$0.isCodexBacked }
        if !codexBackedIds.isEmpty {
            messages.append("Hermes 中 Codex-backed 会话已从 Hermes token 统计排除")
        }
        if sessions.isEmpty {
            messages.append("Hermes state.db 暂无会话记录")
        }

        let tools = loadTools(
            sqlitePath: sqlitePath,
            database: database,
            messageColumns: messageColumns
        ).filter { !codexBackedIds.contains($0.sessionId) }
        let local = makeLocalUsage(
            sessions: nativeSessions,
            tools: tools,
            statistics: context.statistics,
            messages: &messages
        )
        let taskBoard = makeTaskBoard(sessions: sessions, now: context.now)
        return HermesReadResult(databaseFound: true, local: local, taskBoard: taskBoard)
    }

    private func schemaColumns(table: String, sqlitePath: String, database: URL) -> Set<String> {
        let safeTable = table == "messages" ? "messages" : "sessions"
        return Set(
            runSQLiteJSON(
                sqlitePath: sqlitePath,
                database: database,
                query: "PRAGMA table_info(\(safeTable));"
            ).compactMap { hermesString($0["name"]) }
        )
    }

    private func loadSessions(
        sqlitePath: String,
        database: URL,
        sessionColumns: Set<String>,
        messageColumns: Set<String>
    ) -> [HermesSessionRow] {
        func value(_ name: String, fallback: String) -> String {
            sessionColumns.contains(name) ? "COALESCE(s.\(name), \(fallback))" : fallback
        }

        let lastActive: String
        if messageColumns.contains("session_id"), messageColumns.contains("timestamp") {
            lastActive = "COALESCE((SELECT MAX(m.timestamp) FROM messages m WHERE m.session_id = s.id), \(value("ended_at", fallback: "NULL")), s.started_at)"
        } else {
            lastActive = "COALESCE(\(value("ended_at", fallback: "NULL")), s.started_at)"
        }

        let query = """
        SELECT
            s.id AS id,
            \(value("source", fallback: "'unknown'")) AS source,
            \(value("model", fallback: "NULL")) AS model,
            \(value("billing_provider", fallback: "NULL")) AS billing_provider,
            \(value("title", fallback: "NULL")) AS title,
            \(value("cwd", fallback: "''")) AS cwd,
            s.started_at AS started_at,
            \(value("ended_at", fallback: "NULL")) AS ended_at,
            \(lastActive) AS last_active,
            \(value("archived", fallback: "0")) AS archived,
            \(value("input_tokens", fallback: "0")) AS input_tokens,
            \(value("output_tokens", fallback: "0")) AS output_tokens,
            \(value("cache_read_tokens", fallback: "0")) AS cache_read_tokens,
            \(value("cache_write_tokens", fallback: "0")) AS cache_write_tokens,
            \(value("reasoning_tokens", fallback: "0")) AS reasoning_tokens,
            \(sessionColumns.contains("actual_cost_usd") ? "COALESCE(s.actual_cost_usd, \(value("estimated_cost_usd", fallback: "0")), 0)" : value("estimated_cost_usd", fallback: "0")) AS cost_usd,
            \(value("message_count", fallback: "0")) AS message_count,
            \(value("tool_call_count", fallback: "0")) AS tool_call_count
        FROM sessions s
        ORDER BY last_active DESC, s.started_at DESC;
        """

        return runSQLiteJSON(sqlitePath: sqlitePath, database: database, query: query).compactMap { row in
            guard let id = hermesString(row["id"]),
                  let startedAt = hermesDate(row["started_at"]) else { return nil }
            let input = hermesInt64(row["input_tokens"])
            let output = hermesInt64(row["output_tokens"])
            let cacheRead = hermesInt64(row["cache_read_tokens"])
            let cacheWrite = hermesInt64(row["cache_write_tokens"])
            let reasoning = hermesInt64(row["reasoning_tokens"])
            let cached = cacheRead + cacheWrite
            let total = input + output + cached
            let endedAt = hermesDate(row["ended_at"])
            return HermesSessionRow(
                id: id,
                source: hermesString(row["source"]) ?? "unknown",
                model: hermesString(row["model"]),
                billingProvider: hermesString(row["billing_provider"]),
                title: hermesString(row["title"]),
                cwd: hermesString(row["cwd"]) ?? "",
                startedAt: startedAt,
                endedAt: endedAt,
                lastActiveAt: hermesDate(row["last_active"]) ?? endedAt ?? startedAt,
                archived: hermesInt64(row["archived"]) != 0,
                tokens: TokenBreakdown(
                    inputTokens: input + cached,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    reasoningOutputTokens: reasoning,
                    totalTokens: total
                ),
                costUSD: hermesDouble(row["cost_usd"]),
                messageCount: Int(hermesInt64(row["message_count"])),
                toolCallCount: Int(hermesInt64(row["tool_call_count"]))
            )
        }
    }

    private func loadTools(
        sqlitePath: String,
        database: URL,
        messageColumns: Set<String>
    ) -> [HermesToolRow] {
        guard messageColumns.contains("session_id"), messageColumns.contains("tool_name") else { return [] }
        let query = """
        SELECT session_id, tool_name, COUNT(*) AS call_count
        FROM messages
        WHERE tool_name IS NOT NULL AND TRIM(tool_name) != ''
        GROUP BY session_id, tool_name;
        """
        return runSQLiteJSON(sqlitePath: sqlitePath, database: database, query: query).compactMap { row in
            guard let sessionId = hermesString(row["session_id"]),
                  let name = hermesString(row["tool_name"]), !name.isEmpty else { return nil }
            return HermesToolRow(
                sessionId: sessionId,
                name: name,
                count: max(1, Int(hermesInt64(row["call_count"])))
            )
        }
    }

    private func makeLocalUsage(
        sessions: [HermesSessionRow],
        tools: [HermesToolRow],
        statistics: StatisticsContext,
        messages: inout [String]
    ) -> LocalUsage? {
        let usable = sessions.filter { !$0.archived && (!$0.tokens.isZero || $0.messageCount > 0) }
        guard !usable.isEmpty else { return nil }

        messages.append("Hermes 自然日趋势按会话最后活跃时间近似归桶")
        let now = statistics.now
        let calendar = statistics.calendar
        let dayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let previousSevenDayStart = calendar.date(byAdding: .day, value: -13, to: dayStart) ?? dayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? dayStart

        var today = PricedTokenUsage.zero
        var sevenDay = PricedTokenUsage.zero
        var previousSevenDay = PricedTokenUsage.zero
        var month = PricedTokenUsage.zero
        var lifetime = PricedTokenUsage.zero
        var byDay: [String: PricedTokenUsage] = [:]
        var projects: [String: HermesProjectAccumulator] = [:]

        for session in usable {
            lifetime.add(tokens: session.tokens, costUSD: session.costUSD)
            if session.lastActiveAt >= monthStart {
                month.add(tokens: session.tokens, costUSD: session.costUSD)
            }
            if session.lastActiveAt >= sevenDayStart {
                sevenDay.add(tokens: session.tokens, costUSD: session.costUSD)
            }
            if session.lastActiveAt >= previousSevenDayStart, session.lastActiveAt < sevenDayStart {
                previousSevenDay.add(tokens: session.tokens, costUSD: session.costUSD)
            }
            if session.lastActiveAt >= dayStart {
                today.add(tokens: session.tokens, costUSD: session.costUSD)
            }

            let key = hermesDayKey(session.lastActiveAt, calendar: calendar)
            var day = byDay[key] ?? .zero
            day.add(tokens: session.tokens, costUSD: session.costUSD)
            byDay[key] = day

            let projectPath = session.cwd.isEmpty ? "Hermes" : session.cwd
            var project = projects[projectPath] ?? HermesProjectAccumulator(path: projectPath)
            project.add(session)
            projects[projectPath] = project
        }

        let detailed = DetailedUsage(
            today: today,
            sevenDay: sevenDay,
            month: month,
            lifetime: lifetime,
            parsedFileCount: 1,
            tokenEventCount: usable.count
        )
        let projectValues = projects.values.map(\.project).sorted { $0.tokens > $1.tokens }
        return LocalUsage(
            lifetimeTokens: lifetime.tokens.visibleTotalTokens,
            todayTokens: today.tokens.visibleTotalTokens,
            sevenDayTokens: sevenDay.tokens.visibleTotalTokens,
            threadCount: usable.count,
            lastUpdatedAt: usable.map(\.lastActiveAt).max(),
            dailyBuckets: makeDailyBuckets(byDay: byDay, now: now, calendar: calendar),
            recentThreads: usable.prefix(12).map { session in
                LocalThread(
                    id: "hermes:\(session.id)",
                    title: session.title ?? "Hermes · \(String(session.id.prefix(12)))",
                    tokens: session.tokens.visibleTotalTokens,
                    updatedAt: session.lastActiveAt,
                    model: session.model,
                    cwd: session.cwd,
                    archived: session.archived
                )
            },
            detailedUsage: detailed,
            usageTrend: makeUsageTrend(
                byDay: byDay,
                sevenDay: sevenDay,
                previousSevenDay: previousSevenDay,
                month: month,
                now: now,
                calendar: calendar
            ),
            projectBoard: ProjectBoard(
                recentProjects: projectValues.filter { ($0.lastActiveAt ?? .distantPast) >= sevenDayStart }.prefix(8).map { $0 },
                allProjects: projectValues
            ),
            toolUsages: makeToolUsages(tools),
            skillUsages: []
        )
    }

    private func makeDailyBuckets(
        byDay: [String: PricedTokenUsage],
        now: Date,
        calendar: Calendar
    ) -> [DailyTokenBucket] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = hermesDayKey(date, calendar: calendar)
            return DailyTokenBucket(
                id: key,
                label: formatter.string(from: date),
                tokens: byDay[key]?.tokens.visibleTotalTokens ?? 0
            )
        }
    }

    private func makeUsageTrend(
        byDay: [String: PricedTokenUsage],
        sevenDay: PricedTokenUsage,
        previousSevenDay: PricedTokenUsage,
        month: PricedTokenUsage,
        now: Date,
        calendar: Calendar
    ) -> UsageTrend {
        let start = calendar.date(byAdding: .day, value: -179, to: calendar.startOfDay(for: now)) ?? now
        let buckets: [UsageDayBucket] = (0..<180).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = hermesDayKey(date, calendar: calendar)
            return UsageDayBucket(
                id: key,
                date: date,
                usage: byDay[key] ?? .zero,
                sourceQuality: .approximate
            )
        }
        let heatmapDays = buckets.map { bucket in
            UsageHeatmapDay(id: bucket.id, date: bucket.date, usage: bucket.usage, isFuture: bucket.date > now)
        }
        let active = buckets.filter { $0.tokens > 0 }
        let current = sevenDay.tokens.visibleTotalTokens
        let previous = previousSevenDay.tokens.visibleTotalTokens
        let change = previous > 0 ? Double(current - previous) / Double(previous) * 100 : nil
        let values = active.map(\.tokens).sorted()
        return UsageTrend(
            dayBuckets: buckets,
            heatmapWeeks: stride(from: 0, to: heatmapDays.count, by: 7).map {
                Array(heatmapDays[$0..<min($0 + 7, heatmapDays.count)])
            },
            heatmapThresholds: hermesHeatmapThresholds(values),
            summary: UsageTrendSummary(
                sevenDay: sevenDay,
                dailyAverageTokens: current / 7,
                peakDay: active.max { $0.tokens < $1.tokens },
                changePercent: change,
                isNewActivity: previous == 0 && current > 0
            ),
            month: month,
            projectedMonthCostUSD: hermesProjectedMonthCost(month.estimatedCostUSD, now: now, calendar: calendar),
            activeDayCount: active.count,
            sourceQuality: .approximate
        )
    }

    private func makeToolUsages(_ rows: [HermesToolRow]) -> [ToolUsage] {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.name, default: 0] += row.count }
        return counts.map { name, count in
            ToolUsage(
                id: "hermes-tool:\(name)",
                name: name,
                category: hermesToolCategory(name),
                callCount: count,
                estimatedTokens: nil,
                estimatedCostUSD: nil
            )
        }.sorted { $0.callCount > $1.callCount }
    }

    private func makeTaskBoard(sessions: [HermesSessionRow], now: Date) -> TaskBoard? {
        let visible = sessions.filter { !$0.archived }.prefix(60)
        guard !visible.isEmpty else { return nil }
        let items = visible.map { session -> TaskItem in
            let kind: TaskColumnKind
            if session.source.lowercased() == "cron" {
                kind = .scheduled
            } else if session.endedAt == nil {
                kind = session.messageCount > 0 ? .active : .pending
            } else {
                kind = .done
            }
            let detailParts = [session.source, session.model].compactMap { value in
                value.flatMap { $0.isEmpty ? nil : $0 }
            }
            return TaskItem(
                id: "hermes:\(session.id)",
                code: String(session.id.prefix(12)),
                title: session.title ?? "Hermes · \(String(session.id.prefix(12)))",
                detail: detailParts.joined(separator: " · "),
                chip: session.source.uppercased(),
                updatedAt: session.lastActiveAt,
                tokens: session.isCodexBacked ? nil : session.tokens.visibleTotalTokens,
                kind: kind,
                source: .hermes,
                summary: nil,
                recentReply: nil,
                timing: nil,
                progress: kind == .done ? TaskProgress(percent: 100, origin: .completedStatus) : nil,
                navigationTarget: nil
            )
        }
        let columns: [TaskColumnKind] = [.active, .pending, .scheduled, .done]
        return TaskBoard(
            refreshedAt: now,
            columns: columns.map { kind in
                let values = items.filter { $0.kind == kind }
                return TaskColumn(id: kind, title: kind.rawValue, count: values.count, items: values)
            }
        )
    }

    private func runSQLiteJSON(sqlitePath: String, database: URL, query: String) -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = ["-readonly", "-json", database.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rows
    }
}

private struct HermesProjectAccumulator {
    let path: String
    var tokens = TokenBreakdown.zero
    var costUSD: Double = 0
    var sessions = Set<String>()
    var lastActiveAt: Date?

    mutating func add(_ session: HermesSessionRow) {
        tokens.add(session.tokens)
        costUSD += session.costUSD
        sessions.insert(session.id)
        lastActiveAt = max(lastActiveAt ?? .distantPast, session.lastActiveAt)
    }

    var project: ProjectUsage {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = trimmed.split(separator: "/").last.map(String.init) ?? path
        return ProjectUsage(
            id: "hermes-project:\(path)",
            name: name.isEmpty ? "Hermes" : name,
            fullPath: path,
            tokens: tokens.visibleTotalTokens,
            estimatedCostUSD: costUSD > 0 ? costUSD : nil,
            threadCount: sessions.count,
            lastActiveAt: lastActiveAt,
            sourceQuality: .approximate
        )
    }
}

private func hermesFirstExecutablePath(_ paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func hermesString(_ value: Any?) -> String? {
    if let string = value as? String, !string.isEmpty { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

private func hermesInt64(_ value: Any?) -> Int64 {
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) ?? 0 }
    return 0
}

private func hermesDouble(_ value: Any?) -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) ?? 0 }
    return 0
}

private func hermesDate(_ value: Any?) -> Date? {
    let raw: Double
    if let number = value as? NSNumber {
        raw = number.doubleValue
    } else if let string = value as? String, let parsed = Double(string) {
        raw = parsed
    } else {
        return nil
    }
    return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
}

private func hermesDayKey(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func hermesHeatmapThresholds(_ values: [Int64]) -> [Int64] {
    guard !values.isEmpty else { return [1, 10, 100, 1_000] }
    func percentile(_ fraction: Double) -> Int64 {
        let index = min(values.count - 1, max(0, Int((Double(values.count - 1) * fraction).rounded())))
        return max(1, values[index])
    }
    return [percentile(0.25), percentile(0.5), percentile(0.75), percentile(0.95)]
}

private func hermesProjectedMonthCost(_ cost: Double, now: Date, calendar: Calendar) -> Double? {
    let day = calendar.component(.day, from: now)
    guard cost > 0, day > 0, let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
    return cost / Double(day) * Double(days)
}

private func hermesToolCategory(_ name: String) -> String {
    let value = name.lowercased()
    if value.contains("terminal") || value.contains("shell") || value.contains("bash") { return "terminal" }
    if value.contains("write") || value.contains("edit") || value.contains("patch") { return "edit" }
    if value.contains("read") || value.contains("search") || value.contains("grep") { return "docs" }
    if value.contains("browser") || value.contains("web") || value.contains("fetch") { return "browser" }
    if value.contains("agent") || value.contains("task") || value.contains("plan") { return "planning" }
    if value.contains("mcp") { return "mcp" }
    return "tool"
}

import Foundation

struct OpenClawRuntimeProvider: RuntimeUsageProvider {
    let scope: RuntimeScope = .openClaw

    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot {
        var messages: [String] = []
        let local = OpenClawTranscriptReader().loadLocalUsage(context: context, messages: &messages)
        let taskBoard = OpenClawTaskReader().loadTaskBoard(context: context, messages: &messages)
        if local == nil {
            messages.append("暂无 OpenClaw 本机用量记录")
        }

        let snapshot = UsageSnapshot(
            refreshedAt: context.now,
            account: AccountInfo(type: "local", planType: "OpenClaw", emailPresent: false),
            limitId: scope.runtimeId,
            limitName: "OpenClaw local",
            quotaReadSucceeded: false,
            fiveHourQuota: nil,
            sevenDayQuota: nil,
            credits: nil,
            cloudLifetimeTokens: nil,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )

        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: snapshot,
            status: local == nil ? .unavailable : .localOnly,
            quotaSourceLabel: "Local OpenClaw records",
            usageSourceLabel: "OpenClaw main-agent transcripts"
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        var messages: [String] = []
        return OpenClawTaskReader().loadTaskBoard(context: context, messages: &messages)
    }
}

private final class OpenClawTranscriptReader {
    private let fileManager = FileManager.default
    private let cacheVersion = 1

    func loadLocalUsage(context: RuntimeLoadContext, messages: inout [String]) -> LocalUsage? {
        let sessionsRoot = context.homeDirectory
            .appendingPathComponent(".openclaw/agents/main/sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsRoot.path) else {
            messages.append("未找到 ~/.openclaw/agents/main/sessions")
            return nil
        }

        let transcriptFiles = enumerateTranscriptFiles(under: sessionsRoot)
        guard !transcriptFiles.isEmpty else {
            messages.append("未找到 OpenClaw transcript JSONL")
            return nil
        }

        var cache = readCache(context: context)
        let livePaths = Set(transcriptFiles.map(\.path))
        var cacheChanged = false
        if cache.entries.keys.contains(where: { !livePaths.contains($0) }) {
            cache.entries = cache.entries.filter { livePaths.contains($0.key) }
            cacheChanged = true
        }

        var summaries: [OpenClawTranscriptSummary] = []
        for file in transcriptFiles {
            guard let fingerprint = fingerprint(for: file) else { continue }
            if let entry = cache.entries[file.path], entry.matches(fingerprint) {
                summaries.append(entry.summary)
                continue
            }

            let summary = parseTranscript(file: file, fingerprint: fingerprint)
            cache.entries[file.path] = OpenClawSessionCacheEntry(
                fileSize: fingerprint.fileSize,
                modificationTimeNanoseconds: fingerprint.modificationTimeNanoseconds,
                summary: summary
            )
            summaries.append(summary)
            cacheChanged = true
        }

        if cacheChanged, !writeCache(cache, context: context) {
            messages.append("OpenClaw 本地缓存写入失败")
        }

        return makeLocalUsage(from: summaries, statistics: context.statistics, messages: &messages)
    }

    private func enumerateTranscriptFiles(under root: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".jsonl")
                && !name.hasSuffix(".trajectory.jsonl")
                && !name.contains(".deleted.")
                && !name.contains(".reset.")
                && !name.contains(".bak-")
        }.sorted { $0.path < $1.path }
    }

    private func parseTranscript(
        file: URL,
        fingerprint: OpenClawFileFingerprint
    ) -> OpenClawTranscriptSummary {
        var summary = OpenClawTranscriptSummary(
            filePath: file.path,
            sessionId: file.deletingPathExtension().lastPathComponent,
            cwd: "",
            model: nil,
            lastActiveAt: fingerprint.modificationDate,
            deltas: [],
            toolCalls: [:]
        )
        var seenMessageIds = Set<String>()

        guard let handle = try? FileHandle(forReadingFrom: file) else { return summary }
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                processLine(line, summary: &summary, seenMessageIds: &seenMessageIds)
            }
        }
        if !buffer.isEmpty {
            processLine(buffer, summary: &summary, seenMessageIds: &seenMessageIds)
        }
        return summary
    }

    private func processLine(
        _ data: Data,
        summary: inout OpenClawTranscriptSummary,
        seenMessageIds: inout Set<String>
    ) {
        guard data.range(of: Data("\"usage\"".utf8)) != nil
                || data.range(of: Data("\"type\":\"session\"".utf8)) != nil
                || data.range(of: Data("\"type\":\"model_change\"".utf8)) != nil
                || data.range(of: Data("\"toolCall\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = object["type"] as? String else {
            return
        }

        let timestamp = openClawDateValue(object["timestamp"])
        summary.lastActiveAt = openClawMaxDate(summary.lastActiveAt, timestamp)

        if eventType == "session" {
            summary.cwd = (object["cwd"] as? String) ?? summary.cwd
            summary.sessionId = (object["id"] as? String) ?? summary.sessionId
            return
        }
        if eventType == "model_change" {
            summary.model = (object["modelId"] as? String) ?? summary.model
            return
        }
        guard eventType == "message",
              let message = object["message"] as? [String: Any] else {
            return
        }

        parseToolCalls(message["content"], summary: &summary)
        guard message["role"] as? String == "assistant",
              let usage = message["usage"] as? [String: Any] else {
            return
        }

        let messageId = (object["id"] as? String) ?? (message["id"] as? String)
        if let messageId, !seenMessageIds.insert(messageId).inserted { return }

        let cached = openClawInt64Value(usage["cacheRead"]) + openClawInt64Value(usage["cacheWrite"])
        let directInput = openClawInt64Value(usage["input"])
        let output = openClawInt64Value(usage["output"])
        let tokens = TokenBreakdown(
            inputTokens: directInput + cached,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: openClawInt64Value(usage["reasoningOutput"]),
            totalTokens: openClawInt64Optional(usage["totalTokens"]) ?? (directInput + cached + output)
        )
        guard !tokens.isZero else { return }

        let model = (message["model"] as? String) ?? summary.model
        let provider = (message["provider"] as? String) ?? ""
        let normalizedProvider = provider.lowercased()
        let normalizedModel = (model ?? "").lowercased()
        let isCodexBacked = normalizedProvider == "codex"
            || normalizedProvider == "openai-codex"
            || normalizedProvider.hasPrefix("codex-")
            || normalizedModel.hasPrefix("codex/")
            || normalizedModel.contains("openai-codex")
        summary.model = model
        guard !isCodexBacked else { return }
        summary.deltas.append(OpenClawUsageDelta(
            messageId: messageId,
            date: timestamp ?? summary.lastActiveAt ?? Date(),
            tokens: tokens,
            model: model,
            projectPath: summary.cwd,
            sessionId: summary.sessionId
        ))
    }

    private func parseToolCalls(_ content: Any?, summary: inout OpenClawTranscriptSummary) {
        guard let items = content as? [[String: Any]] else { return }
        for item in items {
            let type = (item["type"] as? String) ?? ""
            guard type == "toolCall" || type == "tool_use",
                  let name = (item["name"] as? String) ?? (item["toolName"] as? String),
                  !name.isEmpty else {
                continue
            }
            summary.toolCalls[name, default: 0] += 1
        }
    }

    private func makeLocalUsage(
        from summaries: [OpenClawTranscriptSummary],
        statistics: StatisticsContext,
        messages: inout [String]
    ) -> LocalUsage? {
        var seenMessageIds = Set<String>()
        var deltas: [OpenClawUsageDelta] = []
        for delta in summaries.flatMap(\.deltas) {
            if let messageId = delta.messageId, !seenMessageIds.insert(messageId).inserted {
                continue
            }
            deltas.append(delta)
        }
        guard !deltas.isEmpty else {
            messages.append("OpenClaw transcript 中未找到 usage 事件")
            return nil
        }
        deltas.sort { $0.date < $1.date }

        let calendar = statistics.calendar
        let dayStart = calendar.startOfDay(for: statistics.now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let previousSevenDayStart = calendar.date(byAdding: .day, value: -13, to: dayStart) ?? dayStart
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart) ?? previousSevenDayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: dayStart)) ?? dayStart

        var today = PricedTokenUsage.zero
        var sevenDay = PricedTokenUsage.zero
        var previousSevenDay = PricedTokenUsage.zero
        var month = PricedTokenUsage.zero
        var lifetime = PricedTokenUsage.zero
        var dailyUsage: [String: (date: Date, usage: PricedTokenUsage)] = [:]
        var allProjects: [String: OpenClawProjectAccumulator] = [:]
        var recentProjects: [String: OpenClawProjectAccumulator] = [:]

        for delta in deltas {
            lifetime.add(tokens: delta.tokens, costUSD: 0)
            if delta.date >= monthStart { month.add(tokens: delta.tokens, costUSD: 0) }
            if delta.date >= sevenDayStart { sevenDay.add(tokens: delta.tokens, costUSD: 0) }
            if delta.date >= previousSevenDayStart && delta.date < sevenDayStart {
                previousSevenDay.add(tokens: delta.tokens, costUSD: 0)
            }
            if delta.date >= dayStart { today.add(tokens: delta.tokens, costUSD: 0) }

            if delta.date >= trendStart {
                let bucketDate = calendar.startOfDay(for: delta.date)
                let key = statistics.dayKey(for: bucketDate)
                var usage = dailyUsage[key]?.usage ?? .zero
                usage.add(tokens: delta.tokens, costUSD: 0)
                dailyUsage[key] = (bucketDate, usage)
            }

            let projectPath = delta.projectPath.isEmpty ? "OpenClaw" : delta.projectPath
            var project = allProjects[projectPath] ?? OpenClawProjectAccumulator(path: projectPath)
            project.add(delta: delta)
            allProjects[projectPath] = project
            if delta.date >= sevenDayStart {
                var recent = recentProjects[projectPath] ?? OpenClawProjectAccumulator(path: projectPath)
                recent.add(delta: delta)
                recentProjects[projectPath] = recent
            }
        }

        let detailed = DetailedUsage(
            today: today,
            sevenDay: sevenDay,
            month: month,
            lifetime: lifetime,
            parsedFileCount: summaries.filter { !$0.deltas.isEmpty }.count,
            tokenEventCount: deltas.count
        )
        let trend = makeUsageTrend(
            dailyUsage: dailyUsage,
            dayStart: dayStart,
            sevenDayStart: sevenDayStart,
            previousSevenDay: previousSevenDay,
            month: month,
            calendar: calendar,
            statistics: statistics
        )
        let projectBoard = ProjectBoard(
            recentProjects: recentProjects.values.map { $0.makeProject() }.sorted(by: openClawProjectSort),
            allProjects: allProjects.values.map { $0.makeProject() }.sorted(by: openClawProjectSort)
        )

        return LocalUsage(
            lifetimeTokens: lifetime.tokens.visibleTotalTokens,
            todayTokens: today.tokens.visibleTotalTokens,
            sevenDayTokens: sevenDay.tokens.visibleTotalTokens,
            threadCount: summaries.filter { !$0.deltas.isEmpty }.count,
            lastUpdatedAt: summaries.compactMap(\.lastActiveAt).max(),
            dailyBuckets: makeDailyBuckets(dailyUsage: dailyUsage, dayStart: dayStart, calendar: calendar, statistics: statistics),
            recentThreads: makeRecentThreads(summaries),
            detailedUsage: detailed,
            usageTrend: trend,
            projectBoard: projectBoard,
            toolUsages: makeToolUsages(summaries, lifetimeTokens: lifetime.tokens.visibleTotalTokens),
            skillUsages: makeSkillUsages(summaries)
        )
    }

    private func makeDailyBuckets(
        dailyUsage: [String: (date: Date, usage: PricedTokenUsage)],
        dayStart: Date,
        calendar: Calendar,
        statistics: StatisticsContext
    ) -> [DailyTokenBucket] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: dayStart) else { return nil }
            let key = statistics.dayKey(for: date)
            return DailyTokenBucket(
                id: key,
                label: index == 6 ? "今天" : formatter.string(from: date),
                tokens: dailyUsage[key]?.usage.tokens.visibleTotalTokens ?? 0
            )
        }
    }

    private func makeUsageTrend(
        dailyUsage: [String: (date: Date, usage: PricedTokenUsage)],
        dayStart: Date,
        sevenDayStart: Date,
        previousSevenDay: PricedTokenUsage,
        month: PricedTokenUsage,
        calendar: Calendar,
        statistics: StatisticsContext
    ) -> UsageTrend {
        let trendStart = calendar.date(byAdding: .day, value: -181, to: dayStart) ?? sevenDayStart
        var buckets: [UsageDayBucket] = []
        var cursor = calendar.startOfDay(for: trendStart)
        while cursor <= dayStart {
            let key = statistics.dayKey(for: cursor)
            buckets.append(UsageDayBucket(
                id: key,
                date: cursor,
                usage: dailyUsage[key]?.usage ?? .zero,
                sourceQuality: .detailed
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let lastSeven = buckets.filter { $0.date >= sevenDayStart }
        var sevenDay = PricedTokenUsage.zero
        for bucket in lastSeven {
            sevenDay.add(tokens: bucket.usage.tokens, costUSD: 0)
        }
        let peakDay = lastSeven.max { $0.tokens < $1.tokens }
        let previousTokens = previousSevenDay.tokens.visibleTotalTokens
        let changePercent = previousTokens > 0
            ? (Double(sevenDay.tokens.visibleTotalTokens - previousTokens) / Double(previousTokens)) * 100
            : nil
        let heatmap = makeHeatmapData(buckets: buckets, endDate: dayStart, calendar: calendar)

        return UsageTrend(
            dayBuckets: buckets,
            heatmapWeeks: heatmap.weeks,
            heatmapThresholds: heatmap.thresholds,
            summary: UsageTrendSummary(
                sevenDay: sevenDay,
                dailyAverageTokens: sevenDay.tokens.visibleTotalTokens / 7,
                peakDay: (peakDay?.tokens ?? 0) > 0 ? peakDay : nil,
                changePercent: changePercent,
                isNewActivity: previousTokens == 0 && sevenDay.tokens.visibleTotalTokens > 0
            ),
            month: month,
            projectedMonthCostUSD: nil,
            activeDayCount: buckets.filter { $0.tokens > 0 }.count,
            sourceQuality: .detailed
        )
    }

    private func makeHeatmapData(
        buckets: [UsageDayBucket],
        endDate: Date,
        calendar: Calendar
    ) -> (weeks: [[UsageHeatmapDay]], thresholds: [Int64]) {
        let latest = calendar.startOfDay(for: endDate)
        let weekday = calendar.component(.weekday, from: latest)
        let daysFromMonday = (weekday + 5) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: latest) ?? latest
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -25, to: currentWeekStart) ?? currentWeekStart
        let byDay = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        let weeks = (0..<26).map { weekIndex in
            (0..<7).compactMap { dayIndex -> UsageHeatmapDay? in
                guard let date = calendar.date(byAdding: .day, value: weekIndex * 7 + dayIndex, to: firstWeekStart) else {
                    return nil
                }
                let key = openClawDayKey(date, calendar: calendar)
                let isFuture = date > latest
                return UsageHeatmapDay(
                    id: key,
                    date: date,
                    usage: isFuture ? nil : byDay[key]?.usage,
                    isFuture: isFuture
                )
            }
        }
        let values = weeks.flatMap { $0 }.filter { !$0.isFuture }.map(\.tokens).filter { $0 > 0 }.sorted()
        return (weeks, openClawHeatmapThresholds(values))
    }

    private func makeRecentThreads(_ summaries: [OpenClawTranscriptSummary]) -> [LocalThread] {
        summaries.filter { !$0.deltas.isEmpty }
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
            .prefix(8)
            .map { summary in
                LocalThread(
                    id: "openclaw-\(summary.sessionId)",
                    title: "OpenClaw · \(String(summary.sessionId.prefix(8)))",
                    tokens: summary.deltas.reduce(Int64(0)) { $0 + $1.tokens.visibleTotalTokens },
                    updatedAt: summary.lastActiveAt,
                    model: summary.model,
                    cwd: summary.cwd,
                    archived: false
                )
            }
    }

    private func makeToolUsages(
        _ summaries: [OpenClawTranscriptSummary],
        lifetimeTokens: Int64
    ) -> [ToolUsage] {
        var calls: [String: Int] = [:]
        for summary in summaries {
            for (name, count) in summary.toolCalls { calls[name, default: 0] += count }
        }
        let totalCalls = max(calls.values.reduce(0, +), 1)
        return calls.map { name, count in
            ToolUsage(
                id: "openclaw-tool-\(name.lowercased())",
                name: name,
                category: openClawToolCategory(name),
                callCount: count,
                estimatedTokens: Int64((Double(lifetimeTokens) * Double(count) / Double(totalCalls)).rounded()),
                estimatedCostUSD: nil
            )
        }.sorted { $0.callCount > $1.callCount }
    }

    private func makeSkillUsages(_ summaries: [OpenClawTranscriptSummary]) -> [SkillUsage] {
        let skills = summaries.flatMap { summary in
            summary.toolCalls.compactMap { name, count -> SkillUsage? in
                guard name.lowercased().contains("skill") else { return nil }
                return SkillUsage(
                    id: "openclaw-skill-\(name.lowercased())",
                    name: name,
                    path: name,
                    sourceLabel: "OpenClaw transcript",
                    loadCount: count,
                    threadCount: 1,
                    staticTokenEstimate: nil,
                    staticByteCount: nil,
                    lastLoadedAt: summary.lastActiveAt
                )
            }
        }
        var map: [String: SkillUsage] = [:]
        for skill in skills {
            if let existing = map[skill.id] {
                map[skill.id] = SkillUsage(
                    id: existing.id,
                    name: existing.name,
                    path: existing.path,
                    sourceLabel: existing.sourceLabel,
                    loadCount: existing.loadCount + skill.loadCount,
                    threadCount: existing.threadCount + 1,
                    staticTokenEstimate: nil,
                    staticByteCount: nil,
                    lastLoadedAt: openClawMaxDate(existing.lastLoadedAt, skill.lastLoadedAt)
                )
            } else {
                map[skill.id] = skill
            }
        }
        return map.values.sorted { $0.loadCount > $1.loadCount }
    }

    private func readCache(context: RuntimeLoadContext) -> OpenClawSessionDiskCache {
        let url = cacheURL(context: context)
        guard let data = try? Data(contentsOf: url) else {
            return OpenClawSessionDiskCache(version: cacheVersion, entries: [:])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let cache = try? decoder.decode(OpenClawSessionDiskCache.self, from: data),
              cache.version == cacheVersion else {
            return OpenClawSessionDiskCache(version: cacheVersion, entries: [:])
        }
        return cache
    }

    private func writeCache(_ cache: OpenClawSessionDiskCache, context: RuntimeLoadContext) -> Bool {
        let url = cacheURL(context: context)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(cache)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func cacheURL(context: RuntimeLoadContext) -> URL {
        context.cacheDirectory
            .appendingPathComponent("openclaw", isDirectory: true)
            .appendingPathComponent("session-usage-v1.json")
    }

    private func fingerprint(for file: URL) -> OpenClawFileFingerprint? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return OpenClawFileFingerprint(
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate,
            modificationTimeNanoseconds: values.contentModificationDate.map(openClawEpochNanoseconds)
        )
    }
}

private final class OpenClawTaskReader {
    private let fileManager = FileManager.default

    func loadTaskBoard(context: RuntimeLoadContext, messages: inout [String]) -> TaskBoard? {
        let taskItems = readCanonicalTasks(context: context)
        let sessionItems = readTodaySessions(context: context)
        let items = taskItems + sessionItems
        guard !items.isEmpty else {
            messages.append("未找到 OpenClaw 任务或今日会话")
            return nil
        }

        let columns: [TaskColumnKind] = [.active, .pending, .scheduled, .done]
        return TaskBoard(
            refreshedAt: context.now,
            columns: columns.map { kind in
                let matches = items.filter { $0.kind == kind }
                    .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                return TaskColumn(
                    id: kind,
                    title: kind.rawValue,
                    count: matches.count,
                    items: Array(matches.prefix(8))
                )
            }
        )
    }

    private func readCanonicalTasks(context: RuntimeLoadContext) -> [TaskItem] {
        let url = context.homeDirectory.appendingPathComponent(".openclaw/workspace/memory/tasks.json")
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { row in
            guard let title = openClawTaskText(row["title"] as? String, limit: 160) else { return nil }
            let id = (row["id"] as? String) ?? UUID().uuidString
            let status = (row["status"] as? String) ?? "pending"
            let kind = openClawTaskKind(status)
            let description = openClawTaskText(row["description"] as? String, limit: 1_200)
            let details = openClawTaskText(row["details"] as? String, limit: 1_600)
            let summary = [description, details].compactMap { $0 }.joined(separator: "\n")
            let priority = (row["priority"] as? String) ?? status
            let updatedAt = openClawDateValue(row["created"]) ?? openClawDateValue(row["deadline"])

            return TaskItem(
                id: "openclaw-task-\(id)",
                code: "OCL-\(String(id.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased())",
                title: title,
                detail: [priority, row["source"] as? String].compactMap { $0 }.joined(separator: " · "),
                chip: openClawTaskChip(status: status, priority: priority, kind: kind),
                updatedAt: updatedAt,
                tokens: nil,
                kind: kind,
                source: .openClaw,
                summary: summary.isEmpty ? nil : summary,
                recentReply: nil,
                navigationTarget: nil
            )
        }
    }

    private func readTodaySessions(context: RuntimeLoadContext) -> [TaskItem] {
        let sessionsRoot = context.homeDirectory.appendingPathComponent(".openclaw/agents/main/sessions", isDirectory: true)
        let indexURL = sessionsRoot.appendingPathComponent("sessions.json")
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let dayStart = context.statistics.calendar.startOfDay(for: context.now)
        return index.compactMap { key, rawValue -> TaskItem? in
            guard let value = rawValue as? [String: Any],
                  let updatedAt = openClawDateValue(value["updatedAt"]),
                  updatedAt >= dayStart,
                  let sessionPath = value["sessionFile"] as? String else {
                return nil
            }

            let conversation = readRecentConversation(at: sessionPath)
            let isScheduled = key.contains(":cron:")
            let status = (value["status"] as? String) ?? ""
            let kind = isScheduled ? .scheduled : openClawSessionKind(status: status, updatedAt: updatedAt, now: context.now)
            let title = conversation.lastUser
                ?? (isScheduled ? "OpenClaw 定时任务" : openClawSessionTitle(key))
            let provider = value["modelProvider"] as? String
            let model = value["model"] as? String
            let channel = value["channel"] as? String
            let details = [channel, provider, model].compactMap { $0 }.filter { !$0.isEmpty }
            let rawId = (value["sessionId"] as? String) ?? key
            let tokens = openClawInt64Optional(value["totalTokens"])

            return TaskItem(
                id: "openclaw-session-\(rawId)-\(kind.rawValue)",
                code: "OCL-\(String(rawId.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased())",
                title: openClawTaskText(title, limit: 160) ?? "OpenClaw Session",
                detail: details.joined(separator: " · "),
                chip: isScheduled ? "Cron" : openClawSessionChip(status: status, kind: kind),
                updatedAt: updatedAt,
                tokens: tokens,
                kind: kind,
                source: .openClaw,
                summary: openClawTaskText(conversation.lastUser, limit: 1_200),
                recentReply: openClawTaskText(conversation.lastAssistant, limit: 1_600),
                navigationTarget: nil
            )
        }
    }

    private func readRecentConversation(at path: String) -> (lastUser: String?, lastAssistant: String?) {
        guard fileManager.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return (nil, nil)
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = min(fileSize, 2_000_000)
        try? handle.seek(toOffset: fileSize - readSize)
        guard let data = try? handle.readToEnd() else { return (nil, nil) }

        var lastUser: String?
        var lastAssistant: String?
        for rawLine in data.split(separator: 10).reversed() {
            guard lastUser == nil || lastAssistant == nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  let text = openClawMessageText(message["content"]) else {
                continue
            }
            if role == "user", lastUser == nil, !text.hasPrefix("[OpenClaw Runtime Context]") {
                lastUser = text
            } else if role == "assistant", lastAssistant == nil {
                lastAssistant = text
            }
        }
        return (lastUser, lastAssistant)
    }
}

private struct OpenClawFileFingerprint {
    let fileSize: Int64
    let modificationDate: Date?
    let modificationTimeNanoseconds: Int64?
}

private struct OpenClawSessionCacheEntry: Codable {
    let fileSize: Int64
    let modificationTimeNanoseconds: Int64?
    let summary: OpenClawTranscriptSummary

    func matches(_ fingerprint: OpenClawFileFingerprint) -> Bool {
        fileSize == fingerprint.fileSize
            && modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds
    }
}

private struct OpenClawSessionDiskCache: Codable {
    let version: Int
    var entries: [String: OpenClawSessionCacheEntry]
}

private struct OpenClawTranscriptSummary: Codable {
    let filePath: String
    var sessionId: String
    var cwd: String
    var model: String?
    var lastActiveAt: Date?
    var deltas: [OpenClawUsageDelta]
    var toolCalls: [String: Int]
}

private struct OpenClawUsageDelta: Codable {
    let messageId: String?
    let date: Date
    let tokens: TokenBreakdown
    let model: String?
    let projectPath: String
    let sessionId: String
}

private struct OpenClawProjectAccumulator {
    let path: String
    var tokens = TokenBreakdown.zero
    var sessionIds = Set<String>()
    var lastActiveAt: Date?

    mutating func add(delta: OpenClawUsageDelta) {
        tokens.add(delta.tokens)
        sessionIds.insert(delta.sessionId)
        lastActiveAt = openClawMaxDate(lastActiveAt, delta.date)
    }

    func makeProject() -> ProjectUsage {
        ProjectUsage(
            id: "openclaw-project-\(path)",
            name: openClawShortPath(path),
            fullPath: path,
            tokens: tokens.visibleTotalTokens,
            estimatedCostUSD: nil,
            threadCount: max(sessionIds.count, 1),
            lastActiveAt: lastActiveAt,
            sourceQuality: .detailed
        )
    }
}

private func openClawProjectSort(_ left: ProjectUsage, _ right: ProjectUsage) -> Bool {
    if left.tokens == right.tokens {
        return (left.lastActiveAt ?? .distantPast) > (right.lastActiveAt ?? .distantPast)
    }
    return left.tokens > right.tokens
}

private func openClawTaskKind(_ status: String) -> TaskColumnKind {
    switch status.lowercased() {
    case "in_progress", "active", "running": return .active
    case "done", "completed", "success": return .done
    case "scheduled", "cron": return .scheduled
    default: return .pending
    }
}

private func openClawSessionKind(status: String, updatedAt: Date, now: Date) -> TaskColumnKind {
    switch status.lowercased() {
    case "done", "completed", "success": return .done
    case "failed", "timeout", "error": return .pending
    case "running", "active", "in_progress": return .active
    default: return now.timeIntervalSince(updatedAt) <= 2 * 60 * 60 ? .active : .pending
    }
}

private func openClawTaskChip(status: String, priority: String, kind: TaskColumnKind) -> String {
    let normalized = priority.lowercased()
    if normalized.contains("p0") || normalized.contains("high") || normalized.contains("urgent") { return "High" }
    if normalized.contains("p1") || normalized.contains("medium") { return "Medium" }
    switch kind {
    case .active: return "Active"
    case .pending: return status.isEmpty ? "Pending" : status
    case .scheduled: return "Cron"
    case .done: return "Done"
    }
}

private func openClawSessionChip(status: String, kind: TaskColumnKind) -> String {
    if status.lowercased() == "failed" { return "Failed" }
    if status.lowercased() == "timeout" { return "Timeout" }
    switch kind {
    case .active: return "Active"
    case .pending: return "Pending"
    case .scheduled: return "Cron"
    case .done: return "Done"
    }
}

private func openClawSessionTitle(_ key: String) -> String {
    if key.contains("openclaw-weixin") { return "OpenClaw 微信会话" }
    if key.contains(":main") { return "OpenClaw 主会话" }
    if key.contains(":explicit:") {
        return key.components(separatedBy: ":explicit:").last ?? "OpenClaw 任务"
    }
    return "OpenClaw 任务"
}

private func openClawMessageText(_ content: Any?) -> String? {
    if let text = content as? String {
        return openClawTaskText(text, limit: 4_000)
    }
    guard let items = content as? [[String: Any]] else { return nil }
    let text = items.compactMap { item -> String? in
        guard (item["type"] as? String) == "text" else { return nil }
        return item["text"] as? String
    }.joined(separator: "\n")
    return openClawTaskText(text, limit: 4_000)
}

private func openClawTaskText(_ value: String?, limit: Int) -> String? {
    guard let value else { return nil }
    let compact = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return nil }
    if compact.count <= limit { return compact }
    return String(compact.prefix(max(1, limit - 1))) + "…"
}

private func openClawDateValue(_ value: Any?) -> Date? {
    if let number = value as? NSNumber {
        let raw = number.doubleValue
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }
    guard let string = value as? String, !string.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let date = plain.date(from: string) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: string) { return date }
    }
    return nil
}

private func openClawInt64Value(_ value: Any?) -> Int64 {
    openClawInt64Optional(value) ?? 0
}

private func openClawInt64Optional(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) }
    return nil
}

private func openClawEpochNanoseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
}

private func openClawMaxDate(_ left: Date?, _ right: Date?) -> Date? {
    switch (left, right) {
    case let (left?, right?): return max(left, right)
    case let (left?, nil): return left
    case let (nil, right?): return right
    case (nil, nil): return nil
    }
}

private func openClawShortPath(_ path: String) -> String {
    guard !path.isEmpty else { return "OpenClaw" }
    let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return trimmed.split(separator: "/").last.map(String.init) ?? path
}

private func openClawDayKey(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func openClawHeatmapThresholds(_ values: [Int64]) -> [Int64] {
    guard !values.isEmpty else { return [1, 2, 3] }
    func percentile(_ fraction: Double) -> Int64 {
        let index = min(values.count - 1, max(0, Int((Double(values.count - 1) * fraction).rounded())))
        return values[index]
    }
    return [percentile(0.25), percentile(0.5), percentile(0.75)]
}

private func openClawToolCategory(_ name: String) -> String {
    let normalized = name.lowercased()
    if normalized.contains("browser") || normalized.contains("web") { return "Web" }
    if normalized.contains("exec") || normalized.contains("shell") { return "Shell" }
    if normalized.contains("read") || normalized.contains("write") || normalized.contains("file") { return "Files" }
    if normalized.contains("memory") { return "Memory" }
    if normalized.contains("skill") { return "Skill" }
    return "Tool"
}

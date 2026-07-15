import Foundation

struct ClaudeCodeRuntimeProvider: RuntimeUsageProvider {
    let scope: RuntimeScope = .claudeCode

    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot {
        var messages: [String] = []
        let transcriptLocal = ClaudeCodeTranscriptReader().loadLocalUsage(context: context, messages: &messages)
        let statsFallback = ClaudeCodeStatsCacheReader().loadFallbackLocalUsage(context: context, messages: &messages)
        let globalSkills = ClaudeCodeGlobalStateReader().loadSkillUsages(context: context, messages: &messages)
        let statusLine = ClaudeCodeStatusLineSnapshotReader().load(context: context, messages: &messages)
        let taskBoard = ClaudeCodeTaskReader().loadTaskBoard(context: context, messages: &messages)
        let local = mergeClaudeLocalUsage(transcriptLocal ?? statsFallback, globalSkills: globalSkills)

        if local == nil {
            messages.append("暂无 Claude Code 本机用量记录")
        }

        let status = makeStatus(local: local, statusLine: statusLine)
        let snapshot = UsageSnapshot(
            refreshedAt: context.now,
            account: AccountInfo(type: "local", planType: "Claude Code", emailPresent: false),
            limitId: scope.runtimeId,
            limitName: "Claude Code local",
            quotaReadSucceeded: statusLine.hasQuota,
            fiveHourQuota: statusLine.primary,
            sevenDayQuota: statusLine.secondary,
            credits: nil,
            cloudLifetimeTokens: nil,
            local: local,
            taskBoard: taskBoard,
            messages: messages
        )

        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: snapshot,
            status: status,
            quotaSourceLabel: statusLine.hasQuota ? "Claude statusLine + local records" : "Local records; quota needs statusLine",
            usageSourceLabel: "Claude Code local transcripts"
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        var messages: [String] = []
        return ClaudeCodeTaskReader().loadTaskBoard(context: context, messages: &messages)
    }

    private func makeStatus(local: LocalUsage?, statusLine: ClaudeStatusLineSnapshot) -> RuntimeMenuStatus {
        if statusLine.isStale {
            return .stale
        }
        if statusLine.hasQuota {
            return .available
        }
        if local != nil {
            return statusLine.exists ? .localOnly : .snapshotNeeded
        }
        return statusLine.exists ? .localOnly : .unavailable
    }
}

private final class ClaudeCodeTranscriptReader {
    private let fileManager = FileManager.default
    private let cacheVersion = 2

    func loadLocalUsage(context: RuntimeLoadContext, messages: inout [String]) -> LocalUsage? {
        let projectsRoot = context.homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)

        guard fileManager.fileExists(atPath: projectsRoot.path) else {
            messages.append("未找到 ~/.claude/projects")
            return nil
        }

        let transcriptFiles = enumerateJSONLFiles(under: projectsRoot)
        guard !transcriptFiles.isEmpty else {
            messages.append("未找到 Claude Code transcript JSONL")
            return nil
        }

        let cacheState = readCache(context: context)
        var cache = cacheState.cache
        var summaries: [ClaudeTranscriptSummary] = []
        var cacheChanged = cacheState.usesLegacySecondPrecision
        let livePaths = Set(transcriptFiles.map(\.path))

        if cache.entries.keys.contains(where: { !livePaths.contains($0) }) {
            cache.entries = cache.entries.filter { livePaths.contains($0.key) }
            cacheChanged = true
        }

        for file in transcriptFiles {
            guard let fingerprint = fingerprint(for: file) else { continue }
            let key = file.path
            if let entry = cache.entries[key],
               entry.matches(fingerprint)
                || (cacheState.usesLegacySecondPrecision && entry.matchesLegacySecond(fingerprint)) {
                if !entry.matches(fingerprint) {
                    cache.entries[key] = entry.updatingFingerprint(fingerprint)
                    cacheChanged = true
                }
                summaries.append(entry.summary)
                continue
            }

            let summary = parseTranscript(file: file, fingerprint: fingerprint)
            cache.entries[key] = ClaudeSessionCacheEntry(
                fileSize: fingerprint.fileSize,
                modificationTimeNanoseconds: fingerprint.modificationTimeNanoseconds,
                summary: summary
            )
            cacheChanged = true
            summaries.append(summary)
        }

        if cacheChanged, !writeCache(cache, context: context) {
            messages.append("Claude Code 本地缓存写入失败")
        }

        return makeLocalUsage(from: summaries, statistics: context.statistics, messages: &messages)
    }

    private func enumerateJSONLFiles(under root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    private func parseTranscript(file: URL, fingerprint: ClaudeFileFingerprint) -> ClaudeTranscriptSummary {
        let sessionId = file.deletingPathExtension().lastPathComponent
        var summary = ClaudeTranscriptSummary(
            filePath: file.path,
            sessionId: sessionId,
            projectPath: inferClaudeProjectPath(from: file),
            model: nil,
            lastActiveAt: fingerprint.modificationDate,
            deltas: [],
            toolCalls: [:],
            skillLoads: []
        )
        var seenMessageIds = Set<String>()

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return summary
        }
        defer { try? handle.close() }

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return summary
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.contains("\"usage\"") || line.contains("\"tool_use\"") || line.contains("attribution") else {
                continue
            }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let message = object["message"] as? [String: Any]
            let timestamp = claudeDateValue(object["timestamp"]) ?? fingerprint.modificationDate ?? Date()
            let projectPath = claudeStringValue(object["cwd"])
                ?? claudeStringValue(object["projectPath"])
                ?? summary.projectPath
            let model = claudeStringValue(message?["model"]) ?? claudeStringValue(object["model"]) ?? summary.model
            summary.projectPath = projectPath
            summary.model = model
            summary.lastActiveAt = maxDate(summary.lastActiveAt, timestamp)

            if let skillName = claudeStringValue(object["attributionSkill"])
                ?? claudeStringValue(object["attribution_skill"])
                ?? claudeStringValue(message?["attributionSkill"])
                ?? claudeStringValue(message?["attribution_skill"]) {
                summary.skillLoads.append(ClaudeSkillLoad(name: skillName, path: nil, date: timestamp))
            }

            parseToolCalls(from: message?["content"], at: timestamp, summary: &summary)

            guard let usage = message?["usage"] as? [String: Any],
                  let tokens = parseUsage(usage),
                  !tokens.isZero else {
                continue
            }

            let messageId = claudeStringValue(message?["id"])
                ?? claudeStringValue(object["uuid"])
                ?? claudeStringValue(object["id"])
            if let messageId, seenMessageIds.contains(messageId) {
                continue
            }
            if let messageId {
                seenMessageIds.insert(messageId)
            }

            summary.deltas.append(ClaudeUsageDelta(
                messageId: messageId,
                date: timestamp,
                tokens: tokens,
                model: model,
                projectPath: projectPath,
                sessionId: sessionId
            ))
        }

        return summary
    }

    private func parseToolCalls(from content: Any?, at date: Date, summary: inout ClaudeTranscriptSummary) {
        guard let items = content as? [Any] else { return }
        for item in items {
            guard let itemObject = item as? [String: Any],
                  claudeStringValue(itemObject["type"]) == "tool_use",
                  let name = claudeStringValue(itemObject["name"]),
                  !name.isEmpty else {
                continue
            }

            summary.toolCalls[name, default: 0] += 1
            if name.lowercased().contains("skill") {
                summary.skillLoads.append(ClaudeSkillLoad(name: name, path: nil, date: date))
            }
        }
    }

    private func parseUsage(_ usage: [String: Any]) -> TokenBreakdown? {
        let input = claudeInt64Value(usage["input_tokens"]) ?? 0
        let cacheCreation = claudeInt64Value(usage["cache_creation_input_tokens"]) ?? 0
        let cacheRead = claudeInt64Value(usage["cache_read_input_tokens"]) ?? 0
        let output = claudeInt64Value(usage["output_tokens"]) ?? 0
        let reasoning = claudeInt64Value(usage["reasoning_output_tokens"]) ?? 0
        let total = claudeInt64Value(usage["total_tokens"])
            ?? (input + cacheCreation + cacheRead + output + reasoning)

        return TokenBreakdown(
            inputTokens: input + cacheCreation + cacheRead,
            cachedInputTokens: cacheCreation + cacheRead,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
    }

    private func makeLocalUsage(
        from summaries: [ClaudeTranscriptSummary],
        statistics: StatisticsContext,
        messages: inout [String]
    ) -> LocalUsage? {
        let now = statistics.now
        var uniqueDeltas: [ClaudeUsageDelta] = []
        var seenMessageIds = Set<String>()
        for delta in summaries.flatMap(\.deltas) {
            if let messageId = delta.messageId {
                if seenMessageIds.contains(messageId) {
                    continue
                }
                seenMessageIds.insert(messageId)
            }
            uniqueDeltas.append(delta)
        }

        guard !uniqueDeltas.isEmpty else {
            messages.append("Claude Code transcript 中未找到 usage 事件")
            return nil
        }

        uniqueDeltas.sort { $0.date < $1.date }

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
        var dailyUsage: [String: (date: Date, usage: PricedTokenUsage)] = [:]
        var projects: [String: ClaudeProjectAccumulator] = [:]

        for delta in uniqueDeltas {
            let cost = claudeEstimatedCostUSD(tokens: delta.tokens, model: delta.model)
            lifetime.add(tokens: delta.tokens, costUSD: cost)
            if delta.date >= monthStart {
                month.add(tokens: delta.tokens, costUSD: cost)
            }
            if delta.date >= sevenDayStart {
                sevenDay.add(tokens: delta.tokens, costUSD: cost)
            }
            if delta.date >= previousSevenDayStart && delta.date < sevenDayStart {
                previousSevenDay.add(tokens: delta.tokens, costUSD: cost)
            }
            if delta.date >= dayStart {
                today.add(tokens: delta.tokens, costUSD: cost)
            }

            let bucketDate = calendar.startOfDay(for: delta.date)
            let key = statistics.dayKey(for: bucketDate)
            var dayUsage = dailyUsage[key]?.usage ?? .zero
            dayUsage.add(tokens: delta.tokens, costUSD: cost)
            dailyUsage[key] = (bucketDate, dayUsage)

            let projectPath = delta.projectPath.isEmpty ? "Claude Code" : delta.projectPath
            var project = projects[projectPath] ?? ClaudeProjectAccumulator(path: projectPath)
            project.add(delta: delta, costUSD: cost)
            projects[projectPath] = project
        }

        let detailed = DetailedUsage(
            today: today,
            sevenDay: sevenDay,
            month: month,
            lifetime: lifetime,
            parsedFileCount: summaries.count,
            tokenEventCount: uniqueDeltas.count
        )
        let dailyBuckets = makeSevenDayBuckets(dailyUsage: dailyUsage, now: now, calendar: calendar)
        let usageTrend = makeUsageTrend(
            dailyUsage: dailyUsage,
            sevenDay: sevenDay,
            previousSevenDay: previousSevenDay,
            month: month,
            now: now,
            calendar: calendar
        )
        let projectUsages = projects.values
            .map { $0.makeProject() }
            .sorted {
                if $0.tokens == $1.tokens {
                    return ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast)
                }
                return $0.tokens > $1.tokens
            }
        let recentThreads = makeRecentThreads(from: summaries)
        let toolUsages = makeToolUsages(from: summaries, lifetime: lifetime)
        let skillUsages = makeSkillUsages(from: summaries)

        let unknownModelCount = uniqueDeltas.filter { claudeModelPrice(for: $0.model) == nil }.count
        if unknownModelCount > 0 {
            messages.append("部分 Claude Code 模型没有内置价格，价值估算只包含可识别模型")
        }

        return LocalUsage(
            lifetimeTokens: lifetime.tokens.visibleTotalTokens,
            todayTokens: today.tokens.visibleTotalTokens,
            sevenDayTokens: sevenDay.tokens.visibleTotalTokens,
            threadCount: max(summaries.count, 1),
            lastUpdatedAt: summaries.compactMap(\.lastActiveAt).max(),
            dailyBuckets: dailyBuckets,
            recentThreads: recentThreads,
            detailedUsage: detailed,
            usageTrend: usageTrend,
            projectBoard: ProjectBoard(recentProjects: Array(projectUsages.prefix(8)), allProjects: projectUsages),
            toolUsages: toolUsages,
            skillUsages: skillUsages
        )
    }

    private func makeSevenDayBuckets(
        dailyUsage: [String: (date: Date, usage: PricedTokenUsage)],
        now: Date,
        calendar: Calendar
    ) -> [DailyTokenBucket] {
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.locale = Locale(identifier: "zh_CN")
        labelFormatter.dateFormat = "E"
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = claudeDayKey(date, calendar: calendar)
            return DailyTokenBucket(
                id: key,
                label: labelFormatter.string(from: date),
                tokens: dailyUsage[key]?.usage.tokens.visibleTotalTokens ?? 0
            )
        }
    }

    private func makeUsageTrend(
        dailyUsage: [String: (date: Date, usage: PricedTokenUsage)],
        sevenDay: PricedTokenUsage,
        previousSevenDay: PricedTokenUsage,
        month: PricedTokenUsage,
        now: Date,
        calendar: Calendar
    ) -> UsageTrend {
        let start = calendar.date(byAdding: .day, value: -179, to: calendar.startOfDay(for: now)) ?? now
        var buckets: [UsageDayBucket] = []
        var heatmapDays: [UsageHeatmapDay] = []

        for offset in 0..<180 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = claudeDayKey(date, calendar: calendar)
            let usage = dailyUsage[key]?.usage ?? .zero
            buckets.append(UsageDayBucket(id: key, date: date, usage: usage, sourceQuality: .detailed))
            heatmapDays.append(UsageHeatmapDay(id: key, date: date, usage: usage, isFuture: date > now))
        }

        let activeBuckets = buckets.filter { $0.tokens > 0 }
        let peak = activeBuckets.max { $0.tokens < $1.tokens }
        let previousTokens = previousSevenDay.tokens.visibleTotalTokens
        let currentTokens = sevenDay.tokens.visibleTotalTokens
        let changePercent: Double?
        if previousTokens > 0 {
            changePercent = (Double(currentTokens - previousTokens) / Double(previousTokens)) * 100
        } else {
            changePercent = nil
        }

        let summary = UsageTrendSummary(
            sevenDay: sevenDay,
            dailyAverageTokens: currentTokens / 7,
            peakDay: peak,
            changePercent: changePercent,
            isNewActivity: previousTokens == 0 && currentTokens > 0
        )
        let thresholds = makeHeatmapThresholds(activeBuckets.map(\.tokens))
        let heatmapWeeks = stride(from: 0, to: heatmapDays.count, by: 7).map { start in
            Array(heatmapDays[start..<min(start + 7, heatmapDays.count)])
        }

        return UsageTrend(
            dayBuckets: buckets,
            heatmapWeeks: heatmapWeeks,
            heatmapThresholds: thresholds,
            summary: summary,
            month: month,
            projectedMonthCostUSD: projectedMonthCost(monthCost: month.estimatedCostUSD, now: now, calendar: calendar),
            activeDayCount: activeBuckets.count,
            sourceQuality: .detailed
        )
    }

    private func makeHeatmapThresholds(_ tokens: [Int64]) -> [Int64] {
        let sorted = tokens.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return [1, 10, 100, 1000] }
        func percentile(_ value: Double) -> Int64 {
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * value).rounded())))
            return max(sorted[index], 1)
        }
        return [percentile(0.25), percentile(0.5), percentile(0.75), percentile(0.95)]
    }

    private func projectedMonthCost(monthCost: Double, now: Date, calendar: Calendar) -> Double? {
        let day = calendar.component(.day, from: now)
        guard day > 0,
              let range = calendar.range(of: .day, in: .month, for: now) else {
            return nil
        }
        return monthCost / Double(day) * Double(range.count)
    }

    private func makeRecentThreads(from summaries: [ClaudeTranscriptSummary]) -> [LocalThread] {
        summaries.map { summary in
            let tokens = summary.deltas.reduce(Int64(0)) { $0 + $1.tokens.visibleTotalTokens }
            return LocalThread(
                id: summary.sessionId,
                title: claudeShortWorkspaceName(summary.projectPath),
                tokens: tokens,
                updatedAt: summary.lastActiveAt,
                model: summary.model,
                cwd: summary.projectPath,
                archived: false
            )
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        .prefix(12)
        .map { $0 }
    }

    private func makeToolUsages(from summaries: [ClaudeTranscriptSummary], lifetime: PricedTokenUsage) -> [ToolUsage] {
        var calls: [String: Int] = [:]
        for summary in summaries {
            for (name, count) in summary.toolCalls {
                calls[name, default: 0] += count
            }
        }

        let totalCalls = max(calls.values.reduce(0, +), 1)
        let tokensPerCall = lifetime.tokens.visibleTotalTokens / Int64(totalCalls)
        let costPerCall = lifetime.estimatedCostUSD / Double(totalCalls)

        return calls.map { name, count in
            ToolUsage(
                id: name,
                name: name,
                category: claudeToolCategory(for: name),
                callCount: count,
                estimatedTokens: tokensPerCall > 0 ? tokensPerCall * Int64(count) : nil,
                estimatedCostUSD: costPerCall > 0 ? costPerCall * Double(count) : nil
            )
        }
        .sorted { $0.callCount > $1.callCount }
    }

    private func makeSkillUsages(from summaries: [ClaudeTranscriptSummary]) -> [SkillUsage] {
        var map: [String: ClaudeSkillAccumulator] = [:]
        for summary in summaries {
            for skill in summary.skillLoads {
                let key = skill.path ?? skill.name
                var current = map[key] ?? ClaudeSkillAccumulator(name: skill.name, path: skill.path ?? key)
                current.add(sessionId: summary.sessionId, at: skill.date)
                map[key] = current
            }
        }
        return map.values.map { $0.makeSkillUsage() }
            .sorted { $0.loadCount > $1.loadCount }
    }

    private func readCache(
        context: RuntimeLoadContext
    ) -> (cache: ClaudeSessionDiskCache, usesLegacySecondPrecision: Bool) {
        let url = cacheURL(context: context)
        guard let data = try? Data(contentsOf: url) else {
            return (ClaudeSessionDiskCache(version: cacheVersion, entries: [:]), false)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let cache = try? decoder.decode(ClaudeSessionDiskCache.self, from: data),
              cache.version == cacheVersion else {
            let legacyDecoder = JSONDecoder()
            legacyDecoder.dateDecodingStrategy = .iso8601
            guard let legacy = try? legacyDecoder.decode(LegacyClaudeSessionDiskCache.self, from: data),
                  legacy.version == 1 else {
                return (ClaudeSessionDiskCache(version: cacheVersion, entries: [:]), false)
            }
            let migrated = legacy.entries.mapValues { entry in
                ClaudeSessionCacheEntry(
                    fileSize: entry.fileSize,
                    modificationTimeNanoseconds: entry.modificationDate.map(epochNanoseconds),
                    summary: entry.summary
                )
            }
            return (ClaudeSessionDiskCache(version: cacheVersion, entries: migrated), true)
        }
        return (cache, false)
    }

    private func writeCache(_ cache: ClaudeSessionDiskCache, context: RuntimeLoadContext) -> Bool {
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
            .appendingPathComponent("claude-code", isDirectory: true)
            .appendingPathComponent("session-usage-v1.json")
    }

    private func fingerprint(for file: URL) -> ClaudeFileFingerprint? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return ClaudeFileFingerprint(
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate,
            modificationTimeNanoseconds: values.contentModificationDate.map(epochNanoseconds)
        )
    }
}

private final class ClaudeCodeStatsCacheReader {
    func loadFallbackLocalUsage(context: RuntimeLoadContext, messages: inout [String]) -> LocalUsage? {
        let url = context.homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("stats-cache.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let todayTokens = claudeInt64Value(object["todayTokens"]) ?? claudeInt64Value(object["today_tokens"]) ?? 0
        let sevenDayTokens = claudeInt64Value(object["sevenDayTokens"]) ?? claudeInt64Value(object["seven_day_tokens"]) ?? 0
        let lifetimeTokens = claudeInt64Value(object["totalTokens"]) ?? claudeInt64Value(object["total_tokens"]) ?? max(todayTokens, sevenDayTokens)
        guard lifetimeTokens > 0 else { return nil }

        let tokens = TokenBreakdown(
            inputTokens: lifetimeTokens,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: lifetimeTokens
        )
        let usage = PricedTokenUsage(tokens: tokens, estimatedCostUSD: claudeDoubleValue(object["totalCostUSD"]) ?? claudeDoubleValue(object["total_cost_usd"]) ?? 0)
        let detailed = DetailedUsage(
            today: PricedTokenUsage(tokens: TokenBreakdown(inputTokens: todayTokens, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: todayTokens), estimatedCostUSD: 0),
            sevenDay: PricedTokenUsage(tokens: TokenBreakdown(inputTokens: sevenDayTokens, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: sevenDayTokens), estimatedCostUSD: 0),
            month: usage,
            lifetime: usage,
            parsedFileCount: 1,
            tokenEventCount: 0
        )
        messages.append("Claude Code 使用 stats-cache fallback；详细拆分不可用")

        return LocalUsage(
            lifetimeTokens: lifetimeTokens,
            todayTokens: todayTokens,
            sevenDayTokens: sevenDayTokens,
            threadCount: 0,
            lastUpdatedAt: claudeDateValue(object["updatedAt"]) ?? claudeDateValue(object["updated_at"]),
            dailyBuckets: [],
            recentThreads: [],
            detailedUsage: detailed,
            usageTrend: nil,
            projectBoard: nil,
            toolUsages: [],
            skillUsages: []
        )
    }
}

private final class ClaudeCodeGlobalStateReader {
    func loadSkillUsages(context: RuntimeLoadContext, messages: inout [String]) -> [SkillUsage] {
        let url = context.homeDirectory.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        guard let skillUsage = object["skillUsage"] as? [String: Any]
            ?? object["skill_usage"] as? [String: Any] else {
            return []
        }

        return skillUsage.compactMap { name, rawValue in
            let count: Int
            let lastLoadedAt: Date?
            if let number = rawValue as? NSNumber {
                count = number.intValue
                lastLoadedAt = nil
            } else if let item = rawValue as? [String: Any] {
                count = Int(claudeInt64Value(item["loadCount"]) ?? claudeInt64Value(item["load_count"]) ?? 1)
                lastLoadedAt = claudeDateValue(item["lastLoadedAt"]) ?? claudeDateValue(item["last_loaded_at"])
            } else {
                return nil
            }
            return SkillUsage(
                id: "claude-global-\(name)",
                name: name,
                path: name,
                sourceLabel: "Claude Code global state",
                loadCount: max(count, 1),
                threadCount: 0,
                staticTokenEstimate: nil,
                staticByteCount: nil,
                lastLoadedAt: lastLoadedAt
            )
        }
    }
}

private final class ClaudeCodeStatusLineSnapshotReader {
    func load(context: RuntimeLoadContext, messages: inout [String]) -> ClaudeStatusLineSnapshot {
        let url = context.cacheDirectory
            .appendingPathComponent("claude-code", isDirectory: true)
            .appendingPathComponent("statusline-snapshot.json")
        guard let data = try? Data(contentsOf: url) else {
            messages.append("额度需要 Claude Code active session 快照")
            return ClaudeStatusLineSnapshot(exists: false, capturedAt: nil, primary: nil, secondary: nil, isStale: false)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            messages.append("Claude Code statusLine 快照无法解析")
            return ClaudeStatusLineSnapshot(exists: true, capturedAt: nil, primary: nil, secondary: nil, isStale: false)
        }

        let capturedAt = claudeDateValue(object["capturedAt"]) ?? claudeDateValue(object["captured_at"])
        let isStale = capturedAt.map { context.now.timeIntervalSince($0) > 900 } ?? false
        if isStale {
            messages.append("Claude Code 快照已过期，打开 Claude Code 后刷新")
        }

        let rateLimits = claudeDictionaryValue(object["rateLimits"]) ?? claudeDictionaryValue(object["rate_limits"])
        let fiveHour = claudeDictionaryValue(rateLimits?["fiveHour"]) ?? claudeDictionaryValue(rateLimits?["five_hour"])
        let sevenDay = claudeDictionaryValue(rateLimits?["sevenDay"]) ?? claudeDictionaryValue(rateLimits?["seven_day"])

        return ClaudeStatusLineSnapshot(
            exists: true,
            capturedAt: capturedAt,
            primary: makeRateWindow(fiveHour, durationMins: 300),
            secondary: makeRateWindow(sevenDay, durationMins: 10_080),
            isStale: isStale
        )
    }

    private func makeRateWindow(_ object: [String: Any]?, durationMins: Int) -> RateWindow? {
        guard let object,
              let usedPercent = claudeDoubleValue(object["usedPercentage"]) ?? claudeDoubleValue(object["used_percentage"]) else {
            return nil
        }
        let resetsAt = claudeDateValue(object["resetsAt"]) ?? claudeDateValue(object["resets_at"])
        return RateWindow(
            usedPercent: max(0, min(100, usedPercent)),
            windowDurationMins: durationMins,
            resetsAt: resetsAt
        )
    }
}

private final class ClaudeCodeTaskReader {
    private let fileManager = FileManager.default

    func loadTaskBoard(context: RuntimeLoadContext, messages: inout [String]) -> TaskBoard? {
        let root = context.homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("tasks", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        let items: [TaskItem] = enumerator.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "json" else { return nil }
            return parseTask(url: url)
        }

        guard !items.isEmpty else { return nil }
        let columns = [
            makeColumn(.active, title: "进行中", items: items),
            makeColumn(.pending, title: "待处理", items: items),
            makeColumn(.scheduled, title: "计划中", items: items),
            makeColumn(.done, title: "完成", items: items)
        ]
        return TaskBoard(refreshedAt: context.now, columns: columns)
    }

    private func parseTask(url: URL) -> TaskItem? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let status = claudeStringValue(object["status"]) ?? "pending"
        let kind = taskKind(for: status)
        let title = claudeStringValue(object["subject"])
            ?? claudeStringValue(object["title"])
            ?? url.deletingPathExtension().lastPathComponent
        let updatedAt = claudeDateValue(object["updatedAt"])
            ?? claudeDateValue(object["updated_at"])
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        return TaskItem(
            id: url.path,
            code: status,
            title: title,
            detail: "Claude Code task",
            chip: status,
            updatedAt: updatedAt,
            tokens: nil,
            kind: kind
        )
    }

    private func taskKind(for status: String) -> TaskColumnKind {
        switch status.lowercased() {
        case "in_progress", "active", "running":
            return .active
        case "completed", "done", "success":
            return .done
        case "scheduled":
            return .scheduled
        default:
            return .pending
        }
    }

    private func makeColumn(_ kind: TaskColumnKind, title: String, items: [TaskItem]) -> TaskColumn {
        let columnItems = items
            .filter { $0.kind == kind }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        return TaskColumn(id: kind, title: title, count: columnItems.count, items: columnItems)
    }
}

private struct ClaudeStatusLineSnapshot {
    let exists: Bool
    let capturedAt: Date?
    let primary: RateWindow?
    let secondary: RateWindow?
    let isStale: Bool

    var hasQuota: Bool {
        primary != nil || secondary != nil
    }
}

private struct ClaudeFileFingerprint {
    let fileSize: Int64
    let modificationDate: Date?
    let modificationTimeNanoseconds: Int64?
}

private struct ClaudeSessionCacheEntry: Codable {
    let fileSize: Int64
    let modificationTimeNanoseconds: Int64?
    let summary: ClaudeTranscriptSummary

    func matches(_ fingerprint: ClaudeFileFingerprint) -> Bool {
        fileSize == fingerprint.fileSize
            && modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds
    }

    func matchesLegacySecond(_ fingerprint: ClaudeFileFingerprint) -> Bool {
        guard fileSize == fingerprint.fileSize,
              let cached = modificationTimeNanoseconds,
              let current = fingerprint.modificationTimeNanoseconds else {
            return modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds
        }
        return cached / 1_000_000_000 == current / 1_000_000_000
    }

    func updatingFingerprint(_ fingerprint: ClaudeFileFingerprint) -> ClaudeSessionCacheEntry {
        ClaudeSessionCacheEntry(
            fileSize: fingerprint.fileSize,
            modificationTimeNanoseconds: fingerprint.modificationTimeNanoseconds,
            summary: summary
        )
    }
}

private struct ClaudeSessionDiskCache: Codable {
    let version: Int
    var entries: [String: ClaudeSessionCacheEntry]
}

private struct LegacyClaudeSessionCacheEntry: Codable {
    let fileSize: Int64
    let modificationDate: Date?
    let summary: ClaudeTranscriptSummary
}

private struct LegacyClaudeSessionDiskCache: Codable {
    let version: Int
    let entries: [String: LegacyClaudeSessionCacheEntry]
}

private func epochNanoseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
}

private struct ClaudeTranscriptSummary: Codable {
    let filePath: String
    let sessionId: String
    var projectPath: String
    var model: String?
    var lastActiveAt: Date?
    var deltas: [ClaudeUsageDelta]
    var toolCalls: [String: Int]
    var skillLoads: [ClaudeSkillLoad]
}

private struct ClaudeUsageDelta: Codable {
    let messageId: String?
    let date: Date
    let tokens: TokenBreakdown
    let model: String?
    let projectPath: String
    let sessionId: String
}

private struct ClaudeSkillLoad: Codable {
    let name: String
    let path: String?
    let date: Date?
}

private struct ClaudeModelPrice {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double
}

private struct ClaudeProjectAccumulator {
    let path: String
    var tokens = TokenBreakdown.zero
    var estimatedCostUSD: Double = 0
    var sessionIds = Set<String>()
    var lastActiveAt: Date?

    mutating func add(delta: ClaudeUsageDelta, costUSD: Double) {
        tokens.add(delta.tokens)
        estimatedCostUSD += costUSD
        sessionIds.insert(delta.sessionId)
        lastActiveAt = maxDate(lastActiveAt, delta.date)
    }

    func makeProject() -> ProjectUsage {
        ProjectUsage(
            id: path,
            name: claudeShortWorkspaceName(path),
            fullPath: path,
            tokens: tokens.visibleTotalTokens,
            estimatedCostUSD: estimatedCostUSD > 0 ? estimatedCostUSD : nil,
            threadCount: max(sessionIds.count, 1),
            lastActiveAt: lastActiveAt,
            sourceQuality: .detailed
        )
    }
}

private struct ClaudeSkillAccumulator {
    let name: String
    let path: String
    var loadCount = 0
    var sessionIds = Set<String>()
    var lastLoadedAt: Date?

    mutating func add(sessionId: String, at date: Date?) {
        loadCount += 1
        sessionIds.insert(sessionId)
        lastLoadedAt = maxDate(lastLoadedAt, date)
    }

    func makeSkillUsage() -> SkillUsage {
        SkillUsage(
            id: path,
            name: name,
            path: path,
            sourceLabel: "Claude Code transcript",
            loadCount: max(loadCount, 1),
            threadCount: max(sessionIds.count, 1),
            staticTokenEstimate: nil,
            staticByteCount: nil,
            lastLoadedAt: lastLoadedAt
        )
    }
}

private func mergeClaudeLocalUsage(_ local: LocalUsage?, globalSkills: [SkillUsage]) -> LocalUsage? {
    guard !globalSkills.isEmpty else { return local }
    guard let local else {
        return LocalUsage(
            lifetimeTokens: 0,
            todayTokens: 0,
            sevenDayTokens: 0,
            threadCount: 0,
            lastUpdatedAt: nil,
            dailyBuckets: [],
            recentThreads: [],
            detailedUsage: nil,
            usageTrend: nil,
            projectBoard: nil,
            toolUsages: [],
            skillUsages: globalSkills
        )
    }

    let mergedSkills = mergeClaudeSkillUsages(local.skillUsages + globalSkills)
    return LocalUsage(
        lifetimeTokens: local.lifetimeTokens,
        todayTokens: local.todayTokens,
        sevenDayTokens: local.sevenDayTokens,
        threadCount: local.threadCount,
        lastUpdatedAt: local.lastUpdatedAt,
        dailyBuckets: local.dailyBuckets,
        recentThreads: local.recentThreads,
        detailedUsage: local.detailedUsage,
        usageTrend: local.usageTrend,
        projectBoard: local.projectBoard,
        toolUsages: local.toolUsages,
        skillUsages: mergedSkills
    )
}

private func mergeClaudeSkillUsages(_ skills: [SkillUsage]) -> [SkillUsage] {
    var map: [String: SkillUsage] = [:]
    for skill in skills {
        if let existing = map[skill.id] {
            map[skill.id] = SkillUsage(
                id: existing.id,
                name: existing.name,
                path: existing.path,
                sourceLabel: existing.sourceLabel,
                loadCount: existing.loadCount + skill.loadCount,
                threadCount: max(existing.threadCount, 0) + max(skill.threadCount, 0),
                staticTokenEstimate: existing.staticTokenEstimate ?? skill.staticTokenEstimate,
                staticByteCount: existing.staticByteCount ?? skill.staticByteCount,
                lastLoadedAt: maxDate(existing.lastLoadedAt, skill.lastLoadedAt)
            )
        } else {
            map[skill.id] = skill
        }
    }
    return map.values.sorted { $0.loadCount > $1.loadCount }
}

private func inferClaudeProjectPath(from file: URL) -> String {
    let encoded = file.deletingLastPathComponent().lastPathComponent
    guard encoded.hasPrefix("-") else {
        return encoded
    }
    return encoded.replacingOccurrences(of: "-", with: "/")
}

private func claudeModelPrice(for model: String?) -> ClaudeModelPrice? {
    let normalized = (model ?? "").lowercased()
    guard !normalized.isEmpty else { return nil }

    if normalized.contains("opus") {
        return ClaudeModelPrice(inputPerMillion: 15, cachedInputPerMillion: 1.5, outputPerMillion: 75)
    }
    if normalized.contains("sonnet") {
        return ClaudeModelPrice(inputPerMillion: 3, cachedInputPerMillion: 0.3, outputPerMillion: 15)
    }
    if normalized.contains("haiku") {
        return ClaudeModelPrice(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, outputPerMillion: 4)
    }
    return nil
}

private func claudeEstimatedCostUSD(tokens: TokenBreakdown, model: String?) -> Double {
    guard let price = claudeModelPrice(for: model) else { return 0 }
    let uncachedInputCost = Double(tokens.uncachedInputTokens) / 1_000_000 * price.inputPerMillion
    let cachedInputCost = Double(tokens.billableCachedInputTokens) / 1_000_000 * price.cachedInputPerMillion
    let outputCost = Double(max(tokens.outputTokens, 0)) / 1_000_000 * price.outputPerMillion
    return uncachedInputCost + cachedInputCost + outputCost
}

private func claudeDayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func claudeShortWorkspaceName(_ path: String) -> String {
    guard !path.isEmpty else { return "Claude Code" }
    let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return trimmed.split(separator: "/").last.map(String.init) ?? path
}

private func claudeToolCategory(for name: String) -> String {
    let normalized = name.lowercased()
    if normalized.contains("bash") || normalized.contains("shell") || normalized.contains("terminal") {
        return "terminal"
    }
    if normalized.contains("edit") || normalized.contains("write") || normalized.contains("patch") {
        return "edit"
    }
    if normalized.contains("read") || normalized.contains("grep") || normalized.contains("glob") {
        return "docs"
    }
    if normalized.contains("web") || normalized.contains("browser") || normalized.contains("fetch") {
        return "browser"
    }
    if normalized.contains("task") || normalized.contains("agent") || normalized.contains("todo") {
        return "planning"
    }
    if normalized.contains("mcp") {
        return "mcp"
    }
    return "tool"
}

private func claudeStringValue(_ value: Any?) -> String? {
    if let string = value as? String, !string.isEmpty {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func claudeInt64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
        return number.int64Value
    }
    if let string = value as? String {
        return Int64(string)
    }
    return nil
}

private func claudeDoubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let string = value as? String {
        return Double(string)
    }
    return nil
}

private func claudeDictionaryValue(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func claudeDateValue(_ value: Any?) -> Date? {
    if let date = value as? Date {
        return date
    }
    if let number = value as? NSNumber {
        let raw = number.doubleValue
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
    guard let string = value as? String, !string.isEmpty else {
        return nil
    }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}

private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (left?, right?):
        return max(left, right)
    case let (left?, nil):
        return left
    case let (nil, right?):
        return right
    case (nil, nil):
        return nil
    }
}

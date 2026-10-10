import Foundation

extension UsageSQLValue {
    var number: Double? {
        switch self { case .real(let value): return value; case .integer(let value): return Double(value); default: return nil }
    }
}

struct UsageArchiveDetails {
    var projects: ProjectBoard?
    var tools: [ToolUsage] = []
    var skills: [SkillUsage] = []
    var inference: ModelInferencePerformanceHistory?
}

extension UsageIndexStore {
    /// All joins use the published build's membership and frozen input revision. SQLite performs
    /// grouping/ranking with its disk-backed temporary store; no transcript bodies are reopened.
    func archiveDetails(manifest: UsageArchiveManifest, statistics: StatisticsContext, runtime: String) throws -> UsageArchiveDetails {
        let build = manifest.buildID
        let cut = manifest.inputRevision
        let effective = """
            WITH effective AS (
              SELECT f.*,m.projection_id FROM fact f JOIN build_member m ON m.source_id=f.source_id AND m.build_id=?
              JOIN source_projection p ON p.id=m.projection_id AND p.generation=f.generation
              WHERE f.commit_revision<=? AND f.operation='upsert'
              AND NOT EXISTS (SELECT 1 FROM fact n WHERE n.source_id=f.source_id AND n.generation=f.generation
                AND n.kind=f.kind AND n.logical_key=f.logical_key AND n.commit_revision<=?
                AND (n.commit_revision>f.commit_revision OR (n.commit_revision=f.commit_revision AND n.sequence>f.sequence))))
            """
        let bindings: [UsageSQLValue] = [.text(build), .integer(cut), .integer(cut)]
        let priced = """
            , priced AS (SELECT d.projection_id,sum(json_extract(d.payload,'$.tokens.totalTokens')) tokens,
              sum(json_extract(d.payload,'$.estimatedCostUSD')) cost FROM source_day d
              JOIN build_member m ON m.projection_id=d.projection_id AND m.build_id=? WHERE d.day_key<>'' GROUP BY d.projection_id)
            """
        let toolRows = try rows(effective + priced + """
            , calls AS (SELECT projection_id,json_extract(payload,'$.tool.name') name,
                sum(json_extract(payload,'$.tool.count')) calls FROM effective WHERE kind='tool' GROUP BY projection_id,name),
              totals AS (SELECT projection_id,sum(calls) calls FROM calls GROUP BY projection_id)
            SELECT c.name,sum(c.calls),sum(round(coalesce(p.tokens,0)*1.0*c.calls/t.calls)),
              sum(coalesce(p.cost,0)*c.calls/t.calls) FROM calls c JOIN totals t ON t.projection_id=c.projection_id
              LEFT JOIN priced p ON p.projection_id=c.projection_id GROUP BY c.name ORDER BY sum(c.calls) DESC,c.name LIMIT 1001
            """, bindings + [.text(build)], limit: 1000)
        var result = UsageArchiveDetails()
        let totalCalls = toolRows.reduce(Int64(0)) { $0 + ($1[1].integer ?? 0) }
        let allPrice = try rows(priced.replacingOccurrences(of: ", priced AS", with: "WITH priced AS") + " SELECT sum(tokens),sum(cost) FROM priced",
                                [.text(build)], limit: 1).first
        result.tools = toolRows.compactMap { row in
            guard let name = row[0].text, let calls = row[1].integer else { return nil }
            let tokens: Int64
            let cost: Double
            if runtime == "claude-code" {
                tokens = (allPrice?[0].integer ?? 0) / max(totalCalls, 1) * calls
                cost = (allPrice?[1].number ?? 0) / Double(max(totalCalls, 1)) * Double(calls)
            } else { tokens = Int64(row[2].number ?? 0); cost = row[3].number ?? 0 }
            return ToolUsage(id: name, name: name, category: runtime == "codex" ? toolCategory(for: name) : claudeToolCategory(for: name),
                callCount: Int(calls), estimatedTokens: tokens > 0 ? tokens : nil, estimatedCostUSD: cost > 0 ? cost : nil)
        }
        let skillRows = try rows(effective + """
            , skills AS (SELECT source_id,occurred_at_ms,
              CASE WHEN kind='skill' THEN json_extract(payload,'$.skill._0.path')
                ELSE coalesce(json_extract(payload,'$.claudeSkill._0.path'),'claude-skill:'||json_extract(payload,'$.claudeSkill._0.name')) END path,
              json_extract(payload,'$.claudeSkill._0.name') name FROM effective WHERE kind IN ('skill','claudeSkill'))
            SELECT path,max(name),count(*),count(DISTINCT source_id),max(occurred_at_ms) FROM skills
            GROUP BY path ORDER BY count(*) DESC,path LIMIT 1001
            """, bindings, limit: 1000)
        result.skills = skillRows.compactMap { row in
            guard let path = row[0].text else { return nil }
            return SkillUsage(id: path, name: row[1].text ?? skillName(from: path), path: path,
                sourceLabel: runtime == "codex" ? skillSourceLabel(from: path) : "Claude Code transcript",
                loadCount: Int(row[2].integer ?? 0), threadCount: Int(row[3].integer ?? 0),
                staticTokenEstimate: nil, staticByteCount: nil,
                lastLoadedAt: row[4].number.map { Date(timeIntervalSince1970: $0 / 1000) })
        }
        let sevenKey = statistics.dayKey(for: statistics.calendar.date(byAdding: .day, value: -6, to: statistics.startOfDay(for: statistics.now))!)
        func projects(since: String) throws -> [ProjectUsage] {
            let values = try rows("""
                SELECT json_extract(d.payload,'$.path'),sum(json_extract(d.payload,'$.tokens')),
                  sum(json_extract(d.payload,'$.cost')),count(DISTINCT m.source_id),max(json_extract(d.payload,'$.lastActiveAt'))
                FROM source_day d JOIN build_member m ON m.projection_id=d.projection_id AND m.build_id=?
                WHERE d.day_key='' AND d.dimension_key LIKE 'project:%' AND json_extract(d.payload,'$.day')>=?
                GROUP BY 1 ORDER BY 2 DESC,1 LIMIT 24
                """, [.text(build), .text(since)], limit: 24)
            return values.compactMap { row in
                guard let path = row[0].text else { return nil }
                return ProjectUsage(id: path.isEmpty ? "uncategorized" : path,
                    name: path.isEmpty ? "未归类" : URL(fileURLWithPath: path).lastPathComponent, fullPath: path,
                    tokens: row[1].integer ?? 0, estimatedCostUSD: row[2].number, threadCount: Int(row[3].integer ?? 0),
                    lastActiveAt: row[4].number.map { Date(timeIntervalSinceReferenceDate: $0) }, sourceQuality: .detailed)
            }
        }
        result.projects = try ProjectBoard(recentProjects: projects(since: sevenKey), allProjects: projects(since: ""))
        if runtime == "codex" { result.inference = try archiveInference(effective: effective, bindings: bindings, cut: cut, statistics: statistics) }
        return result
    }

    private func archiveInference(effective: String, bindings: [UsageSQLValue], cut: Int64,
                                  statistics: StatisticsContext) throws -> ModelInferencePerformanceHistory? {
        // Rank the independent inference stream before trimming the inherited fork prefix.
        let samples = effective + """
            , ranked AS (SELECT e.*,row_number() OVER(PARTITION BY source_id ORDER BY logical_key) sample_number
                FROM effective e WHERE kind='inference'),
              samples AS (SELECT json_extract(payload,'$.inference._0.model') model,
                json_extract(payload,'$.inference._0.effort') effort,
                json_extract(payload,'$.inference._0.durationSeconds') duration,
                json_extract(payload,'$.inference._0.outputTokens') output,
                json_extract(payload,'$.inference._0.reasoningOutputTokens') reasoning,occurred_at_ms completed
                FROM ranked r WHERE sample_number>coalesce((SELECT inference_prefix FROM dependency_version d
                  WHERE d.child_source_id=r.source_id AND d.child_generation=r.generation AND d.valid_from<=\(cut)
                    AND (d.valid_to IS NULL OR d.valid_to>\(cut))),0))
            """
        guard let earliest = try rows(samples + " SELECT min(completed) FROM samples WHERE duration>=0.1 AND output>0", bindings, limit: 1).first?.first?.number else { return nil }
        let recorded = try rows("SELECT value FROM index_meta WHERE key='inference-recording-start'",limit:1).first?.first?.text.flatMap(Double.init)
        let startSeconds = min(recorded ?? earliest/1000, earliest/1000)
        try execute("INSERT INTO index_meta(key,value) VALUES ('inference-recording-start',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[.text(String(startSeconds))])
        let started = Date(timeIntervalSince1970: startSeconds)
        let today = statistics.startOfDay(for: statistics.now)
        let end = statistics.calendar.date(byAdding: .day, value: 1, to: today)!
        func performance(_ period: ModelInferencePeriod) throws -> ModelInferencePerformance? {
            let start = statistics.calendar.date(byAdding: .day, value: 1-period.dayCount, to: today)!
            let coverageStart = max(start, statistics.startOfDay(for: started))
            let coverage = min(max((statistics.calendar.dateComponents([.day], from: coverageStart, to: today).day ?? 0)+1,1),period.dayCount)
            let window = samples + ", selected AS (SELECT * FROM samples WHERE duration>=0.1 AND output>0 AND completed>=? AND completed<?)"
            let args = bindings + [.integer(try usageIndexMilliseconds(start)), .integer(try usageIndexMilliseconds(end))]
            let summaries = try rows(window + " SELECT model,effort,count(*),sum(duration),sum(output),sum(reasoning) FROM selected GROUP BY model,effort ORDER BY count(*) DESC,model,effort LIMIT 1001", args, limit: 1000)
            var groups: [ModelInferencePerformanceGroup] = []
            for row in summaries {
                guard let model = row[0].text, let effort = row[1].text, let count = row[2].integer,
                      let duration = row[3].number, duration > 0 else { throw UsageIndexError.cacheInvalid }
                func percentile(_ fraction: Double) throws -> Double {
                    let position = Double(count-1)*fraction
                    let low = Int64(position.rounded(.down)), high = Int64(position.rounded(.up))
                    let values = try rows(window + " SELECT duration FROM selected WHERE model=? AND effort=? ORDER BY duration LIMIT ? OFFSET ?",
                        args + [.text(model),.text(effort),.integer(high-low+1),.integer(low)], limit: 2)
                    guard let first = values.first?.first?.number, let last = values.last?.first?.number else { throw UsageIndexError.cacheInvalid }
                    return first+(last-first)*(position-Double(low))
                }
                let output = row[4].integer ?? 0
                groups.append(try ModelInferencePerformanceGroup(id: modelInferencePerformanceID(model: model, effort: effort), model: model,
                    effort: effort, callCount: Int(count), averageDailyCallCount: Double(count)/Double(coverage),
                    averageDurationSeconds: duration/Double(count), p50DurationSeconds: percentile(0.5), p90DurationSeconds: percentile(0.9),
                    effectiveOutputTokensPerSecond: Double(output)/duration, outputTokens: output, reasoningOutputTokens: row[5].integer ?? 0))
            }
            return groups.isEmpty ? nil : ModelInferencePerformance(period: period, coverageDayCount: coverage, groups: groups, totalCallCount: groups.reduce(0) { $0+$1.callCount })
        }
        let result = try ModelInferencePerformanceHistory(recordingStartedAt: started, today: performance(.today),
            sevenDays: performance(.sevenDays), twentyEightDays: performance(.twentyEightDays))
        return result.today == nil && result.sevenDays == nil && result.twentyEightDays == nil ? nil : result
    }
}

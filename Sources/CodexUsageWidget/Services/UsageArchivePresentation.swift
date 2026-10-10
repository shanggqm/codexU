import Foundation

struct UsageArchivePresentation {
    let local: LocalUsage
    let observedAt: Date
    let complete: Bool
    let revision: Int64
    var leadership: LeadershipDashboardSnapshot? = nil
    var hasDetails = false
    var leadershipComplete = false
    var scope: RuntimeScope = .codex
}

extension UsageIndexStore {
    /// Read only a published manifest, never the largest revision from each day independently.
    /// Called on the history worker; the home receives its compact DTO, not a database connection.
    func archivePresentation(context: String, statistics: StatisticsContext, runtime: String = "codex", includeDetails: Bool = false) throws -> UsageArchivePresentation? {
        guard let row = try rows("SELECT payload,observed_at_ms,coverage FROM published_slice WHERE context_id=? AND domain='archive' AND runtime=?",
                                 [.text(context), .text(runtime)], limit: 1).first,
              let payload = row[0].text, let observed = row[1].integer else { return nil }
        let manifest = try JSONDecoder().decode(UsageArchiveManifest.self, from: Data(payload.utf8))
        let calendar = statistics.calendar
        let dayStart = statistics.startOfDay(for: statistics.now)
        let sevenStart = calendar.date(byAdding: .day, value: -6, to: dayStart)!
        let trendStart = calendar.date(byAdding: .day, value: -190, to: dayStart)!
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: dayStart))!
        let todayKey = statistics.dayKey(for: dayStart), sevenKey = statistics.dayKey(for: sevenStart)
        let trendKey = statistics.dayKey(for: trendStart), monthKey = statistics.dayKey(for: monthStart)
        var lifetime = PricedTokenUsage.zero, today = PricedTokenUsage.zero
        var seven = PricedTokenUsage.zero, month = PricedTokenUsage.zero
        var days: [String: PricedTokenUsage] = [:]
        var modelDays: [String: [String: PricedTokenUsage]] = [:]
        var modelNames: [String: String] = [:]
        var eventCount = 0
        var after = ""
        func add(_ target: inout PricedTokenUsage, _ value: PricedTokenUsage) throws {
            target.tokens = try checkedTokenSum(target.tokens, value.tokens)
            target.estimatedCostUSD += value.estimatedCostUSD
            guard target.estimatedCostUSD.isFinite else { throw UsageIndexError.resourceLimited }
            target.usesReferencePricing = target.usesReferencePricing || value.usesReferencePricing
        }
        while true {
            let page = try rows("SELECT day_key,payload FROM archive_day WHERE context_id=? AND revision_id=? AND day_key>? ORDER BY day_key LIMIT 12",
                [.text(context), .integer(manifest.publicationRevision), .text(after)], limit: 12)
            if page.isEmpty { break }
            for dayRow in page {
                guard let key = dayRow[0].text, let payload = dayRow[1].text else { throw UsageIndexError.cacheInvalid }
                after = key
                let day = try JSONDecoder().decode(UsageArchivedDay.self, from: Data(payload.utf8))
                var priced = PricedTokenUsage.zero
                for value in day.dimensions.values {
                    try add(&priced, PricedTokenUsage(tokens: value.tokens, estimatedCostUSD: value.estimatedCostUSD, usesReferencePricing: value.usesReferencePricing))
                    if key>=trendKey && key<=todayKey {
                        let id=modelUsageIdentifier(for:value.model)
                        var modelDay=modelDays[id]?[key] ?? .zero
                        try add(&modelDay,PricedTokenUsage(tokens:value.tokens,estimatedCostUSD:value.estimatedCostUSD,usesReferencePricing:value.usesReferencePricing))
                        modelDays[id,default:[:]][key]=modelDay
                        if let name=value.model { modelNames[id]=name }
                        guard modelDays.count<=256 else { throw UsageIndexError.resourceLimited }
                    }
                    let count = eventCount.addingReportingOverflow(value.events)
                    guard !count.overflow else { throw UsageIndexError.resourceLimited }
                    eventCount = count.partialValue
                }
                try add(&lifetime, priced)
                if key >= todayKey { try add(&today, priced) }
                if key >= sevenKey { try add(&seven, priced) }
                if key >= monthKey { try add(&month, priced) }
                if key >= trendKey && key <= todayKey { days[key] = priced }
                guard days.count <= 191 else { throw UsageIndexError.resourceLimited }
            }
        }
        let threadCount = Int(try scalar("SELECT count(*) FROM build_member WHERE build_id=?", [.text(manifest.buildID)]) ?? 0)
        guard manifest.missingSources == 0 || threadCount > 0 else { return nil }
        let counts = try rows("""
            SELECT sum(json_extract(d.payload,'$.parsedFileCount')),sum(json_extract(d.payload,'$.tokenEventCount'))
            FROM source_day d JOIN build_member m ON m.projection_id=d.projection_id
            WHERE m.build_id=? AND d.day_key='' AND d.dimension_key='summary'
            """, [.text(manifest.buildID)], limit: 1).first
        let parsedFileCount = Int(counts?[0].integer ?? 0)
        eventCount = Int(counts?[1].integer ?? Int64(eventCount))
        let date = Date(timeIntervalSince1970: Double(observed) / 1000)
        let trend = CodexUsageReader().archivedTrend(days: days, statistics: statistics, models:modelDays, names:modelNames)
        let detailed = DetailedUsage(today: today, sevenDay: seven, month: month, lifetime: lifetime,
                                     parsedFileCount: parsedFileCount, tokenEventCount: eventCount)
        let details = includeDetails ? try archiveDetails(manifest: manifest, statistics: statistics, runtime: runtime) : UsageArchiveDetails()
        let local = LocalUsage(lifetimeTokens: lifetime.tokens.totalTokens, todayTokens: today.tokens.totalTokens,
            sevenDayTokens: seven.tokens.totalTokens, threadCount: threadCount, lastUpdatedAt: date,
            dailyBuckets: [], recentThreads: [], detailedUsage: detailed, usageTrend: trend,
            inferencePerformance: details.inference, projectBoard: details.projects, toolUsages: details.tools, skillUsages: details.skills)
        return UsageArchivePresentation(local: local, observedAt: date, complete: row[2].text == "completeAtRevision",
                                        revision: manifest.publicationRevision, hasDetails: includeDetails, scope: runtime == "codex" ? .codex : .claudeCode)
    }
}

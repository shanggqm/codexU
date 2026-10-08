import CryptoKit
import Foundation

struct UsageDayContribution: Codable, Equatable {
    let model: String?
    let serviceTier: String?
    var tokens: TokenBreakdown
    var events: Int
    var estimatedCostUSD: Double = 0
    var usesReferencePricing: Bool = false
}

struct UsageProjectionCursor: Codable, Equatable {
    let projectionID: String
    let source: String
    let revision: Int64
    let model: String?
    let tokenPrefix: Int
    var runtime: String = "codex"
    var lastKey = ""
    var tokenIndex = 0
    var finished = false
}

/// Each step changes one bounded page and its cursor in a single transaction. Ready projections
/// are immutable; a replacement with no day rows still replaces the previous contribution.
extension UsageIndexStore {
    func ensureProjectionContext(root: String, statistics: StatisticsContext, now: Date) throws -> String {
        let identity = root + "\n" + statistics.resolvedIdentifier + "\n2\n1"
        let id = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        try execute("""
            INSERT OR IGNORE INTO projection_context(id,root_id,timezone_id,formula_version,price_version,created_at_ms)
            VALUES (?,?,?,2,1,?)
            """, [.text(id), .text(root), .text(statistics.resolvedIdentifier), .integer(try usageIndexMilliseconds(now))])
        return id
    }

    func beginUsageProjection(context: String, source: String, revision: Int64, now: Date) throws -> UsageProjectionCursor? {
        guard let roots = try rows("SELECT s.root_id,c.root_id,s.runtime FROM source s CROSS JOIN projection_context c WHERE s.id=? AND c.id=?",
                                  [.text(source), .text(context)], limit: 1).first, roots[0] == roots[1] else { throw UsageIndexError.cacheInvalid }
        let runtime = roots[2].text ?? "codex"
        guard let metadata = try metadata(source: source, revision: revision),
              let generation = try scalar("""
                SELECT generation FROM source_generation WHERE source_id=? AND valid_from<=?
                AND (valid_to IS NULL OR valid_to>?)
                """, [.text(source), .integer(revision), .integer(revision)]),
              let checkpointRevision = try scalar("SELECT max(revision_id) FROM checkpoint_version WHERE source_id=? AND generation=? AND revision_id<=?",
                  [.text(source), .integer(generation), .integer(revision)]) else { return nil }
        var prefix = 0
        var dependencyRevision: Int64?
        if metadata.value.parentLogicalID != nil {
            // The caller pins and serializes this cut while staging projections. Never infer zero
            // for a fork whose parent or any ancestor is still pending.
            guard try dependencyIsValidAt(source: source, revision: revision),
                  let dependency = try rows("""
                    SELECT valid_from,token_prefix FROM dependency_version WHERE child_source_id=? AND child_generation=?
                    AND valid_from<=? AND (valid_to IS NULL OR valid_to>?) AND status='resolved'
                    """, [.text(source), .integer(generation), .integer(revision), .integer(revision)], limit: 1).first,
                  let version = dependency[0].integer, let count = dependency[1].integer else { return nil }
            dependencyRevision = version; prefix = Int(count)
        }
        let ownershipRevision = runtime == "claude-code" ? try claudeOwnershipRevision(source: source, at: revision) : 0
        let inputRevision = max(checkpointRevision, metadata.revision, dependencyRevision ?? 0, ownershipRevision)
        if let row = try rows("SELECT id,state FROM source_projection WHERE context_id=? AND source_id=? AND generation=? AND input_revision=?",
                             [.text(context), .text(source), .integer(generation), .integer(inputRevision)], limit: 1).first,
           let id = row[0].text {
            if row[1].text == "ready" { return UsageProjectionCursor(projectionID: id, source: source, revision: revision,
                model: metadata.value.model, tokenPrefix: prefix, runtime: runtime, finished: true) }
            if let encoded = try rows("SELECT cursor FROM job WHERE dedup_key=?", [.text("projection:" + id)], limit: 1).first?.first?.text {
                return try JSONDecoder().decode(UsageProjectionCursor.self, from: Data(encoded.utf8))
            }
            throw UsageIndexError.cacheInvalid
        }
        let id = UUID().uuidString
        let cursor = UsageProjectionCursor(projectionID: id, source: source, revision: revision,
                                           model: metadata.value.model, tokenPrefix: prefix, runtime: runtime)
        let encoded = String(decoding: try JSONEncoder().encode(cursor), as: UTF8.self)
        try transaction {
            try execute("""
                INSERT INTO source_projection(id,context_id,source_id,generation,input_revision,dependency_revision,state,created_at_ms,updated_at_ms)
                VALUES (?,?,?,?,?,?,'building',?,?)
                """, [.text(id), .text(context), .text(source), .integer(generation), .integer(inputRevision),
                      dependencyRevision.map(UsageSQLValue.integer) ?? .null, .integer(try usageIndexMilliseconds(now)), .integer(try usageIndexMilliseconds(now))])
            try execute("""
                INSERT INTO job(id,dedup_key,kind,priority,source_id,context_id,status,cursor,cut_revision,created_at_ms,updated_at_ms)
                VALUES (?,?,'projection',2,?,?,'queued',?,?,?,?)
                """, [.text(UUID().uuidString), .text("projection:" + id), .text(source), .text(context), .text(encoded),
                      .integer(revision), .integer(try usageIndexMilliseconds(now)), .integer(try usageIndexMilliseconds(now))])
            try execute("INSERT INTO revision_pin(owner_id,revision_id,updated_at_ms) VALUES (?,?,?)",
                        [.text("projection:" + id), .integer(revision), .integer(try usageIndexMilliseconds(now))])
        }
        return cursor
    }

    func stepUsageProjection(_ cursor: UsageProjectionCursor, statistics: StatisticsContext, now: Date) throws -> UsageProjectionCursor {
        if cursor.finished { return cursor }
        return try transaction {
            let key = "projection:" + cursor.projectionID
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let stored = try rows("SELECT cursor,status FROM job WHERE dedup_key=?", [.text(key)], limit: 1).first,
                  stored[1].text == "queued", let payload = stored[0].text else { throw UsageIndexError.sourceChanged }
            let persisted = try JSONDecoder().decode(UsageProjectionCursor.self, from: Data(payload.utf8))
            guard persisted == cursor else { throw UsageIndexError.sourceChanged }
            guard try rows("SELECT c.timezone_id FROM source_projection p JOIN projection_context c ON c.id=p.context_id WHERE p.id=?",
                           [.text(cursor.projectionID)], limit: 1).first?.first?.text == statistics.resolvedIdentifier else {
                throw UsageIndexError.sourceChanged
            }
            var next = cursor
            let page = try factsAt(source: cursor.source, kind: cursor.runtime == "codex" ? "token" : "claudeToken", revision: cursor.revision, afterKey: cursor.lastKey)
            for row in page {
                guard let logicalKey = row[0].text, let payload = row[3].text else { throw UsageIndexError.cacheInvalid }
                next.lastKey = logicalKey
                if row[1].text == "delete" { continue }
                let decoded = try JSONDecoder().decode(UsageFactPayload.self, from: Data(payload.utf8))
                let tokens: TokenBreakdown
                let date: Date
                let model: String?
                let tier: String?
                let project: String
                switch decoded {
                case .token(let delta):
                    tokens = delta.tokens; date = delta.date
                    project = try metadata(source: cursor.source, revision: cursor.revision)?.value.project ?? ""
                    model = resolvedModelUsageName(turnContextModel: delta.model, threadModel: next.model); tier = delta.serviceTier
                case .claudeToken(let delta):
                    if delta.messageId != nil, try !claudeOwnsMessage(source: cursor.source, key: logicalKey, revision: cursor.revision) { continue }
                    tokens = delta.tokens; date = delta.date; model = delta.model; tier = nil
                    project = delta.projectPath.isEmpty ? "Claude Code" : delta.projectPath
                default: throw UsageIndexError.cacheInvalid
                }
                next.tokenIndex += 1
                if next.tokenIndex <= next.tokenPrefix { continue }
                let dimensionData = try encoder.encode([model, tier])
                let dimension = SHA256.hash(data: dimensionData).map { String(format: "%02x", $0) }.joined()
                let day = statistics.dayKey(for: date)
                var contribution = UsageDayContribution(model: model, serviceTier: tier, tokens: .zero, events: 0)
                if let previous = try rows("SELECT payload FROM source_day WHERE projection_id=? AND day_key=? AND dimension_key=?",
                                           [.text(cursor.projectionID), .text(day), .text(dimension)], limit: 1).first?.first?.text {
                    contribution = try JSONDecoder().decode(UsageDayContribution.self, from: Data(previous.utf8))
                }
                let priced = cursor.runtime == "claude-code" ? priceArchivedClaude(tokens: tokens, model: model)
                    : priceArchivedContribution(UsageDayContribution(model: model, serviceTier: tier, tokens: tokens, events: 1))
                try accumulateProject(projection: cursor.projectionID, path: project, date: date, priced: priced, statistics: statistics)
                contribution.tokens = try checkedTokenSum(contribution.tokens, tokens)
                contribution.estimatedCostUSD += priced.estimatedCostUSD
                contribution.usesReferencePricing = contribution.usesReferencePricing || priced.usesReferencePricing
                guard contribution.estimatedCostUSD.isFinite else { throw UsageIndexError.resourceLimited }
                contribution.events += 1
                let data = try encoder.encode(contribution)
                guard data.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
                try execute("""
                    INSERT INTO source_day(projection_id,day_key,dimension_key,payload) VALUES (?,?,?,?)
                    ON CONFLICT(projection_id,day_key,dimension_key) DO UPDATE SET payload=excluded.payload
                    """, [.text(cursor.projectionID), .text(day), .text(dimension), .text(String(decoding: data, as: UTF8.self))])
            }
            next.finished = page.isEmpty
            let encoded = String(decoding: try encoder.encode(next), as: UTF8.self)
            try execute("UPDATE job SET cursor=?,status=?,updated_at_ms=? WHERE dedup_key=?", [.text(encoded),
                .text(next.finished ? "done" : "queued"), .integer(try usageIndexMilliseconds(now)), .text(key)])
            if next.finished {
                let counter = try factsAt(source: cursor.source, kind: "counters", revision: cursor.revision).first
                var rawCount = cursor.tokenIndex
                var parsed = rawCount > 0
                if let payload = counter?[3].text,
                   case .counters(let count, let hasToken) = try JSONDecoder().decode(UsageFactPayload.self, from: Data(payload.utf8)) {
                    rawCount = count; parsed = hasToken
                }
                let summary = UsageProjectionSummary(parsedFileCount: parsed ? 1 : 0,
                    tokenEventCount: max(rawCount - cursor.tokenPrefix, 0))
                let payload = String(decoding: try encoder.encode(summary), as: UTF8.self)
                try execute("INSERT OR REPLACE INTO source_day(projection_id,day_key,dimension_key,payload) VALUES (?,'','summary',?)",
                            [.text(cursor.projectionID), .text(payload)])
                try execute("UPDATE source_projection SET state='ready',updated_at_ms=? WHERE id=?", [.integer(try usageIndexMilliseconds(now)), .text(cursor.projectionID)])
                try execute("DELETE FROM revision_pin WHERE owner_id=?", [.text(key)])
            }
            return next
        }
    }
}

func checkedTokenSum(_ a: TokenBreakdown, _ b: TokenBreakdown) throws -> TokenBreakdown {
    func sum(_ x: Int64, _ y: Int64) throws -> Int64 {
        let value = x.addingReportingOverflow(y)
        guard !value.overflow, value.partialValue >= 0 else { throw UsageIndexError.resourceLimited }
        return value.partialValue
    }
    return try TokenBreakdown(inputTokens: sum(a.inputTokens, b.inputTokens), cachedInputTokens: sum(a.cachedInputTokens, b.cachedInputTokens),
        cacheWriteInputTokens: sum(a.cacheWriteInputTokens, b.cacheWriteInputTokens),
        outputTokens: sum(a.outputTokens, b.outputTokens), reasoningOutputTokens: sum(a.reasoningOutputTokens, b.reasoningOutputTokens),
        totalTokens: sum(a.totalTokens, b.totalTokens))
}

struct UsageProjectionSummary: Codable {
    let parsedFileCount: Int
    let tokenEventCount: Int
}

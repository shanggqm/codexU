import Foundation

struct UsageArchivedDay: Codable, Equatable {
    var dimensions: [String: UsageDayContribution] = [:]
}

struct UsageArchiveCursor: Codable {
    var publicationRevision: Int64 = 0
    var stage = "members"
    var source = ""
    var day = ""
    var projection = ""
    var dimension = ""
    var accumulated = UsageArchivedDay()
    var missingSources = 0
}

extension UsageIndexStore {
    func beginDayArchive(context: String, root: String, dayKey: String, now: Date, runtime: String = "codex") throws -> String {
        let id = UUID().uuidString
        try transaction {
            let cut = try scalar("SELECT max(id) FROM revision") ?? allocateRevision(now: now)
            let timestamp = try usageIndexMilliseconds(now)
            let publication = try allocateRevision(now: now)
            let inventory = try rows("SELECT id,status,revision_id FROM discovery_scan WHERE root_id=? AND runtime=? ORDER BY id DESC LIMIT 1",
                                     [.text(root), .text(runtime)], limit: 1).first
            let scan = inventory?[0].integer
            let pendingOwnership = runtime == "claude-code" ? try scalar("SELECT count(*) FROM job j JOIN source s ON s.id=j.source_id WHERE s.root_id=? AND j.kind='claude-owner' AND j.status<>'done'", [.text(root)]) ?? 0 : 0
            let complete = inventory?[1].text == "complete" && (inventory?[2].integer ?? Int64.max) <= cut && pendingOwnership == 0
            let cursor = String(decoding: try JSONEncoder().encode(UsageArchiveCursor(publicationRevision: publication,
                missingSources: complete ? 0 : 1)), as: UTF8.self)
            try execute("""
                INSERT INTO report_build(id,context_id,cut_revision,day_key,domain,runtime,state,cursor,created_at_ms,updated_at_ms)
                VALUES (?,?,?,?,'usage',?,'building',?,?,?)
                """, [.text(id), .text(context), .integer(cut), .text(dayKey), .text(runtime), .text(cursor), .integer(timestamp), .integer(timestamp)])
            if complete, let scan { try execute("UPDATE report_build SET scan_id=? WHERE id=?", [.integer(scan), .text(id)]) }
            try execute("INSERT INTO revision_pin(owner_id,revision_id,updated_at_ms) VALUES (?,?,?)",
                        [.text("report:" + id), .integer(cut), .integer(timestamp)])
        }
        return id
    }

    /// Returns true only after all source memberships and day replacements have been persisted.
    /// Every call processes at most 100 sources or 100 contribution rows.
    func stepDayArchive(build: String, now: Date) throws -> Bool {
        try transaction {
            guard let row = try rows("""
                SELECT b.context_id,b.cut_revision,b.cursor,b.state,c.root_id,b.runtime FROM report_build b
                JOIN projection_context c ON c.id=b.context_id WHERE b.id=?
                """, [.text(build)], limit: 1).first,
                  let context = row[0].text, let cut = row[1].integer,
                  let serialized = row[2].text, let root = row[4].text, let runtime = row[5].text else { throw UsageIndexError.cacheInvalid }
            if row[3].text == "ready" || row[3].text == "partial" { return true }
            var cursor = try JSONDecoder().decode(UsageArchiveCursor.self, from: Data(serialized.utf8))
            if cursor.stage == "members" {
                let sources = try rows("SELECT id FROM source WHERE root_id=? AND runtime=? AND created_revision<=? AND id>? ORDER BY id LIMIT 100",
                    [.text(root), .text(runtime), .integer(cut), .text(cursor.source)], limit: 100)
                for sourceRow in sources {
                    guard let source = sourceRow[0].text else { throw UsageIndexError.cacheInvalid }
                    cursor.source = source
                    // Match the latest checkpoint and metadata at this fixed cut. A previous complete
                    // projection must not hide an unprojected append or an empty replacement generation.
                    let candidates = try rows("""
                        SELECT p.id,p.input_revision FROM source_projection p JOIN source_generation g
                          ON g.source_id=p.source_id AND g.generation=p.generation
                        WHERE p.context_id=? AND p.source_id=? AND p.state='ready' AND p.input_revision<=?
                          AND g.valid_from<=? AND (g.valid_to IS NULL OR g.valid_to>?)
                          AND p.input_revision>=(SELECT max(revision_id) FROM checkpoint_version
                            WHERE source_id=p.source_id AND generation=p.generation AND revision_id<=?)
                          AND p.input_revision>=(SELECT max(valid_from) FROM source_metadata_version WHERE source_id=p.source_id AND valid_from<=?)
                          AND COALESCE(p.dependency_revision,0)=COALESCE((SELECT max(d.valid_from) FROM dependency_version d
                            WHERE d.child_source_id=p.source_id AND d.child_generation=p.generation AND d.valid_from<=?
                            AND (d.valid_to IS NULL OR d.valid_to>?)),0)
                        ORDER BY p.input_revision DESC LIMIT 1
                        """, [.text(context), .text(source), .integer(cut), .integer(cut), .integer(cut), .integer(cut), .integer(cut), .integer(cut), .integer(cut)], limit: 1)
                    let ownerRevision = runtime == "claude-code" ? try claudeOwnershipRevision(source: source, at: cut) : 0
                    if let projection = candidates.first?.first?.text, (candidates.first?[1].integer ?? 0) >= ownerRevision,
                       try dependencyIsValidAt(source: source, revision: cut),
                       try observationIsCovered(source: source, revision: cut) {
                        try execute("INSERT INTO build_member(build_id,source_id,projection_id) VALUES (?,?,?)",
                            [.text(build), .text(source), .text(projection)])
                    } else { cursor.missingSources += 1 }
                }
                if sources.isEmpty { cursor.stage = "days" }
            } else {
                if cursor.projection.isEmpty && cursor.dimension.isEmpty && cursor.accumulated.dimensions.isEmpty {
                    // Include previous days so a rewrite that removes every event emits an empty
                    // replacement instead of resurrecting the old archive.
                    let next = try rows("""
                        SELECT day_key FROM (
                          SELECT d.day_key FROM source_day d JOIN build_member m ON m.projection_id=d.projection_id WHERE m.build_id=? AND d.day_key<>''
                          UNION SELECT a.day_key FROM archive_day a
                          WHERE a.context_id=? AND a.revision_id<=? AND a.revision_id IN
                            (SELECT revision_id FROM published_slice WHERE context_id=a.context_id AND domain='archive' AND runtime=?)
                        ) WHERE day_key>? ORDER BY day_key LIMIT 1
                        """, [.text(build), .text(context), .integer(cut), .text(runtime), .text(cursor.day)], limit: 1)
                    guard let day = next.first?.first?.text else {
                        let state = cursor.missingSources == 0 ? "ready" : "partial"
                        try execute("UPDATE report_build SET state=?,updated_at_ms=? WHERE id=?",
                            [.text(state), .integer(try usageIndexMilliseconds(now)), .text(build)])
                        let coverage = cursor.missingSources == 0 ? "completeAtRevision" : "partial"
                        let payload = String(decoding: try JSONEncoder().encode(UsageArchiveManifest(buildID: build,
                            publicationRevision: cursor.publicationRevision, inputRevision: cut,
                            missingSources: cursor.missingSources)), as: UTF8.self)
                        try execute("""
                            INSERT INTO published_slice(build_id,day_key,context_id,domain,runtime,revision_id,coverage,observed_at_ms,payload,updated_at_ms)
                            SELECT b.id,b.day_key,b.context_id,'archive',b.runtime,?,?,r.committed_at_ms,?,? FROM report_build b
                            JOIN revision r ON r.id=b.cut_revision WHERE b.id=?
                            ON CONFLICT(context_id,domain,runtime) DO UPDATE SET build_id=excluded.build_id,day_key=excluded.day_key,
                              revision_id=excluded.revision_id,coverage=excluded.coverage,observed_at_ms=excluded.observed_at_ms,
                              payload=excluded.payload,updated_at_ms=excluded.updated_at_ms
                            WHERE excluded.revision_id>published_slice.revision_id
                              AND (published_slice.coverage<>'completeAtRevision' OR excluded.coverage='completeAtRevision')
                            """, [.integer(cursor.publicationRevision), .text(coverage), .text(payload),
                                  .integer(try usageIndexMilliseconds(now)), .text(build)])
                        try execute("DELETE FROM revision_pin WHERE owner_id=?", [.text("report:" + build)])
                        return true
                    }
                    cursor.day = day
                }
                let page = try rows("""
                    SELECT d.projection_id,d.dimension_key,d.payload FROM source_day d
                    JOIN build_member m ON m.projection_id=d.projection_id
                    WHERE m.build_id=? AND d.day_key=? AND (d.projection_id>? OR (d.projection_id=? AND d.dimension_key>?))
                    ORDER BY d.projection_id,d.dimension_key LIMIT 100
                    """, [.text(build), .text(cursor.day), .text(cursor.projection), .text(cursor.projection), .text(cursor.dimension)], limit: 100)
                for contributionRow in page {
                    guard let projection = contributionRow[0].text, let dimension = contributionRow[1].text,
                          let payload = contributionRow[2].text else { throw UsageIndexError.cacheInvalid }
                    let value = try JSONDecoder().decode(UsageDayContribution.self, from: Data(payload.utf8))
                    var combined = cursor.accumulated.dimensions[dimension] ?? UsageDayContribution(
                        model: value.model, serviceTier: value.serviceTier, tokens: .zero, events: 0)
                    combined.tokens = try checkedTokenSum(combined.tokens, value.tokens)
                    combined.estimatedCostUSD += value.estimatedCostUSD
                    combined.usesReferencePricing = combined.usesReferencePricing || value.usesReferencePricing
                    guard combined.estimatedCostUSD.isFinite else { throw UsageIndexError.resourceLimited }
                    let count = combined.events.addingReportingOverflow(value.events)
                    guard !count.overflow else { throw UsageIndexError.resourceLimited }
                    combined.events = count.partialValue
                    cursor.accumulated.dimensions[dimension] = combined
                    guard cursor.accumulated.dimensions.count <= 256 else { throw UsageIndexError.resourceLimited }
                    cursor.projection = projection; cursor.dimension = dimension
                }
                if page.isEmpty {
                    let payload = try JSONEncoder().encode(cursor.accumulated)
                    guard payload.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
                    try execute("""
                        INSERT INTO archive_day(context_id,day_key,revision_id,coverage,payload,updated_at_ms) VALUES (?,?,?,?,?,?)
                        ON CONFLICT(context_id,day_key,revision_id) DO UPDATE SET coverage=excluded.coverage,payload=excluded.payload,updated_at_ms=excluded.updated_at_ms
                        """, [.text(context), .text(cursor.day), .integer(cursor.publicationRevision), .text(cursor.missingSources == 0 ? "completeAtRevision" : "partial"),
                              .text(String(decoding: payload, as: UTF8.self)), .integer(try usageIndexMilliseconds(now))])
                    cursor.projection = ""; cursor.dimension = ""; cursor.accumulated = UsageArchivedDay()
                }
            }
            let data = try JSONEncoder().encode(cursor)
            guard data.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
            try execute("UPDATE report_build SET cursor=?,updated_at_ms=? WHERE id=?",
                        [.text(String(decoding: data, as: UTF8.self)), .integer(try usageIndexMilliseconds(now)), .text(build)])
            return false
        }
    }
}

struct UsageArchiveManifest: Codable {
    let buildID: String
    let publicationRevision: Int64
    let inputRevision: Int64
    let missingSources: Int
}

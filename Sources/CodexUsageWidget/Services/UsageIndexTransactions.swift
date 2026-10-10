import Foundation

enum UsageFactPayload: Codable {
    case token(SessionUsageDelta)
    case claudeToken(ClaudeUsageDelta)
    case claudeSkill(ClaudeSkillLoad)
    case turnStart(Date)
    case counters(rawTokenEvents: Int, hasTokenEvents: Bool)
    case inference(ModelInferenceSample)
    case tool(name: String, count: Int)
    case skill(SkillLoadEvent)
    case interval(LeadershipInterval)

    var isBounded: Bool {
        switch self {
        case .claudeToken(let value):
            return (value.model?.utf8.count ?? 0) <= 256 && (value.messageId?.utf8.count ?? 0) <= 1024
                && value.projectPath.utf8.count <= 16384 && value.sessionId.utf8.count <= 1024
        case .claudeSkill(let value): return value.name.utf8.count <= 256 && (value.path?.utf8.count ?? 0) <= 16384
        case .turnStart(let date): return date.timeIntervalSince1970.isFinite
        case .counters(let count, _): return count >= 0
        case .token(let value):
            return (value.model?.utf8.count ?? 0) <= 256 && (value.serviceTier?.utf8.count ?? 0) <= 64
        case .inference(let value):
            return value.model.utf8.count <= 256 && value.effort.utf8.count <= 256
        case .tool(let name, let count): return name.utf8.count <= 256 && count >= 0
        case .skill(let value): return value.path.utf8.count <= 16384
        case .interval(let value):
            return value.id.utf8.count <= 1024 && value.workerID.utf8.count <= 1024 && value.projectID.utf8.count <= 16384
        }
    }

    var kind: String {
        switch self {
        case .claudeToken: return "claudeToken"
        case .claudeSkill: return "claudeSkill"
        case .turnStart: return "turnStart"
        case .counters: return "counters"
        case .token: return "token"
        case .inference: return "inference"
        case .tool: return "tool"
        case .skill: return "skill"
        case .interval: return "interval"
        }
    }
}

struct UsageIndexFact {
    let logicalKey: String
    let occurredAt: Date
    let payload: UsageFactPayload
    var deleted = false
}

struct UsageIndexCheckpoint {
    let generation: Int64
    let revision: Int64
    let offset: Int64
    let targetEnd: Int64
    let state: String
    let identity: String
}

extension UsageIndexStore {
    @discardableResult
    func registerSource(id: String, root: String, runtime: String, logicalID: String,
                        locator: String, now: Date) throws -> Int64 {
        guard ["codex", "claude-code"].contains(runtime), id.utf8.count <= 1024,
              locator.utf8.count <= 16384 else { throw UsageIndexError.resourceLimited }
        return try transaction {
            if let revision = try scalar("SELECT created_revision FROM source WHERE id=?", [.text(id)]) { return revision }
            let revision = try allocateRevision(now: now)
            try execute("""
                INSERT INTO source(id,root_id,runtime,logical_id,instance_id,locator,discovered_epoch,created_revision,status,updated_at_ms)
                VALUES (?,?,?,?,?,?,0,?,'pending',?)
                """, [.text(id), .text(root), .text(runtime), .text(logicalID), .text(id), .text(locator),
                      .integer(revision), .integer(try usageIndexMilliseconds(now))])
            return revision
        }
    }

    func beginGeneration(source: String, identity: String, targetEnd: Int64,
                         initialState: String, now: Date) throws -> UsageIndexCheckpoint {
        guard targetEnd >= 0, initialState.utf8.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
        return try transaction {
            let generation = (try scalar("SELECT max(generation) FROM source_generation WHERE source_id=?", [.text(source)]) ?? 0) + 1
            let revision = try allocateRevision(now: now)
            // All new generations stage first, including the first one. No partial source is published as complete.
            try execute("""
                INSERT INTO source_generation(source_id,generation,parser_version,file_identity,checkpoint_offset,
                  observed_end,checkpoint_state,fingerprint,created_at_ms,updated_at_ms)
                VALUES (?,?,3,?,0,?,?,'',?,?)
                """, [.text(source), .integer(generation), .text(identity), .integer(targetEnd), .text(initialState),
                      .integer(try usageIndexMilliseconds(now)), .integer(try usageIndexMilliseconds(now))])
            try execute("INSERT INTO checkpoint_version VALUES (?,?,?,0,?)",
                        [.text(source), .integer(generation), .integer(revision), .integer(targetEnd)])
            return UsageIndexCheckpoint(generation: generation, revision: revision, offset: 0,
                                        targetEnd: targetEnd, state: initialState, identity: identity)
        }
    }

    func checkpoint(source: String) throws -> UsageIndexCheckpoint? {
        let records = try rows("""
            SELECT generation,checkpoint_offset,observed_end,checkpoint_state,file_identity,
              (SELECT max(revision_id) FROM checkpoint_version c WHERE c.source_id=g.source_id AND c.generation=g.generation)
            FROM source_generation g WHERE source_id=? AND valid_to IS NULL ORDER BY generation DESC LIMIT 1
            """, [.text(source)], limit: 1)
        guard let row = records.first else { return nil }
        guard let generation = row[0].integer, let offset = row[1].integer, let end = row[2].integer,
              let state = row[3].text, let identity = row[4].text, let revision = row[5].integer,
              generation > 0, revision > 0, offset >= 0, end >= offset,
              state.utf8.count <= Self.maximumPayloadBytes else { throw UsageIndexError.cacheInvalid }
        return UsageIndexCheckpoint(generation: generation, revision: revision, offset: offset,
                                    targetEnd: end, state: state, identity: identity)
    }

    func completeOffset(source: String, checkpoint: UsageIndexCheckpoint) throws -> Int64 {
        guard let offset=try scalar("SELECT complete_offset FROM checkpoint_version WHERE source_id=? AND generation=? AND revision_id=?",
            [.text(source),.integer(checkpoint.generation),.integer(checkpoint.revision)]) else { throw UsageIndexError.cacheInvalid }
        return offset
    }

    /// Extend a frozen target only to the first verified newline that finishes its pending line.
    /// The isolated reader supplies this boundary; this transaction performs no source-file I/O.
    func finishFrozenTail(source: String, expected: UsageIndexCheckpoint, boundary: Int64,
                          verifiedIdentity: String, now: Date) throws -> UsageIndexCheckpoint {
        guard expected.offset <= expected.targetEnd, boundary > expected.targetEnd,
              try completeOffset(source: source, checkpoint: expected) < expected.targetEnd,
              boundary - expected.targetEnd <= Int64(UsageStreamParser.maximumLineBytes + UsageStreamParser.chunkBytes),
              verifiedIdentity == expected.identity else { throw UsageIndexError.sourceChanged }
        return try transaction {
            guard try scalar("SELECT max(revision_id) FROM checkpoint_version WHERE source_id=? AND generation=?",
                             [.text(source), .integer(expected.generation)]) == expected.revision,
                  try scalar("SELECT max(generation) FROM source_generation WHERE source_id=?", [.text(source)]) == expected.generation else {
                throw UsageIndexError.sourceChanged
            }
            try execute("""
                UPDATE source_generation SET observed_end=?,updated_at_ms=?
                WHERE source_id=? AND generation=? AND checkpoint_offset=? AND observed_end=? AND file_identity=?
                  AND valid_from IS NULL AND valid_to IS NULL
                """, [.integer(boundary), .integer(try usageIndexMilliseconds(now)), .text(source), .integer(expected.generation),
                      .integer(expected.offset), .integer(expected.targetEnd), .text(verifiedIdentity)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            let revision = try allocateRevision(now: now)
            try execute("INSERT INTO checkpoint_version VALUES (?,?,?,?,?)", [.text(source), .integer(expected.generation),
                .integer(revision), .integer(try completeOffset(source: source, checkpoint: expected)), .integer(boundary)])
            return UsageIndexCheckpoint(generation: expected.generation, revision: revision, offset: expected.offset,
                                        targetEnd: boundary, state: expected.state, identity: verifiedIdentity)
        }
    }

    /// Active sources can observe an appended tail without rebuilding their committed generation.
    /// Staging targets remain frozen; a helper must resolve an incomplete initial tail before activation.
    func observeAppend(source: String, expected: UsageIndexCheckpoint, targetEnd: Int64,
                       verifiedIdentity: String, now: Date) throws -> UsageIndexCheckpoint {
        guard targetEnd >= expected.targetEnd, verifiedIdentity == expected.identity else {
            throw UsageIndexError.sourceChanged
        }
        return try transaction {
            guard try scalar("SELECT max(revision_id) FROM checkpoint_version WHERE source_id=? AND generation=?",
                             [.text(source), .integer(expected.generation)]) == expected.revision else {
                throw UsageIndexError.sourceChanged
            }
            try execute("""
                UPDATE source_generation SET observed_end=?,updated_at_ms=?
                WHERE source_id=? AND generation=? AND checkpoint_offset=? AND observed_end=? AND file_identity=?
                  AND valid_from IS NOT NULL AND valid_to IS NULL
                """, [.integer(targetEnd), .integer(try usageIndexMilliseconds(now)), .text(source), .integer(expected.generation),
                      .integer(expected.offset), .integer(expected.targetEnd), .text(verifiedIdentity)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            let revision = try allocateRevision(now: now)
            try execute("""
                INSERT INTO source_observation(source_id,revision_id,file_identity,target_end,status,observed_at_ms)
                VALUES (?,?,?,?,'readable',?)
                """, [.text(source), .integer(revision), .text(verifiedIdentity), .integer(targetEnd),
                      .integer(try usageIndexMilliseconds(now))])
            try execute("INSERT INTO checkpoint_version VALUES (?,?,?,?,?)",
                        [.text(source), .integer(expected.generation), .integer(revision), .integer(try completeOffset(source: source, checkpoint: expected)), .integer(targetEnd)])
            return UsageIndexCheckpoint(generation: expected.generation, revision: revision, offset: expected.offset,
                                        targetEnd: targetEnd, state: expected.state, identity: verifiedIdentity)
        }
    }

    /// One CAS protects the facts and parser state, including retries where the offset did not advance.
    @discardableResult
    func append(source: String, expected: UsageIndexCheckpoint, offset: Int64, state: String,
                facts: [UsageIndexFact], now: Date, completeOffset completed: Int64? = nil) throws -> UsageIndexCheckpoint {
        guard facts.count <= 1000, state.utf8.count <= Self.maximumPayloadBytes,
              offset >= expected.offset, offset <= expected.targetEnd else { throw UsageIndexError.resourceLimited }
        let complete = completed ?? offset
        guard complete>=0,complete<=offset,try complete>=completeOffset(source:source,checkpoint:expected) else { throw UsageIndexError.sourceChanged }
        let encoder = JSONEncoder()
        var totalPayloadBytes = 0
        let payloads = try facts.map { fact -> String in
            guard fact.payload.isBounded, !fact.logicalKey.isEmpty, fact.logicalKey.utf8.count <= 1024, fact.occurredAt.timeIntervalSince1970.isFinite else {
                throw UsageIndexError.resourceLimited
            }
            _ = try usageIndexMilliseconds(fact.occurredAt)
            let data = try encoder.encode(fact.payload)
            totalPayloadBytes += data.count
            guard totalPayloadBytes <= 4 * 1024 * 1024, data.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
            return String(decoding: data, as: UTF8.self)
        }
        guard payloads.reduce(0, { $0 + $1.utf8.count }) <= 4 * 1024 * 1024 else { throw UsageIndexError.resourceLimited }
        return try transaction {
            let current = try scalar("SELECT max(revision_id) FROM checkpoint_version WHERE source_id=? AND generation=?",
                                     [.text(source), .integer(expected.generation)])
            guard current == expected.revision else { throw UsageIndexError.sourceChanged }
            try execute("""
                UPDATE source_generation SET checkpoint_offset=?,checkpoint_state=?,updated_at_ms=?
                WHERE source_id=? AND generation=? AND checkpoint_offset=? AND file_identity=? AND observed_end=? AND valid_to IS NULL
                """, [.integer(offset), .text(state), .integer(try usageIndexMilliseconds(now)), .text(source), .integer(expected.generation),
                      .integer(expected.offset), .text(expected.identity), .integer(expected.targetEnd)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            let revision = try allocateRevision(now: now)
            var sequence = try scalar("SELECT max(sequence) FROM fact WHERE source_id=? AND generation=?",
                                      [.text(source), .integer(expected.generation)]) ?? 0
            for (index, fact) in facts.enumerated() {
                sequence += 1
                try execute("""
                    INSERT INTO fact(source_id,generation,sequence,kind,logical_key,operation,occurred_at_ms,payload,commit_revision)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    """, [.text(source), .integer(expected.generation), .integer(sequence), .text(fact.payload.kind),
                          .text(fact.logicalKey), .text(fact.deleted ? "delete" : "upsert"), .integer(try usageIndexMilliseconds(fact.occurredAt)),
                          .text(payloads[index]), .integer(revision)])
            }
            try execute("INSERT INTO checkpoint_version VALUES (?,?,?,?,?)",
                        [.text(source), .integer(expected.generation), .integer(revision), .integer(complete), .integer(expected.targetEnd)])
            return UsageIndexCheckpoint(generation: expected.generation, revision: revision, offset: offset,
                                        targetEnd: expected.targetEnd, state: state, identity: expected.identity)
        }
    }

    /// The helper must verify the file identity/target boundary before asking to switch.
    @discardableResult
    func activate(source: String, expected: UsageIndexCheckpoint, verifiedIdentity: String, now: Date) throws -> Int64 {
        guard expected.offset == expected.targetEnd, try completeOffset(source:source,checkpoint:expected) == expected.targetEnd, verifiedIdentity == expected.identity else { throw UsageIndexError.sourceChanged }
        return try transaction {
            guard try scalar("SELECT max(generation) FROM source_generation WHERE source_id=?", [.text(source)]) == expected.generation else {
                throw UsageIndexError.sourceChanged
            }
            guard try scalar("SELECT max(revision_id) FROM checkpoint_version WHERE source_id=? AND generation=?",
                             [.text(source), .integer(expected.generation)]) == expected.revision else { throw UsageIndexError.sourceChanged }
            let revision = try allocateRevision(now: now)
            try execute("UPDATE source_generation SET valid_to=? WHERE source_id=? AND valid_from IS NOT NULL AND valid_to IS NULL",
                        [.integer(revision), .text(source)])
            try execute("""
                UPDATE source_generation SET valid_from=?,updated_at_ms=?
                WHERE source_id=? AND generation=? AND valid_from IS NULL AND valid_to IS NULL AND checkpoint_offset=observed_end AND file_identity=?
                """, [.integer(revision), .integer(try usageIndexMilliseconds(now)), .text(source), .integer(expected.generation), .text(verifiedIdentity)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            return revision
        }
    }

    /// Latest revision is chosen before deletion/time filtering, so an old interval cannot resurrect.
    /// Returned rows include tombstones; consumers advance the cursor even when a row is deleted.
    func factsAt(source: String, kind: String, revision: Int64, afterKey: String = "", limit: Int = 100) throws -> [[UsageSQLValue]] {
        guard (1...100).contains(limit) else { throw UsageIndexError.resourceLimited }
        let pageLimit = min(limit, 12) // 12 maximal payloads plus metadata fit the 4 MiB response budget.
        return try rows("""
            SELECT f.logical_key,f.operation,f.occurred_at_ms,f.payload,f.commit_revision,f.sequence
            FROM fact f JOIN source_generation g ON g.source_id=f.source_id AND g.generation=f.generation
            WHERE f.source_id=? AND f.kind=? AND f.logical_key>? AND f.commit_revision<=?
              AND g.valid_from<=? AND (g.valid_to IS NULL OR g.valid_to>?)
              AND NOT EXISTS (SELECT 1 FROM fact newer
                WHERE newer.source_id=f.source_id AND newer.generation=f.generation AND newer.kind=f.kind
                  AND newer.logical_key=f.logical_key AND newer.commit_revision<=?
                  AND (newer.commit_revision>f.commit_revision OR
                    (newer.commit_revision=f.commit_revision AND newer.sequence>f.sequence)))
            ORDER BY f.logical_key LIMIT ?
            """, [.text(source), .text(kind), .text(afterKey), .integer(revision), .integer(revision), .integer(revision),
                  .integer(revision), .integer(Int64(pageLimit))], limit: pageLimit)
    }

}

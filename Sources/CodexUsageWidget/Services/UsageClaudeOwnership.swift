import Foundation

extension UsageIndexStore {
    static let ownershipSchema = [
        """
        CREATE TABLE claude_message_owner (
          root_id TEXT NOT NULL,message_key TEXT NOT NULL,source_id TEXT,generation INTEGER,
          valid_from INTEGER NOT NULL REFERENCES revision(id),valid_to INTEGER REFERENCES revision(id),
          PRIMARY KEY(root_id,message_key,valid_from),
          FOREIGN KEY(source_id,generation) REFERENCES source_generation(source_id,generation),
          CHECK(valid_to IS NULL OR valid_to>valid_from)
        )
        """,
        "CREATE UNIQUE INDEX claude_owner_current ON claude_message_owner(root_id,message_key) WHERE valid_to IS NULL",
        "CREATE INDEX claude_owner_source ON claude_message_owner(source_id,valid_from,valid_to)",
        "CREATE INDEX fact_message_lookup ON fact(kind,logical_key,source_id,generation,commit_revision)"
    ]

    func enqueueClaudeOwnership(source: String, now: Date) throws {
        try execute("""
            INSERT INTO job(id,dedup_key,kind,priority,source_id,status,cursor,created_at_ms,updated_at_ms)
            VALUES (?,?,'claude-owner',1,?,'queued','',?,?) ON CONFLICT(dedup_key) DO UPDATE SET
              status='queued',cursor='',updated_at_ms=excluded.updated_at_ms
            """, [.text(UUID().uuidString), .text("claude-owner:" + source), .text(source),
                  .integer(try usageIndexMilliseconds(now)), .integer(try usageIndexMilliseconds(now))])
    }

    func stepClaudeOwnership(now: Date, changed: (String) throws -> Void) throws -> Bool {
        guard let job = try rows("""
            SELECT j.id,j.source_id,j.cursor,s.root_id FROM job j JOIN source s ON s.id=j.source_id
            WHERE j.kind='claude-owner' AND j.status='queued' ORDER BY j.updated_at_ms,j.id LIMIT 1
            """, limit: 1).first, let id = job[0].text, let source = job[1].text,
            let after = job[2].text, let root = job[3].text else { return false }
        let keys = try rows("""
            SELECT DISTINCT logical_key FROM fact WHERE source_id=? AND kind='claudeToken'
            AND logical_key LIKE 'message:%' AND logical_key>? ORDER BY logical_key LIMIT 50
            """, [.text(source), .text(after)], limit: 50)
        for row in keys {
            guard let key = row[0].text else { throw UsageIndexError.cacheInvalid }
            try transaction {
                for affected in try reconcileClaudeOwner(root: root, key: key, now: now) { try changed(affected) }
            }
        }
        try execute("UPDATE job SET cursor=?,status=?,updated_at_ms=? WHERE id=?",
                    [.text(keys.last?.first?.text ?? after), .text(keys.isEmpty ? "done" : "queued"),
                     .integer(try usageIndexMilliseconds(now)), .text(id)])
        return true
    }

    private func reconcileClaudeOwner(root: String, key: String, now: Date) throws -> [String] {
        try transaction {
            let winner = try rows("""
                SELECT f.source_id,f.generation FROM fact f JOIN source s ON s.id=f.source_id
                JOIN source_generation g ON g.source_id=f.source_id AND g.generation=f.generation
                WHERE s.root_id=? AND s.runtime='claude-code' AND f.kind='claudeToken' AND f.logical_key=?
                  AND g.valid_from IS NOT NULL AND g.valid_to IS NULL AND f.operation='upsert'
                  AND NOT EXISTS (SELECT 1 FROM fact newer WHERE newer.source_id=f.source_id
                    AND newer.generation=f.generation AND newer.kind=f.kind AND newer.logical_key=f.logical_key
                    AND newer.sequence>f.sequence)
                ORDER BY s.locator,s.id,f.sequence LIMIT 1
                """, [.text(root), .text(key)], limit: 1).first
            let previous = try rows("SELECT source_id,generation FROM claude_message_owner WHERE root_id=? AND message_key=? AND valid_to IS NULL",
                                    [.text(root), .text(key)], limit: 1).first
            let source = winner?[0] ?? .null, generation = winner?[1] ?? .null
            if previous == [source, generation] { return [] }
            let revision = try allocateRevision(now: now)
            try execute("UPDATE claude_message_owner SET valid_to=? WHERE root_id=? AND message_key=? AND valid_to IS NULL",
                        [.integer(revision), .text(root), .text(key)])
            try execute("INSERT INTO claude_message_owner(root_id,message_key,source_id,generation,valid_from) VALUES (?,?,?,?,?)",
                        [.text(root), .text(key), source, generation, .integer(revision)])
            return Array(Set([previous?.first?.text, source.text].compactMap { $0 }))
        }
    }

    func claudeOwnsMessage(source: String, key: String, revision: Int64) throws -> Bool {
        try scalar("""
            SELECT 1 FROM claude_message_owner o JOIN source s ON s.root_id=o.root_id
            WHERE s.id=? AND o.message_key=? AND o.source_id=s.id AND o.valid_from<=? AND (o.valid_to IS NULL OR o.valid_to>?)
            AND EXISTS (SELECT 1 FROM source_generation g WHERE g.source_id=o.source_id AND g.generation=o.generation
              AND g.valid_from<=? AND (g.valid_to IS NULL OR g.valid_to>?)) LIMIT 1
            """, [.text(source), .text(key), .integer(revision), .integer(revision), .integer(revision), .integer(revision)]) != nil
    }

    func claudeOwnershipRevision(source: String, at revision: Int64) throws -> Int64 {
        let opened = try scalar("SELECT max(valid_from) FROM claude_message_owner WHERE source_id=? AND valid_from<=?", [.text(source), .integer(revision)]) ?? 0
        let closed = try scalar("SELECT max(valid_to) FROM claude_message_owner WHERE source_id=? AND valid_to<=?", [.text(source), .integer(revision)]) ?? 0
        return max(opened, closed)
    }
}

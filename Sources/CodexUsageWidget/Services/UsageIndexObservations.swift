import Foundation

extension UsageIndexStore {
    func beginDiscovery(root: String, runtime: String, now: Date) throws -> Int64 {
        try transaction {
            try execute("INSERT INTO discovery_scan(root_id,runtime,started_at_ms,method,status) VALUES (?,?,?,'paged','scanning')",
                        [.text(root), .text(runtime), .integer(try usageIndexMilliseconds(now))])
            return try scalar("SELECT last_insert_rowid()")!
        }
    }

    func finishDiscovery(scan: Int64, complete: Bool, now: Date) throws {
        try transaction {
            let revision = try allocateRevision(now: now)
            try execute("UPDATE discovery_scan SET completed_at_ms=?,revision_id=?,status=? WHERE id=? AND status='scanning'",
                [.integer(try usageIndexMilliseconds(now)), .integer(revision), .text(complete ? "complete" : "partial"), .integer(scan)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            if complete {
                try execute("""
                    INSERT INTO source_observation(source_id,revision_id,scan_id,file_identity,target_end,status,observed_at_ms)
                    SELECT s.id,?,?,'',0,'missing',? FROM source s JOIN discovery_scan d ON d.root_id=s.root_id AND d.runtime=s.runtime
                    WHERE d.id=? AND s.discovered_epoch<>?
                    """, [.integer(revision), .integer(scan), .integer(try usageIndexMilliseconds(now)), .integer(scan), .integer(scan)])
            }
        }
    }

    func observeSource(source: String, identity: String, targetEnd: Int64, status: String, now: Date) throws {
        guard targetEnd >= 0, ["readable", "missing", "changed", "unreadable"].contains(status) else { throw UsageIndexError.cacheInvalid }
        try transaction {
            let previous = try rows("SELECT file_identity,target_end,status FROM source_observation WHERE source_id=? ORDER BY revision_id DESC LIMIT 1",
                                    [.text(source)], limit: 1).first
            if previous == [.text(identity), .integer(targetEnd), .text(status)] { return }
            let revision = try allocateRevision(now: now)
            try execute("INSERT INTO source_observation(source_id,revision_id,file_identity,target_end,status,observed_at_ms) VALUES (?,?,?,?,?,?)",
                [.text(source), .integer(revision), .text(identity), .integer(targetEnd), .text(status), .integer(try usageIndexMilliseconds(now))])
        }
    }

    func observationIsCovered(source: String, revision: Int64) throws -> Bool {
        guard let observation = try rows("SELECT file_identity,target_end,status FROM source_observation WHERE source_id=? AND revision_id<=? ORDER BY revision_id DESC LIMIT 1",
                                        [.text(source), .integer(revision)], limit: 1).first,
              observation[2].text == "readable",
              let generation = try rows("""
                SELECT g.file_identity,c.complete_offset FROM source_generation g
                JOIN checkpoint_version c ON c.source_id=g.source_id AND c.generation=g.generation
                WHERE g.source_id=? AND g.valid_from<=? AND (g.valid_to IS NULL OR g.valid_to>?)
                AND c.revision_id<=? ORDER BY c.revision_id DESC LIMIT 1
                """, [.text(source), .integer(revision), .integer(revision), .integer(revision)], limit: 1).first,
              let target = observation[1].integer, let offset = generation[1].integer else { return false }
        return observation[0] == generation[0] && offset >= target
    }
}

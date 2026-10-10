import Foundation

struct UsageIndexJob {
    let id: String
    let source: String?
    let kind: String
    let priority: Int
    let claimVersion: Int64
}

extension UsageIndexStore {
    func enqueueSource(_ source: String, priority: Int, now: Date) throws {
        guard (1...3).contains(priority) else { throw UsageIndexError.resourceLimited }
        let timestamp = try usageIndexMilliseconds(now)
        try execute("""
            INSERT INTO job(id,dedup_key,kind,priority,source_id,status,cursor,created_at_ms,updated_at_ms)
            VALUES (?,?,'parse',?,?,'queued','{}',?,?)
            ON CONFLICT(dedup_key) DO UPDATE SET
              priority=min(job.priority,excluded.priority),
              status=CASE WHEN job.status='running' THEN 'running' ELSE 'queued' END,
              updated_at_ms=max(job.updated_at_ms+1,excluded.updated_at_ms),retry_at_ms=NULL
            """, [.text(UUID().uuidString), .text("parse:" + source), .integer(Int64(priority)), .text(source),
                  .integer(timestamp), .integer(timestamp)])
    }

    /// Inventory refreshes are level-triggered. Re-aging already queued work on every
    /// scan can starve the same older sources forever while a large backfill is running.
    func enqueueDiscoveredSource(_ source: String, priority: Int, now: Date) throws {
        let state = try rows("SELECT status FROM job WHERE dedup_key=?", [.text("parse:"+source)], limit:1).first?.first?.text
        if state == "queued" || state == "running" {
            try execute("UPDATE job SET priority=min(priority,?),retry_at_ms=NULL WHERE dedup_key=?",[.integer(Int64(priority)),.text("parse:"+source)])
        } else {
            try enqueueSource(source, priority:priority, now:now)
        }
    }

    func recoverInterruptedJobs() throws {
        try execute("UPDATE job SET status='queued' WHERE status='running'")
    }

    /// Persistent weighted rotation: at least two old-history slots and one maintenance slot per ten claims.
    func claimJob(now: Date, avoiding source: String? = nil) throws -> UsageIndexJob? {
        try transaction {
            let previous = try rows("SELECT value FROM index_meta WHERE key='scheduler-step'", limit: 1).first?.first?.text
            let step = (Int(previous ?? "0") ?? 0) % 10
            let preferred = step == 9 ? 3 : ([3, 7].contains(step) ? 2 : 1)
            let timestamp = try usageIndexMilliseconds(now)
            let records = try rows("""
                SELECT id,source_id,kind,priority,updated_at_ms FROM job
                WHERE kind='parse' AND source_id IS NOT NULL AND status='queued' AND (retry_at_ms IS NULL OR retry_at_ms<=?)
                ORDER BY CASE WHEN priority=? THEN 0 ELSE 1 END,
                  CASE WHEN source_id=? THEN 1 ELSE 0 END,updated_at_ms,id LIMIT 1
                """, [.integer(timestamp), .integer(Int64(preferred)), source.map(UsageSQLValue.text) ?? .null], limit: 1)
            guard let row = records.first, let id = row[0].text, let kind = row[2].text,
                  let priority = row[3].integer, let version = row[4].integer else { return nil }
            try execute("UPDATE job SET status='running' WHERE id=? AND status='queued'", [.text(id)])
            guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
            try execute("INSERT INTO index_meta(key,value) VALUES ('scheduler-step',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                        [.text(String((step + 1) % 10))])
            return UsageIndexJob(id: id, source: row[1].text, kind: kind, priority: Int(priority), claimVersion: version)
        }
    }

    /// A source notification arriving during work must survive completion of the older claim.
    func finishJob(_ job: UsageIndexJob, more: Bool, retryAt: Date? = nil, now: Date) throws {
        let retry = try retryAt.map { UsageSQLValue.integer(try usageIndexMilliseconds($0)) } ?? .null
        try execute("""
            UPDATE job SET status=CASE WHEN updated_at_ms<>? OR ?=1 THEN 'queued' ELSE 'done' END,
              retry_at_ms=?,updated_at_ms=max(updated_at_ms,?) WHERE id=? AND status='running'
            """, [.integer(job.claimVersion), .integer(more ? 1 : 0), retry,
                  .integer(try usageIndexMilliseconds(now)), .text(job.id)])
        guard try scalar("SELECT changes()") == 1 else { throw UsageIndexError.sourceChanged }
    }
}

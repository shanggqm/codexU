import Foundation

private struct UsageMaterializationCursor: Codable {
    var revision: Int64 = 0
    var requestedRevision: Int64? = nil
    var phase = "dependency"
    var token = UsagePrefixCursor()
    var inference = UsagePrefixCursor()
    var projection: UsageProjectionCursor?
}

/// Queue-owned by the same writer as ingestion. Work and pins survive process exit in job/report rows.
final class UsageIndexMaterializer {
    let store: UsageIndexStore
    let statistics: StatisticsContext
    let root: String
    let runtime: String
    let context: String
    private var activeBuild: String?
    private var dirty = false
    private var steps = 0
    var hasPendingWork: Bool { dirty || activeBuild != nil }
    func invalidateArchive() { dirty = true }
    private var lastBuildStart: TimeInterval = 0
    var onArchive: ((String) -> Void)?

    init(store: UsageIndexStore, root: String, statistics: StatisticsContext, runtime: String = "codex") throws {
        self.store = store; self.root = root; self.statistics = statistics; self.runtime = runtime
        context = try store.ensureProjectionContext(root: root, statistics: statistics, now: Date())
        activeBuild = try store.rows("SELECT id FROM report_build WHERE context_id=? AND runtime=? AND state='building' ORDER BY created_at_ms LIMIT 1",
                                    [.text(context), .text(runtime)], limit: 1).first?.first?.text
    }

    func enqueue(_ source: String) throws {
        guard let checkpoint = try store.checkpoint(source: source), checkpoint.offset == checkpoint.targetEnd,
              try store.scalar("SELECT valid_from FROM source_generation WHERE source_id=? AND generation=?",[.text(source),.integer(checkpoint.generation)]) != nil,
              let metadata = try store.metadata(source: source, revision: Int64.max) else { return }
        var requested = max(checkpoint.revision, metadata.revision)
        if runtime == "claude-code" {
            requested = max(requested, try store.claudeOwnershipRevision(source: source, at: Int64.max))
        }
        if let parentID = metadata.value.parentLogicalID,
           let parent = try store.rows("SELECT id FROM source WHERE root_id=? AND runtime=? AND logical_id=? LIMIT 1",
                [.text(root), .text(runtime), .text(parentID)], limit: 1).first?.first?.text {
            requested = max(requested, try store.checkpoint(source: parent)?.revision ?? 0,
                try store.metadata(source: parent, revision: Int64.max)?.revision ?? 0)
        }
        let payload = String(decoding: try JSONEncoder().encode(UsageMaterializationCursor()), as: UTF8.self)
        try store.execute("""
            INSERT INTO job(id,dedup_key,kind,priority,source_id,context_id,status,cursor,cut_revision,created_at_ms,updated_at_ms)
            VALUES (?,?,'materialize',2,?,?,'queued',?,?,?,?) ON CONFLICT(dedup_key) DO UPDATE SET
              status='queued',cursor=CASE WHEN job.status='done' THEN excluded.cursor ELSE job.cursor END,
              cut_revision=excluded.cut_revision,retry_at_ms=NULL
            WHERE excluded.cut_revision>coalesce(job.cut_revision,0)
            """, [.text(UUID().uuidString), .text("materialize:" + context + ":" + source), .text(source), .text(context), .text(payload),
                  .integer(requested), .integer(try usageIndexMilliseconds(Date())), .integer(try usageIndexMilliseconds(Date()))])
    }

    func step() throws -> Bool {
        steps += 1
        if activeBuild == nil, dirty, ProcessInfo.processInfo.systemUptime - lastBuildStart >= 2 {
            activeBuild = try store.beginDayArchive(context: context, root: root, dayKey: statistics.dayKey(for: statistics.now), now: Date(), runtime: runtime)
            lastBuildStart = ProcessInfo.processInfo.systemUptime; dirty = false
        }
        if let build = activeBuild, steps % 4 == 0 {
            if try store.stepDayArchive(build: build, now: Date()) { activeBuild = nil; onArchive?(build) }
            return true
        }
        if let job = try store.rows("""
            SELECT id,source_id,cursor,cut_revision FROM job WHERE kind='materialize' AND context_id=? AND status='queued' AND source_id IN (SELECT id FROM source WHERE runtime=?)
            AND (retry_at_ms IS NULL OR retry_at_ms<=?)
            AND (json_extract(cursor,'$.phase')='projection' OR EXISTS (
                SELECT 1 FROM source_generation g WHERE g.source_id=job.source_id AND g.valid_from IS NOT NULL
                AND g.valid_to IS NULL AND g.checkpoint_offset=g.observed_end))
            ORDER BY updated_at_ms,id LIMIT 1
            """, [.text(context), .text(runtime), .integer(try usageIndexMilliseconds(Date()))], limit: 1).first,
           let id = job[0].text, let source = job[1].text, let payload = job[2].text {
            var cursor = try JSONDecoder().decode(UsageMaterializationCursor.self, from: Data(payload.utf8))
            do {
                let latest = try store.scalar("SELECT max(id) FROM revision") ?? 0
                if cursor.revision == 0 { cursor.revision = latest; cursor.requestedRevision = job[3].integer }
                if cursor.phase == "dependency" {
                    guard let own = try store.checkpoint(source: source), own.offset == own.targetEnd else { throw UsageIndexError.sourceChanged }
                    guard let metadata = try store.metadata(source: source, revision: latest) else { throw UsageIndexError.cacheInvalid }
                    if let parentID = metadata.value.parentLogicalID {
                        guard let parent = try store.rows("SELECT id FROM source WHERE root_id=? AND runtime='codex' AND logical_id=? ORDER BY id LIMIT 1",
                            [.text(root), .text(parentID)], limit: 1).first?.first?.text,
                            let parentCheckpoint = try store.checkpoint(source: parent), parentCheckpoint.offset == parentCheckpoint.targetEnd,
                            let parentMetadata = try store.metadata(source: parent, revision: cursor.revision) else { throw UsageIndexError.sourceChanged }
                        cursor.token = try store.comparePrefix(child: source, parent: parent, kind: "token", revision: cursor.revision, cursor: cursor.token)
                        cursor.inference = try store.comparePrefix(child: source, parent: parent, kind: "inference", revision: cursor.revision, cursor: cursor.inference)
                        if cursor.token.finished && cursor.inference.finished {
                            try store.recordDependency(child: source, expectedChild: own, childMetadataRevision: metadata.revision,
                                parent: parent, expectedParent: parentCheckpoint, parentMetadataRevision: parentMetadata.revision,
                                parentLogicalID: parentID, tokenResult: cursor.token, inferenceResult: cursor.inference, now: Date())
                            guard try store.dependencyIsCurrent(source: source) else { throw UsageIndexError.sourceChanged }
                            cursor.revision = try store.scalar("SELECT max(id) FROM revision") ?? latest
                            cursor.phase = "projection"
                        }
                    } else { cursor.phase = "projection" }
                }
                if cursor.phase == "projection" {
                    if cursor.projection == nil {
                        cursor.projection = try store.beginUsageProjection(context: context, source: source, revision: cursor.revision, now: Date())
                    }
                    guard let projection = cursor.projection else { throw UsageIndexError.sourceChanged }
                    cursor.projection = try store.stepUsageProjection(projection, statistics: statistics, now: Date())
                }
                let done = cursor.projection?.finished == true
                let rerun = done && (job[3].integer ?? 0) > (cursor.requestedRevision ?? 0)
                if rerun { cursor = UsageMaterializationCursor() }
                let data = try JSONEncoder().encode(cursor)
                guard data.count <= UsageIndexStore.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
                try store.execute("UPDATE job SET cursor=?,status=?,updated_at_ms=? WHERE id=?", [.text(String(decoding: data, as: UTF8.self)),
                    .text(done && !rerun ? "done" : "queued"), .integer(try usageIndexMilliseconds(Date())), .text(id)])
                if done { if runtime == "codex" { try enqueueChildren(source) }; dirty = true }
            } catch UsageIndexError.sourceChanged {
                let reset = String(decoding: try JSONEncoder().encode(UsageMaterializationCursor()), as: UTF8.self)
                try store.execute("UPDATE job SET cursor=?,retry_at_ms=? WHERE id=?", [.text(reset),
                    .integer(try usageIndexMilliseconds(Date().addingTimeInterval(2))), .text(id)])
            }
            return true
        }
        if activeBuild == nil, dirty, ProcessInfo.processInfo.systemUptime - lastBuildStart >= 2 {
            activeBuild = try store.beginDayArchive(context: context, root: root, dayKey: statistics.dayKey(for: statistics.now), now: Date(), runtime: runtime)
            lastBuildStart = ProcessInfo.processInfo.systemUptime; dirty = false
        }
        if let build = activeBuild {
            if try store.stepDayArchive(build: build, now: Date()) { activeBuild = nil; onArchive?(build) }
            return true
        }
        return false
    }

    private func enqueueChildren(_ source: String) throws {
        guard let logicalID = try store.rows("SELECT logical_id FROM source WHERE id=?", [.text(source)], limit: 1).first?.first?.text else { return }
        var after = ""
        while true {
            let page = try store.rows("""
                SELECT s.id FROM source s JOIN source_metadata_version m ON m.source_id=s.id AND m.valid_to IS NULL
                WHERE s.root_id=? AND s.runtime='codex' AND s.id>? AND json_extract(m.payload,'$.parentLogicalID')=?
                ORDER BY s.id LIMIT 100
                """, [.text(root), .text(after), .text(logicalID)], limit: 100)
            if page.isEmpty { break }
            for row in page { if let child = row[0].text { after = child; try enqueue(child) } }
        }
    }
}

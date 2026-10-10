import Foundation

extension UsageIndexStore {
    /// Leave room for the private inventory spool and WAL instead of allowing the main database
    /// to consume the entire 2 GiB index allowance.
    func configureStorageBudget() throws {
        let pageSize = try scalar("PRAGMA page_size") ?? 4096
        guard pageSize > 0 else { throw UsageIndexError.cacheInvalid }
        let maximumPages = (1792 * 1024 * 1024) / pageSize
        try execute("PRAGMA max_page_count=\(maximumPages)")
        try execute("PRAGMA journal_size_limit=33554432")
    }

    /// Pins protect fixed cuts. Only derived, unreferenced output and obsolete source generations
    /// are removed. Original logs and the current published manifests are never deletion targets.
    func collectReportGarbage(now: Date) throws -> Int {
        try withDeadline(milliseconds: 100) {
            try transaction {
                guard let row = try rows("""
                    SELECT b.id,b.context_id,b.cursor FROM report_build b
                    WHERE b.state IN ('ready','partial') AND b.updated_at_ms<?
                      AND NOT EXISTS (SELECT 1 FROM published_slice p WHERE p.build_id=b.id)
                      AND NOT EXISTS (SELECT 1 FROM revision_pin p WHERE p.owner_id='report:'||b.id)
                    LIMIT 1
                    """, [.integer(try usageIndexMilliseconds(now.addingTimeInterval(-60)))], limit: 1).first,
                      let id = row[0].text, let context = row[1].text, let cursor = row[2].text else { return 0 }
                let archive = try JSONDecoder().decode(UsageArchiveCursor.self, from: Data(cursor.utf8))
                // Commit each bounded deletion separately. A later timeout cannot undo earlier
                // progress, and the context/revision index avoids scanning every archive row.
                try execute("""
                    DELETE FROM archive_day WHERE rowid IN (SELECT rowid FROM archive_day
                    WHERE context_id=? AND revision_id=? LIMIT 256)
                    """, [.text(context), .integer(archive.publicationRevision)])
                var removed = try scalar("SELECT changes()") ?? 0
                if removed > 0 { return Int(removed) }
                for table in ["build_member", "build_interval", "build_boundary", "build_metric", "build_sample"] {
                    try execute("DELETE FROM \(table) WHERE rowid IN (SELECT rowid FROM \(table) WHERE build_id=? LIMIT 256)", [.text(id)])
                    removed = try scalar("SELECT changes()") ?? 0
                    if removed > 0 { return Int(removed) }
                }
                try execute("DELETE FROM report_build WHERE id=?", [.text(id)])
                return 1
            }
        }
    }

    func collectGarbage(now: Date) throws -> Int {
        let removed = try collectReportGarbage(now: now)
        if removed > 0 { return removed }
        return try withDeadline(milliseconds: 100) {
            try transaction {
                let floor = try scalar("SELECT min(value) FROM (SELECT revision_id value FROM revision_pin UNION ALL SELECT b.cut_revision FROM published_slice p JOIN report_build b ON b.id=p.build_id UNION ALL SELECT max(id) FROM revision)") ?? 0
                let projections = try rows("""
                    SELECT p.id FROM source_projection p WHERE p.state IN ('ready','retired') AND p.input_revision<?
                      AND NOT EXISTS (SELECT 1 FROM build_member m WHERE m.projection_id=p.id)
                      AND NOT EXISTS (SELECT 1 FROM revision_pin pin WHERE pin.owner_id='projection:'||p.id)
                      AND (EXISTS (SELECT 1 FROM source_projection n WHERE n.context_id=p.context_id AND n.source_id=p.source_id
                        AND n.generation=p.generation AND n.state='ready' AND n.input_revision>p.input_revision AND n.input_revision<=?)
                        OR EXISTS (SELECT 1 FROM source_generation g WHERE g.source_id=p.source_id AND g.generation=p.generation AND g.valid_to<=?))
                    ORDER BY p.input_revision LIMIT 10
                    """, [.integer(floor), .integer(floor), .integer(floor)], limit: 10)
                for row in projections {
                    guard let id = row[0].text else { continue }
                    try execute("DELETE FROM source_day WHERE projection_id=?", [.text(id)])
                    try execute("DELETE FROM job WHERE dedup_key=? AND status='done'", [.text("projection:" + id)])
                    try execute("DELETE FROM source_projection WHERE id=?", [.text(id)])
                }
                let generations = try rows("""
                    SELECT g.source_id,g.generation FROM source_generation g WHERE g.valid_to<=?
                    AND NOT EXISTS (SELECT 1 FROM source_projection p WHERE p.source_id=g.source_id AND p.generation=g.generation)
                    AND NOT EXISTS (SELECT 1 FROM claude_message_owner o WHERE o.source_id=g.source_id AND o.generation=g.generation)
                    AND NOT EXISTS (SELECT 1 FROM dependency_version d WHERE d.parent_source_id=g.source_id AND d.parent_generation=g.generation
                      AND (d.valid_to IS NULL OR d.valid_to>?)) LIMIT 5
                    """, [.integer(floor), .integer(floor)], limit: 5)
                for row in generations {
                    guard let source = row[0].text, let generation = row[1].integer else { continue }
                    try execute("DELETE FROM dependency_version WHERE (child_source_id=? AND child_generation=?) OR (parent_source_id=? AND parent_generation=? AND valid_to<=?)",
                        [.text(source), .integer(generation), .text(source), .integer(generation), .integer(floor)])
                    try execute("DELETE FROM fact WHERE rowid IN (SELECT rowid FROM fact WHERE source_id=? AND generation=? LIMIT 200)", [.text(source), .integer(generation)])
                    if try scalar("SELECT 1 FROM fact WHERE source_id=? AND generation=? LIMIT 1", [.text(source), .integer(generation)]) != nil { continue }
                    try execute("DELETE FROM checkpoint_version WHERE rowid IN (SELECT rowid FROM checkpoint_version WHERE source_id=? AND generation=? LIMIT 200)", [.text(source), .integer(generation)])
                    if try scalar("SELECT 1 FROM checkpoint_version WHERE source_id=? AND generation=? LIMIT 1", [.text(source), .integer(generation)]) != nil { continue }
                    try execute("DELETE FROM source_generation WHERE source_id=? AND generation=?", [.text(source), .integer(generation)])
                }
                return projections.count + generations.count
            }
        }
    }
}

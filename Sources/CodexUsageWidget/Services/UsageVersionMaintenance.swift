import Foundation

extension UsageIndexStore {
    /// Retain the predecessor needed by the oldest active/published cut, not every historical
    /// checkpoint or superseded logical fact version forever. Immutable facts remain available.
    func collectVersionGarbage(now: Date) throws {
        try withDeadline(milliseconds: 100) {
            try transaction {
                let floor=try scalar("""
                    SELECT min(value) FROM (
                      SELECT revision_id value FROM revision_pin
                      UNION ALL SELECT b.cut_revision FROM published_slice p JOIN report_build b ON b.id=p.build_id
                      UNION ALL SELECT max(id) FROM revision)
                    """) ?? 0
                try execute("""
                    DELETE FROM fact WHERE rowid IN (SELECT f.rowid FROM fact f WHERE f.commit_revision<?
                      AND EXISTS (SELECT 1 FROM fact n WHERE n.source_id=f.source_id AND n.generation=f.generation
                        AND n.kind=f.kind AND n.logical_key=f.logical_key AND n.commit_revision<=?
                        AND (n.commit_revision>f.commit_revision OR (n.commit_revision=f.commit_revision AND n.sequence>f.sequence))) LIMIT 200)
                    """,[.integer(floor),.integer(floor)])
                try execute("""
                    DELETE FROM checkpoint_version WHERE rowid IN (SELECT c.rowid FROM checkpoint_version c WHERE c.revision_id<?
                      AND EXISTS (SELECT 1 FROM checkpoint_version n WHERE n.source_id=c.source_id AND n.generation=c.generation
                        AND n.revision_id>c.revision_id AND n.revision_id<=?) LIMIT 200)
                    """,[.integer(floor),.integer(floor)])
                // A cancelled materialization may leave an obsolete building projection and pin.
                let abandoned=try rows("""
                    SELECT p.id FROM source_projection p WHERE p.state='building' AND p.updated_at_ms<?
                    AND NOT EXISTS (SELECT 1 FROM job j WHERE j.kind='materialize' AND j.status='queued'
                      AND json_extract(j.cursor,'$.projection.projectionID')=p.id)
                    AND NOT EXISTS (SELECT 1 FROM build_member m WHERE m.projection_id=p.id) LIMIT 5
                    """,[.integer(try usageIndexMilliseconds(now.addingTimeInterval(-3600)))],limit:5)
                for row in abandoned {
                    guard let id=row[0].text else { continue }
                    try execute("DELETE FROM revision_pin WHERE owner_id=?",[.text("projection:"+id)])
                    try execute("DELETE FROM job WHERE dedup_key=?",[.text("projection:"+id)])
                    try execute("DELETE FROM source_day WHERE projection_id=?",[.text(id)])
                    try execute("DELETE FROM source_projection WHERE id=?",[.text(id)])
                }
                // Keep the latest ownership invalidation for every source: its projection key
                // must remain monotonic even after losing its final owned message.
                try execute("""
                    DELETE FROM claude_message_owner WHERE rowid IN (
                      SELECT o.rowid FROM claude_message_owner o WHERE o.valid_to<=?
                      AND EXISTS (SELECT 1 FROM claude_message_owner n WHERE n.source_id=o.source_id
                        AND ((n.valid_from>o.valid_to AND n.valid_from<=?)
                          OR (n.valid_to>o.valid_to AND n.valid_to<=?))) LIMIT 200)
                    """,[.integer(floor),.integer(floor),.integer(floor)])
                // Closed ownership keeps its source watermark, but no longer pins retired
                // generation bodies once every live cut is beyond its closing revision.
                try execute("""
                    UPDATE claude_message_owner SET generation=NULL WHERE rowid IN (
                      SELECT rowid FROM claude_message_owner WHERE valid_to<=? AND generation IS NOT NULL LIMIT 200)
                    """,[.integer(floor)])
                try execute("""
                    DELETE FROM discovery_scan WHERE id IN (SELECT d.id FROM discovery_scan d
                      WHERE d.status<>'scanning' AND d.completed_at_ms<?
                      AND NOT EXISTS (SELECT 1 FROM report_build b WHERE b.scan_id=d.id)
                      AND NOT EXISTS (SELECT 1 FROM source_observation o WHERE o.scan_id=d.id)
                      AND d.id<>(SELECT max(n.id) FROM discovery_scan n WHERE n.root_id=d.root_id AND n.runtime=d.runtime)
                      LIMIT 100)
                    """,[.integer(try usageIndexMilliseconds(now.addingTimeInterval(-86400)))])
            }
        }
    }
}

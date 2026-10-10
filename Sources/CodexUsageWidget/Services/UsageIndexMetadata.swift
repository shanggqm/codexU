import Foundation

struct UsageSourceMetadata: Codable, Equatable {
    let model: String?
    let project: String
    var parentLogicalID: String?
    var createdAt: Int64? = nil
    var sourceKind: String? = nil
    var workerParentID: String? = nil
    var automationID: String? = nil
}

extension UsageIndexStore {
    @discardableResult
    func recordMetadata(source: String, metadata: UsageSourceMetadata, now: Date) throws -> Int64 {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        guard data.count <= Self.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
        let payload = String(decoding: data, as: UTF8.self)
        return try transaction {
            if let current = try rows("SELECT valid_from,payload FROM source_metadata_version WHERE source_id=? AND valid_to IS NULL",
                                      [.text(source)], limit: 1).first, current[1].text == payload,
               let revision = current[0].integer { return revision }
            let previousParent = try self.metadata(source: source, revision: Int64.max)?.value.parentLogicalID
            let revision = try allocateRevision(now: now)
            if previousParent != metadata.parentLogicalID {
                try execute("UPDATE dependency_version SET valid_to=? WHERE child_source_id=? AND valid_to IS NULL", [.integer(revision),.text(source)])
            }
            try execute("UPDATE source_metadata_version SET valid_to=? WHERE source_id=? AND valid_to IS NULL", [.integer(revision), .text(source)])
            try execute("INSERT INTO source_metadata_version(source_id,valid_from,payload) VALUES (?,?,?)",
                        [.text(source), .integer(revision), .text(payload)])
            return revision
        }
    }

    func metadata(source: String, revision: Int64) throws -> (revision: Int64, value: UsageSourceMetadata)? {
        guard let row = try rows("""
            SELECT valid_from,payload FROM source_metadata_version WHERE source_id=?
            AND valid_from<=? AND (valid_to IS NULL OR valid_to>?) ORDER BY valid_from DESC LIMIT 1
            """, [.text(source), .integer(revision), .integer(revision)], limit: 1).first,
              let version = row[0].integer, let payload = row[1].text else { return nil }
        return (version, try JSONDecoder().decode(UsageSourceMetadata.self, from: Data(payload.utf8)))
    }
}

import Foundation

/// The two prefixes deliberately have independent cursors: rejected token events and inference
/// samples do not have a one-to-one correspondence.
struct UsagePrefixCursor: Codable {
    var binding: UsagePrefixBinding?
    var childKey = ""
    var parentKey = ""
    var count = 0
    var finished = false
}

struct UsagePrefixBinding: Codable, Equatable {
    let child: String
    let parent: String
    let kind: String
    let revision: Int64
    let childGeneration: Int64
    let parentGeneration: Int64
    let childCheckpoint: Int64
    let parentCheckpoint: Int64
    let childMetadata: Int64
    let parentMetadata: Int64
}

extension UsageIndexStore {
    func comparePrefix(child: String, parent: String, kind: String, revision: Int64,
                       cursor: UsagePrefixCursor, maximumPairs: Int = 100) throws -> UsagePrefixCursor {
        guard ["token", "inference"].contains(kind), (1...100).contains(maximumPairs) else {
            throw UsageIndexError.resourceLimited
        }
        guard let childCheckpoint = try checkpoint(source: child), let parentCheckpoint = try checkpoint(source: parent),
              childCheckpoint.revision <= revision, parentCheckpoint.revision <= revision,
              let childMetadata = try metadata(source: child, revision: revision),
              let parentMetadata = try metadata(source: parent, revision: revision) else { throw UsageIndexError.sourceChanged }
        let binding = UsagePrefixBinding(child: child, parent: parent, kind: kind, revision: revision,
            childGeneration: childCheckpoint.generation, parentGeneration: parentCheckpoint.generation,
            childCheckpoint: childCheckpoint.revision, parentCheckpoint: parentCheckpoint.revision,
            childMetadata: childMetadata.revision, parentMetadata: parentMetadata.revision)
        var next = cursor
        if let previous = next.binding { guard previous == binding else { throw UsageIndexError.sourceChanged } }
        else { next.binding = binding }
        guard !next.finished else { return next }
        var children: [[UsageSQLValue]] = [], parents: [[UsageSQLValue]] = []
        func nextRow(source: String, key: inout String, buffered: inout [[UsageSQLValue]]) throws -> [UsageSQLValue]? {
            while true {
                if buffered.isEmpty { buffered = try factsAt(source: source, kind: kind, revision: revision, afterKey: key) }
                guard !buffered.isEmpty else { return nil }
                let row = buffered.removeFirst()
                guard let rowKey = row[0].text else { throw UsageIndexError.cacheInvalid }
                key = rowKey
                if row[1].text != "delete" { return row }
            }
        }
        for _ in 0..<maximumPairs {
            guard let a = try nextRow(source: child, key: &next.childKey, buffered: &children),
                  let b = try nextRow(source: parent, key: &next.parentKey, buffered: &parents),
                  let ap = a[3].text, let bp = b[3].text else { next.finished = true; break }
            let left = try JSONDecoder().decode(UsageFactPayload.self, from: Data(ap.utf8))
            let right = try JSONDecoder().decode(UsageFactPayload.self, from: Data(bp.utf8))
            let equal: Bool
            switch (left, right) {
            case (.token(let x), .token(let y)): equal = x.eventIdentity == y.eventIdentity
            case (.inference(let x), .inference(let y)): equal = x.eventIdentity == y.eventIdentity
            default: throw UsageIndexError.cacheInvalid
            }
            if !equal { next.finished = true; break }
            next.count += 1
        }
        return next
    }

    /// Call after a resumable comparison finishes. The four watermarks make a computed prefix
    /// unusable as soon as either source appends or either source's metadata changes.
    func recordDependency(child: String, expectedChild: UsageIndexCheckpoint,
                          childMetadataRevision: Int64, parent: String, expectedParent: UsageIndexCheckpoint,
                          parentMetadataRevision: Int64, parentLogicalID: String,
                          tokenResult: UsagePrefixCursor, inferenceResult: UsagePrefixCursor, now: Date) throws {
        guard tokenResult.finished, inferenceResult.finished, tokenResult.count >= 0, inferenceResult.count >= 0,
              let tokenBinding = tokenResult.binding, let inferenceBinding = inferenceResult.binding,
              tokenBinding.kind == "token", inferenceBinding.kind == "inference", tokenBinding.revision == inferenceBinding.revision else {
            throw UsageIndexError.sourceChanged
        }
        for binding in [tokenBinding, inferenceBinding] {
            guard binding.child == child, binding.parent == parent,
                  binding.childGeneration == expectedChild.generation, binding.parentGeneration == expectedParent.generation,
                  binding.childCheckpoint == expectedChild.revision, binding.parentCheckpoint == expectedParent.revision,
                  binding.childMetadata == childMetadataRevision, binding.parentMetadata == parentMetadataRevision else {
                throw UsageIndexError.sourceChanged
            }
        }
        let tokenPrefix = tokenResult.count, inferencePrefix = inferenceResult.count
        try transaction {
            guard let identities = try rows("SELECT c.root_id,p.root_id,c.runtime,p.runtime,p.logical_id FROM source c CROSS JOIN source p WHERE c.id=? AND p.id=?",
                [.text(child), .text(parent)], limit: 1).first, identities[0] == identities[1], identities[2] == identities[3],
                identities[4].text == parentLogicalID,
                try metadata(source: child, revision: tokenBinding.revision)?.value.parentLogicalID == parentLogicalID else {
                throw UsageIndexError.sourceChanged
            }
            guard try checkpoint(source: child)?.revision == expectedChild.revision,
                  try checkpoint(source: parent)?.revision == expectedParent.revision,
                  try scalar("SELECT max(valid_from) FROM source_metadata_version WHERE source_id=?", [.text(child)]) == childMetadataRevision,
                  try scalar("SELECT max(valid_from) FROM source_metadata_version WHERE source_id=?", [.text(parent)]) == parentMetadataRevision else {
                throw UsageIndexError.sourceChanged
            }
            let revision = try allocateRevision(now: now)
            try execute("UPDATE dependency_version SET valid_to=? WHERE child_source_id=? AND child_generation=? AND valid_to IS NULL",
                        [.integer(revision), .text(child), .integer(expectedChild.generation)])
            try execute("""
                INSERT INTO dependency_version(child_source_id,child_generation,parent_logical_id,parent_source_id,parent_generation,
                  valid_from,token_prefix,inference_prefix,status,updated_at_ms,child_checkpoint_revision,parent_checkpoint_revision,
                  child_metadata_revision,parent_metadata_revision) VALUES (?,?,?,?,?,?,?,?,'resolved',?,?,?,?,?)
                """, [.text(child), .integer(expectedChild.generation), .text(parentLogicalID), .text(parent), .integer(expectedParent.generation),
                      .integer(revision), .integer(Int64(tokenPrefix)), .integer(Int64(inferencePrefix)), .integer(try usageIndexMilliseconds(now)),
                      .integer(expectedChild.revision), .integer(expectedParent.revision), .integer(childMetadataRevision), .integer(parentMetadataRevision)])
        }
    }

    /// Resolve ancestors iteratively with a bounded working set. A missing, stale, or cyclic parent
    /// makes the child pending instead of silently counting its inherited history again.
    func dependencyIsCurrent(source: String, maximumDepth: Int = 256) throws -> Bool {
        try dependencyIsValidAt(source: source, revision: scalar("SELECT max(id) FROM revision") ?? 0, maximumDepth: maximumDepth)
    }

    func dependencyIsValidAt(source: String, revision: Int64, maximumDepth: Int = 256) throws -> Bool {
        var current = source
        var seen = Set<String>()
        func checkpointAt(_ source: String) throws -> (generation: Int64, revision: Int64)? {
            guard let row = try rows("""
                SELECT g.generation,c.revision_id,c.complete_offset,c.observed_end FROM source_generation g
                JOIN checkpoint_version c ON c.source_id=g.source_id AND c.generation=g.generation
                WHERE g.source_id=? AND g.valid_from<=? AND (g.valid_to IS NULL OR g.valid_to>?)
                  AND c.revision_id<=? ORDER BY c.revision_id DESC LIMIT 1
                """, [.text(source), .integer(revision), .integer(revision), .integer(revision)], limit: 1).first,
                let generation = row[0].integer, let version = row[1].integer, row[2] == row[3] else { return nil }
            return (generation, version)
        }
        for _ in 0..<maximumDepth {
            guard seen.insert(current).inserted,
                  let own = try checkpointAt(current),
                  let metadata = try metadata(source: current, revision: revision) else { return false }
            guard let parentID = metadata.value.parentLogicalID else { return true }
            guard let row = try rows("""
                SELECT parent_source_id,parent_generation,child_checkpoint_revision,parent_checkpoint_revision,
                  child_metadata_revision,parent_metadata_revision,parent_logical_id FROM dependency_version
                WHERE child_source_id=? AND child_generation=? AND valid_from<=? AND (valid_to IS NULL OR valid_to>?) AND status='resolved'
                """, [.text(current), .integer(own.generation), .integer(revision), .integer(revision)], limit: 1).first,
                  let parent = row[0].text, row[6].text == parentID,
                  row[2].integer == own.revision, row[4].integer == metadata.revision,
                  let parentCheckpoint = try checkpointAt(parent),
                  row[1].integer == parentCheckpoint.generation, row[3].integer == parentCheckpoint.revision,
                  let parentMetadata = try self.metadata(source: parent, revision: revision),
                  row[5].integer == parentMetadata.revision else { return false }
            current = parent
        }
        return false
    }
}

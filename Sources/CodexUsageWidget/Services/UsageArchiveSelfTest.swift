import Foundation

enum UsageArchiveSelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func check(_ value: Bool) throws { if !value { throw UsageIndexError.databaseFailure } }
        do {
            let store = try UsageIndexStore(directory: directory)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let statistics = StatisticsContext(preference: .init(selection: .utc, fixedIdentifier: "UTC"), now: now)
            let context = try store.ensureProjectionContext(root: "fixture", statistics: statistics, now: now)
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tests/fixtures/history-index/codex-counters.jsonl")
            let parsed = try UsageStreamParser.readCodex(url: url, targetEnd: UInt64(Data(contentsOf: url).count), checkpoint: CodexIndexCheckpoint())
            let scan = try store.beginDiscovery(root: "fixture", runtime: "codex", now: now)
            for source in ["parent", "child"] {
                try store.registerSource(id: source, root: "fixture", runtime: "codex", logicalID: source, locator: "/fixture", now: now)
                try store.recordMetadata(source: source, metadata: UsageSourceMetadata(model: nil, project: "fixture",
                    parentLogicalID: source == "child" ? "parent" : nil), now: now)
                let checkpoint = try store.beginGeneration(source: source, identity: source, targetEnd: 10, initialState: "{}", now: now)
                let facts = parsed.deltas.enumerated().map { UsageIndexFact(logicalKey: String(format: "%010d", $0.offset),
                    occurredAt: $0.element.date, payload: .token($0.element)) }
                let next = try store.append(source: source, expected: checkpoint, offset: 10, state: "{}", facts: facts, now: now)
                try store.activate(source: source, expected: next, verifiedIdentity: source, now: now)
                try store.execute("UPDATE source SET discovered_epoch=? WHERE id=?", [.integer(scan), .text(source)])
                try store.observeSource(source: source, identity: source, targetEnd: 10, status: "readable", now: now)
            }
            try store.finishDiscovery(scan: scan, complete: true, now: now)
            var revision = try store.scalar("SELECT max(id) FROM revision")!
            try check(!store.dependencyIsCurrent(source: "child"))
            var prefix = UsagePrefixCursor()
            var rounds = 0
            repeat {
                prefix = try store.comparePrefix(child: "child", parent: "parent", kind: "token", revision: revision,
                    cursor: JSONDecoder().decode(UsagePrefixCursor.self, from: JSONEncoder().encode(prefix)), maximumPairs: 1)
                rounds += 1
            } while !prefix.finished && rounds < 10
            try check(prefix.finished && prefix.count == 4)
            let inferencePrefix = try store.comparePrefix(child: "child", parent: "parent", kind: "inference", revision: revision, cursor: UsagePrefixCursor())
            try store.recordDependency(child: "child", expectedChild: store.checkpoint(source: "child")!,
                childMetadataRevision: store.metadata(source: "child", revision: revision)!.revision,
                parent: "parent", expectedParent: store.checkpoint(source: "parent")!,
                parentMetadataRevision: store.metadata(source: "parent", revision: revision)!.revision,
                parentLogicalID: "parent", tokenResult: prefix, inferenceResult: inferencePrefix, now: now)
            revision = try store.scalar("SELECT max(id) FROM revision")!
            try check(store.dependencyIsCurrent(source: "child"))
            func project(_ source: String) throws {
                guard var cursor = try store.beginUsageProjection(context: context, source: source, revision: revision, now: now) else {
                    throw UsageIndexError.databaseFailure
                }
                var count = 0
                while !cursor.finished {
                    cursor = try store.stepUsageProjection(cursor, statistics: statistics, now: now)
                    count += 1
                    try check(count < 100)
                }
            }
            try project("parent"); try project("child")
            func archive() throws -> Int64 {
                let build = try store.beginDayArchive(context: context, root: "fixture", dayKey: statistics.dayKey(for: now), now: now)
                var count = 0
                while try !store.stepDayArchive(build: build, now: now) {
                    count += 1; try check(count < 100)
                }
                try check(store.rows("SELECT state FROM report_build WHERE id=?", [.text(build)], limit: 1).first?.first?.text == "ready")
                let payload = try store.rows("SELECT cursor FROM report_build WHERE id=?", [.text(build)], limit: 1).first?.first?.text
                return try JSONDecoder().decode(UsageArchiveCursor.self, from: Data(payload!.utf8)).publicationRevision
            }
            let oldCut = try archive()
            func total(_ cut: Int64) throws -> Int64 {
                var sum: Int64 = 0
                for row in try store.rows("SELECT payload FROM archive_day WHERE context_id=? AND revision_id=?", [.text(context), .integer(cut)]) {
                    let day = try JSONDecoder().decode(UsageArchivedDay.self, from: Data(row[0].text!.utf8))
                    sum += day.dimensions.values.reduce(0) { $0 + $1.tokens.totalTokens }
                }
                return sum
            }
            try check(total(oldCut) == 175)
            // Removing only the parent metadata must retire the old dependency in the same generation.
            try store.recordMetadata(source: "child", metadata: UsageSourceMetadata(model: nil, project: "fixture", parentLogicalID: nil), now: now)
            revision = try store.scalar("SELECT max(id) FROM revision")!
            try project("child")
            try check(total(archive()) == 350)
            // Rewrite both sources to empty; the new complete projections must remove old day rows.
            for source in ["parent", "child"] {
                try store.recordMetadata(source: source, metadata: UsageSourceMetadata(model: nil, project: "fixture", parentLogicalID: nil), now: now)
                let empty = try store.beginGeneration(source: source, identity: source + "-new", targetEnd: 0, initialState: "{}", now: now)
                try store.activate(source: source, expected: empty, verifiedIdentity: source + "-new", now: now)
                try store.observeSource(source: source, identity: source + "-new", targetEnd: 0, status: "readable", now: now)
            }
            revision = try store.scalar("SELECT max(id) FROM revision")!
            try project("parent"); try project("child")
            let newCut = try archive()
            try check(total(newCut) == 0 && total(oldCut) == 175)
            print("history archive: resumable fork prefix, parent watermarks, day projection, fixed-cut archive and empty replacement passed")
            return true
        } catch {
            print("history archive failed: \(error)")
            return false
        }
    }
}

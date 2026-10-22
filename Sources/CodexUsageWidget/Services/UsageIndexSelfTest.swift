import Foundation

enum UsageIndexSelfTest {
    static func run() -> Bool {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/history-index/codex-counters.jsonl")
        do {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            var state = CodexTokenCounterState()
            var deltas: [TokenBreakdown] = []
            for line in lines {
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                let payload = object["payload"] as! [String: Any]
                let info = payload["info"] as! [String: Any]
                let usage = info["total_token_usage"] as! [String: Any]
                func value(_ key: String) -> Int64? { (usage[key] as? NSNumber)?.int64Value }
                let sample = CodexTokenCounterSample(inputTokens: value("input_tokens"),
                    cachedInputTokens: value("cached_input_tokens"), outputTokens: value("output_tokens"),
                    reasoningOutputTokens: nil, totalTokens: value("total_tokens"))
                if let delta = CodexTokenCounterNormalizer.consume(cumulative: sample, lastUsage: nil, state: &state) {
                    deltas.append(delta)
                }
            }
            guard deltas.map(\.totalTokens) == [100, 45, 15, 15],
                  deltas.map(\.inputTokens) == [80, 40, 10, 10],
                  deltas.map(\.cachedInputTokens) == [50, 20, 2, 2],
                  deltas.map(\.outputTokens) == [20, 5, 5, 5] else {
                print("history oracle: counter fixture mismatch")
                return false
            }
            print("history oracle: fixed counter fixture passed")
            return storeTests() && UsageStreamParserSelfTest.run() && UsageIndexTransactionSelfTest.run() && UsageSourceDiscoverySelfTest.run() && UsageIndexWorkerSelfTest.run() && UsageArchiveSelfTest.run() && UsageClaudeIndexSelfTest.run() && UsageClaudeOwnershipSelfTest.run() && UsagePipelineSelfTest.run() && UsageIndexedReportsSelfTest.run() && UsageHistoryServiceSelfTest.run() && UsageLargeJSONSelfTest.run()
        } catch {
            print("history oracle: fixture unavailable (run from repository root)")
            return false
        }
    }
    private static func storeTests() -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ value: Bool) throws { if !value { throw UsageIndexError.databaseFailure } }
        do {
            var store: UsageIndexStore? = try UsageIndexStore(directory: root)
            try check(store!.scalar("SELECT count(*) FROM sqlite_master WHERE type='table'") == 24)
            do { _ = try UsageIndexStore(directory: root); return false } catch UsageIndexError.indexBusy {}
            do {
                try store!.transaction {
                    _ = try store!.allocateRevision(now: Date())
                    throw UsageIndexError.cancelled
                }
            } catch UsageIndexError.cancelled {}
            try check(store!.scalar("SELECT count(*) FROM revision") == 0)
            try store!.transaction { _ = try store!.allocateRevision(now: Date()) }
            try check(store!.scalar("SELECT count(*) FROM revision") == 1)
            do {
                try store!.withDeadline(milliseconds: 0) { try store!.execute("SELECT 1") }
                return false
            } catch UsageIndexError.cancelled {}
            do {
                _ = try store!.rows("SELECT 1 UNION ALL SELECT 2", limit: 1)
                return false
            } catch UsageIndexError.resourceLimited {}
            do {
                _ = try store!.rows("SELECT 'large'", maximumBytes: 4)
                return false
            } catch UsageIndexError.resourceLimited {}
            try store!.checkpointWAL()
            for name in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm", "writer.lock"] {
                let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)
                try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            }
            store = nil
            store = try UsageIndexStore(directory: root)
            try check(store!.scalar("SELECT count(*) FROM revision") == 1)
            let now = Date()
            for (id, locator) in [("compressed", "one.jsonl.zst"), ("reserved", "two.jsonl.zst"), ("live", "live.jsonl")] {
                _ = try store!.registerSource(id: id, root: "fixture", runtime: "codex",
                    logicalID: id, locator: locator, now: now)
                try store!.enqueueSource(id, priority: 1, now: now.addingTimeInterval(id == "live" ? -2 : -1))
            }
            // Live work can interrupt a compressed continuation without borrowing another slot's mirror.
            try store!.execute("UPDATE index_meta SET value='0' WHERE key='scheduler-step'")
            guard let live = try store!.claimJob(now: now, continuing: "compressed") else {
                throw UsageIndexError.databaseFailure
            }
            try check(live.source == "live")
            try store!.finishJob(live, more: false, now: now)
            guard let continuation = try store!.claimJob(now: now, continuing: "compressed", excluding: "reserved") else {
                throw UsageIndexError.databaseFailure
            }
            try check(continuation.source == "compressed")
            try store!.finishJob(continuation, more: true, now: now)
            try check(store!.claimJob(now: now, continuing: "compressed", excluding: "compressed") == nil)
            // A slot without a mirror may still claim an unreserved compressed source.
            guard let other = try store!.claimJob(now: now, excluding: "compressed") else {
                throw UsageIndexError.databaseFailure
            }
            try check(other.source == "reserved")
            try store!.finishJob(other, more: false, now: now)
            try store!.execute("UPDATE job SET priority=2 WHERE source_id='compressed'")
            try store!.enqueueSource("live", priority: 1, now: now)
            try store!.execute("UPDATE index_meta SET value='0' WHERE key='scheduler-step'")
            try check(store!.claimJob(now: now, avoiding: "live", continuing: "compressed")?.source == "live")
            try store!.execute("PRAGMA user_version=999")
            store = nil
            do { _ = try UsageIndexStore(directory: root); return false } catch UsageIndexError.unsupportedSchema {}
            print("history store: schema, lock, rollback, durability, cancellation, bounds, permissions, future-version protection passed")
            return true
        } catch {
            print("history store failed: \(error)")
            return false
        }
    }

}

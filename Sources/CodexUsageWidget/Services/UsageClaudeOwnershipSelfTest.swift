import Foundation

enum UsageClaudeOwnershipSelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try UsageIndexStore(directory: directory)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            func register(_ source: String, path: String) throws {
                try store.registerSource(id: source, root: "test", runtime: "claude-code", logicalID: source, locator: path, now: now)
                let start = try store.beginGeneration(source: source, identity: source, targetEnd: 1, initialState: "{}", now: now)
                let delta = ClaudeUsageDelta(messageId: "shared", date: now,
                    tokens: TokenBreakdown(inputTokens: 10, cachedInputTokens: 0, outputTokens: 2, reasoningOutputTokens: 0, totalTokens: 12),
                    model: "claude-sonnet-4", projectPath: "fixture", sessionId: source)
                let next = try store.append(source: source, expected: start, offset: 1, state: "{}",
                    facts: [UsageIndexFact(logicalKey: "message:shared", occurredAt: now, payload: .claudeToken(delta))], now: now)
                try store.activate(source: source, expected: next, verifiedIdentity: source, now: now)
                try store.enqueueClaudeOwnership(source: source, now: now)
            }
            func reconcile() throws {
                var rounds = 0
                while try store.stepClaudeOwnership(now: now, changed: { _ in }) {
                    rounds += 1
                    if rounds > 20 { throw UsageIndexError.databaseFailure }
                }
            }
            try register("b", path: "/b"); try reconcile()
            let first = try store.scalar("SELECT max(id) FROM revision")!
            guard try store.claudeOwnsMessage(source: "b", key: "message:shared", revision: first) else { throw UsageIndexError.databaseFailure }
            try register("a", path: "/a"); try reconcile()
            let second = try store.scalar("SELECT max(id) FROM revision")!
            guard try store.claudeOwnsMessage(source: "a", key: "message:shared", revision: second),
                  try !store.claudeOwnsMessage(source: "b", key: "message:shared", revision: second),
                  try store.claudeOwnsMessage(source: "b", key: "message:shared", revision: first),
                  try store.claudeOwnershipRevision(source: "b", at: second) > first else { throw UsageIndexError.databaseFailure }
            // A tombstone must release ownership without resurrecting the earlier upsert.
            let old = try store.checkpoint(source: "a")!
            let payload = ClaudeUsageDelta(messageId: "shared", date: now, tokens: .zero, model: nil, projectPath: "", sessionId: "a")
            _ = try store.append(source: "a", expected: old, offset: old.offset, state: old.state,
                facts: [UsageIndexFact(logicalKey: "message:shared", occurredAt: now, payload: .claudeToken(payload), deleted: true)], now: now)
            try store.enqueueClaudeOwnership(source: "a", now: now); try reconcile()
            guard try store.claudeOwnsMessage(source: "b", key: "message:shared", revision: Int64.max) else { throw UsageIndexError.databaseFailure }
            let empty = try store.beginGeneration(source: "a", identity: "a2", targetEnd: 0, initialState: "{}", now: now)
            try store.activate(source: "a", expected: empty, verifiedIdentity: "a2", now: now)
            try store.enqueueClaudeOwnership(source: "a", now: now); try reconcile()
            let third = try store.scalar("SELECT max(id) FROM revision")!
            guard try store.claudeOwnsMessage(source: "b", key: "message:shared", revision: third),
                  try store.claudeOwnsMessage(source: "a", key: "message:shared", revision: second) else { throw UsageIndexError.databaseFailure }
            let beforeGC = try store.claudeOwnershipRevision(source: "a", at: Int64.max)
            try store.collectVersionGarbage(now: now.addingTimeInterval(7200))
            guard try store.claudeOwnershipRevision(source: "a", at: Int64.max) == beforeGC else { throw UsageIndexError.databaseFailure }
            _ = try store.collectGarbage(now: now.addingTimeInterval(7200))
            guard try store.scalar("SELECT count(*) FROM fact WHERE source_id='a' AND generation=?",[.integer(old.generation)]) == 0,
                  try store.claudeOwnershipRevision(source:"a",at:Int64.max) == beforeGC else { throw UsageIndexError.databaseFailure }
            print("history Claude ownership: deterministic cross-file dedup, late source, empty replacement and fixed-cut owners passed")
            return true
        } catch {
            print("history Claude ownership failed: \(error)")
            return false
        }
    }
}

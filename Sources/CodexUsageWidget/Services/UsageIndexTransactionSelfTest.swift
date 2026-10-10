import Foundation

enum UsageIndexTransactionSelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func check(_ value: Bool) throws { if !value { throw UsageIndexError.databaseFailure } }
        do {
            let store = try UsageIndexStore(directory: directory)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            try store.registerSource(id: "s", root: "fixture", runtime: "codex", logicalID: "s", locator: "/fixture", now: now)
            let start = try store.beginGeneration(source: "s", identity: "inode-a", targetEnd: 10, initialState: "{}", now: now)
            let fact = UsageIndexFact(logicalKey: "tool-1", occurredAt: now, payload: .tool(name: "test", count: 1))
            let first = try store.append(source: "s", expected: start, offset: 5, state: "{}", facts: [fact], now: now)
            try check(store.factsAt(source: "s", kind: "tool", revision: first.revision).isEmpty)
            do {
                _ = try store.activate(source: "s", expected: first, verifiedIdentity: "inode-a", now: now)
                return false
            } catch UsageIndexError.sourceChanged {}
            do {
                _ = try store.append(source: "s", expected: start, offset: 5, state: "{}", facts: [fact], now: now)
                return false
            } catch UsageIndexError.sourceChanged {}
            try check(store.scalar("SELECT count(*) FROM fact") == 1)
            let complete = try store.append(source: "s", expected: first, offset: 10, state: "{}", facts: [], now: now)
            let published = try store.activate(source: "s", expected: complete, verifiedIdentity: "inode-a", now: now)
            try check(store.factsAt(source: "s", kind: "tool", revision: published).count == 1)
            var removed = fact; removed.deleted = true
            let tombstone = try store.append(source: "s", expected: complete, offset: 10, state: "{}", facts: [removed], now: now)
            try check(store.factsAt(source: "s", kind: "tool", revision: published).first?[1].text == "upsert")
            try check(store.factsAt(source: "s", kind: "tool", revision: tombstone.revision).first?[1].text == "delete")
            let empty = try store.beginGeneration(source: "s", identity: "inode-b", targetEnd: 0, initialState: "{}", now: now)
            let replaced = try store.activate(source: "s", expected: empty, verifiedIdentity: "inode-b", now: now)
            try check(store.factsAt(source: "s", kind: "tool", revision: replaced).isEmpty)
            try check(store.factsAt(source: "s", kind: "tool", revision: published).count == 1)
            let appended = try store.observeAppend(source: "s", expected: empty, targetEnd: 5, verifiedIdentity: "inode-b", now: now)
            let next = try store.append(source: "s", expected: appended, offset: 5, state: "{}", facts: [fact], now: now)
            try check(next.generation == empty.generation)
            try check(store.factsAt(source: "s", kind: "tool", revision: next.revision).count == 1)
            let stale = try store.beginGeneration(source: "s", identity: "old", targetEnd: 0, initialState: "{}", now: now)
            let newest = try store.beginGeneration(source: "s", identity: "new", targetEnd: 0, initialState: "{}", now: now)
            _ = try store.activate(source: "s", expected: newest, verifiedIdentity: "new", now: now)
            do { _ = try store.activate(source: "s", expected: stale, verifiedIdentity: "old", now: now); return false }
            catch UsageIndexError.sourceChanged {}
            let invalid = UsageIndexFact(logicalKey: "", occurredAt: now, payload: .tool(name: "test", count: 1))
            do { _ = try store.append(source: "s", expected: newest, offset: 0, state: "{}", facts: [invalid], now: now); return false }
            catch UsageIndexError.resourceLimited {}
            for seconds in [Double.infinity, Double.nan, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
                do { _ = try usageIndexMilliseconds(Date(timeIntervalSince1970: seconds)); return false }
                catch UsageIndexError.resourceLimited {}
            }
            print("history transactions: staging isolation, CAS retry, partial rejection, as-of tombstones, empty replacement passed")
            return true
        } catch {
            print("history transactions failed: \(error)")
            return false
        }
    }
}

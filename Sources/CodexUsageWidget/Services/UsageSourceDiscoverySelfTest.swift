import Foundation

enum UsageSourceDiscoverySelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try UsageIndexStore(directory: directory)
            try store.execute("CREATE TABLE threads(id TEXT PRIMARY KEY,rollout_path TEXT,model TEXT,cwd TEXT,updated_at INTEGER)")
            try store.transaction {
                for index in 0..<1025 {
                    try store.execute("INSERT INTO threads VALUES (?,?,?, ?,?)", [
                        .text(String(format: "%06d", index)), .text("/synthetic/\(index).jsonl"),
                        .text("test-model"), .text("/synthetic"), .integer(Int64(index))])
                }
            }
            var seen = Set<String>()
            var largestPage = 0
            var pages = 0
            var oldSnapshotValueObserved = false
            let result = try UsageSourceDiscovery.codex(databaseURL: directory.appendingPathComponent("index.sqlite")) { values in
                largestPage = max(largestPage, values.count)
                pages += 1
                if pages == 1 { try store.execute("UPDATE threads SET updated_at=-1 WHERE id='001024'") }
                for value in values {
                    guard seen.insert(value.logicalID).inserted else { throw UsageIndexError.databaseFailure }
                    if value.logicalID == "001024" { oldSnapshotValueObserved = value.updatedAt == 1024 }
                }
            }
            guard result.complete, result.sources == 1025, seen.count == 1025,
                  largestPage == 256, pages == 5, oldSnapshotValueObserved else { return false }
            let expired = try UsageSourceDiscovery.codex(databaseURL: directory.appendingPathComponent("index.sqlite"), deadlineSeconds: 0) { _ in }
            guard !expired.complete, expired.sources == 0 else { return false }
            print("history discovery: 1025 sources, bounded pages, fixed read snapshot, timeout coverage passed")
            return true
        } catch {
            print("history discovery failed: \(error)")
            return false
        }
    }
}

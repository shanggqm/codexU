import Foundation

enum UsageClaudeIndexSelfTest {
    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("fixture.jsonl")
            let lines = [
                #"{"timestamp":"2026-09-18T10:00:00Z","cwd":"/fixture","message":{"id":"m1","model":"claude-sonnet-4","usage":{"input_tokens":1,"cache_creation_input_tokens":4,"cache_read_input_tokens":5,"output_tokens":2},"content":[{"type":"tool_use","name":"Skill"}]}}"#,
                #"{"timestamp":"2026-09-18T10:00:01Z","message":{"id":"m1","usage":{"input_tokens":99},"content":[{"type":"tool_use","name":"Skill"}]}}"#,
                #"{"timestamp":"2026-09-18T10:00:02Z","message":{"id":"m2","usage":{"input_tokens":15,"output_tokens":5}}}"#
            ]
            let bytes = Data((lines.joined(separator: "\n") + "\n").utf8)
            try bytes.write(to: url)
            var checkpoint = ClaudeIndexCheckpoint()
            var deltas: [ClaudeUsageDelta] = [], skills: [ClaudeSkillLoad] = []
            var calls: [String: Int] = [:]
            repeat {
                let batch = try ClaudeIncrementalAdapter.read(url: url, targetEnd: UInt64(bytes.count), checkpoint: checkpoint,
                    modificationDate: Date(timeIntervalSince1970: 0), maximumLines: 1)
                checkpoint = try JSONDecoder().decode(ClaudeIndexCheckpoint.self, from: JSONEncoder().encode(batch.checkpoint))
                deltas += batch.deltas; skills += batch.skills
                for (name, count) in batch.tools { calls[name, default: 0] += count }
            } while checkpoint.cursor.offset < bytes.count
            guard let oracle = claudeHistoryIndexOracle(url: url) else { throw UsageIndexError.cacheInvalid }
            var seen = Set<String>()
            let unique = deltas.filter { delta in delta.messageId.map { seen.insert($0).inserted } ?? true }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(unique) == encoder.encode(oracle.deltas),
                      try encoder.encode(skills) == encoder.encode(oracle.skills), calls == oracle.tools else { throw UsageIndexError.databaseFailure }
            let helper = UsageParseHelper()
            let parsed = try helper.parse(UsageParseRequest(id: UUID().uuidString, path: url.path, targetEnd: UInt64(bytes.count),
                checkpoint: CodexIndexCheckpoint(), previousStamp: nil, runtime: "claude-code", claudeCheckpoint: ClaudeIndexCheckpoint()))
            guard let batch = parsed.claude, batch.deltas.count == 3, batch.tools["Skill"] == 2 else { throw UsageIndexError.databaseFailure }
            print("history Claude: checkpoint continuation, old-reader parity, pre-dedup tools/skills and isolated helper passed")
            return true
        } catch {
            print("history Claude failed: \(error)")
            return false
        }
    }
}

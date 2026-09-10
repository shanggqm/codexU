import Foundation

// Standalone harness: the production context also contains unrelated UI preferences.
struct RuntimeLoadContext {
    let now: Date
    let homeDirectory: URL
    let cacheDirectory: URL
}

@main
struct RemoteUsageTests {
    static func main() throws {
        typealias Reader = RemoteUsageReader
        let host = Reader.Host(name: "dev", sshHost: "dev-alias", codexHome: "/srv/a'b/.codex")
        try Reader.validate(.init(hosts: [host]))
        precondition(Reader.shellQuote("a'b") == "'a'\\''b'")
        for value in ["-oProxyCommand=bad", "host;bad", "$(bad)", "host\nbad"] {
            do {
                try Reader.validate(.init(hosts: [.init(name: "dev", sshHost: value, codexHome: nil)]))
                fatalError("unsafe SSH destination accepted")
            } catch {}
        }
        do {
            try Reader.validate(.init(hosts: [host, host]))
            fatalError("duplicate sources accepted")
        } catch {}
        func row(_ id: String, _ tokens: Int64, _ time: Double, _ path: String) -> Reader.Row {
            .init(id: id, tokens: tokens, updatedAt: time, model: "gpt-5.5", cwd: "/project",
                  rollout: path, title: "test", archived: 0)
        }
        let local = row("same-id", 100, 100, "/local.jsonl")
        let copy = row("same-id", 100, 100, "/copy.jsonl")
        let newer = row("same-id", 200, 110, "/remote.jsonl")
        let merged = Reader.merge([local, copy, newer, row("other", 50, 120, "/other.jsonl")])
        precondition(merged.count == 2 && merged.reduce(0) { $0 + $1.tokens } == 250)
        precondition(Reader.merge([local, copy]).first?.rollout == "/local.jsonl")
        precondition(Reader.merge([newer, local]).first?.rollout == "/remote.jsonl")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = directory.appendingPathComponent("usage.sqlite")
        try Reader.writeDatabase(rows: merged, to: db)
        let read = try Reader.localRows(db.path)
        precondition(read.count == 2 && read.reduce(0) { $0 + $1.tokens } == 250)
        let context = RuntimeLoadContext(now: Date(), homeDirectory: directory, cacheDirectory: directory)
        var messages: [String] = []
        precondition(Reader().database(localPath: db.path, context: context, messages: &messages) == nil)
        precondition(messages.isEmpty, "disabled mode must not contact SSH or add warnings")
        let invalid = Data(#"{"version":2,"collectedAt":1,"missingRollouts":0,"threads":[]}"#.utf8)
        do { _ = try Reader.decode(invalid); fatalError("unsupported version accepted") } catch {}
        let configurationDirectory = directory.appendingPathComponent(".config/codexU")
        try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Reader.Configuration(hosts: [host]))
            .write(to: configurationDirectory.appendingPathComponent("remote-hosts.json"))
        let timestamp = Date().timeIntervalSince1970
        let event: [String: Any] = ["type": "event_msg", "timestamp": "2026-09-01T12:00:00Z",
                                   "payload": ["type": "token_count", "info": [
                                    "total_token_usage": ["input_tokens": 300, "total_tokens": 300]]]]
        var snapshot: [String: Any] = ["version": 1, "collectedAt": timestamp, "missingRollouts": 0,
            "threads": [["id": "remote-only", "tokens": 300, "updatedAt": timestamp,
                         "model": "gpt-5.5", "cwd": "/project", "events": [event]]]]
        let valid = try JSONSerialization.data(withJSONObject: snapshot)
        _ = try Reader.decode(valid)
        var requests = 0
        var shouldFail = false
        let reader = Reader(transport: { _, _ in
            requests += 1
            if shouldFail { throw Reader.Failure.process }
            return valid
        })
        func load(at offset: Double) throws -> [Reader.Row]? {
            messages = []
            let next = RuntimeLoadContext(now: Date(timeIntervalSince1970: timestamp + offset),
                                          homeDirectory: directory, cacheDirectory: directory)
            guard let result = reader.database(localPath: db.path, context: next, messages: &messages) else { return nil }
            defer { try? FileManager.default.removeItem(at: result) }
            return try Reader.localRows(result.path)
        }
        let combined = try load(at: 0)!
        precondition(combined.count == 3 && combined.reduce(0) { $0 + $1.tokens } == 550)
        precondition(combined.contains { $0.cwd == "ssh:dev:/project" })
        _ = try load(at: 100)
        precondition(requests == 1, "refresh interval must survive repeated reads")
        shouldFail = true
        let stale = try load(at: 301)
        precondition(stale != nil)
        precondition(messages.contains { $0.contains("cached; last collected") })
        _ = try load(at: 302)
        precondition(requests == 2 && messages.contains { $0.contains("cached; last collected") })
        let expired = try load(at: 8 * 86400)
        precondition(expired == nil)
        precondition(messages.contains { $0.contains("unavailable") })
        let unchanged = try Reader.localRows(db.path)
        precondition(unchanged.count == 2, "live database must remain unchanged")
        snapshot["privatePrompt"] = "must not be cached"
        do { _ = try Reader.decode(JSONSerialization.data(withJSONObject: snapshot)); fatalError("unexpected field accepted") } catch {}
        let fakeSSH = directory.appendingPathComponent("fake-ssh")
        try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: fakeSSH)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeSSH.path)
        let script = directory.appendingPathComponent("collector.py")
        try Data("print('fixture')\n".utf8).write(to: script)
        let start = Date()
        do {
            _ = try Reader.runSSH(host: host, script: script, directory: directory,
                                  executable: fakeSSH, timeout: 0.1)
            fatalError("timeout must fail")
        } catch {}
        precondition(Date().timeIntervalSince(start) < 3, "timed-out process must be reaped promptly")
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("download.tmp").path))
        print("Remote usage Swift tests passed")
    }
}

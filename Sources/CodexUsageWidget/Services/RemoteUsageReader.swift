import Foundation
import CryptoKit
import SQLite3

/// Optional SSH sources feed an isolated usage database, never the live Codex database.
/// This reader is confined to CodexUsageReader's serial loading queue.
final class RemoteUsageReader {
    struct Host: Codable {
        let name: String
        let sshHost: String
        let codexHome: String?

        var key: String {
            SHA256.hash(data: Data("\(sshHost)\n\(codexHome ?? "")".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Configuration: Codable { let hosts: [Host] }
    struct Snapshot: Decodable {
        let version: Int
        let collectedAt: Double
        let missingRollouts: Int
        let threads: [ThreadRecord]
    }
    struct ThreadRecord: Decodable {
        let id: String
        let tokens: Int64
        let updatedAt: Double
        let model: String?
        let cwd: String
        // Event dictionaries are decoded separately after envelope validation.
    }
    struct Row {
        let id: String
        let tokens: Int64
        let updatedAt: Double
        let model: String?
        let cwd: String
        let rollout: String
        let title: String
        let archived: Int
    }
    enum Failure: Error { case configuration, snapshot, process, database }

    static let maximumBytes = 32 * 1_024 * 1_024
    private var lastAttempts: [String: Date] = [:]
    private var failedHosts: Set<String> = []
    private(set) var includedSourceNames: [String] = []
    private let fileManager = FileManager.default
    private let transport: ((Host, URL) throws -> Data)?

    init(transport: ((Host, URL) throws -> Data)? = nil) {
        self.transport = transport
    }

    static func validate(_ config: Configuration) throws {
        guard config.hosts.count <= 4,
              Set(config.hosts.map(\.key)).count == config.hosts.count,
              Set(config.hosts.map(\.name)).count == config.hosts.count else { throw Failure.configuration }
        for host in config.hosts {
            guard host.name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$"#, options: .regularExpression) != nil,
                  host.sshHost.range(of: #"^[A-Za-z0-9][A-Za-z0-9._@-]{0,199}$"#, options: .regularExpression) != nil,
                  host.codexHome.map({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains("\n") && !$0.contains("\0") }) ?? true
            else { throw Failure.configuration }
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Returns nil when disabled or unavailable. The caller removes the temporary database.
    func database(localPath: String?, context: RuntimeLoadContext, messages: inout [String]) -> URL? {
        includedSourceNames = []
        let configURL = context.homeDirectory.appendingPathComponent(".config/codexU/remote-hosts.json")
        guard fileManager.fileExists(atPath: configURL.path) else { return nil }
        let config: Configuration
        do {
            guard let size = try configURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 64 * 1024 else { throw Failure.configuration }
            config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
            try Self.validate(config)
        } catch {
            messages.append("SSH usage: invalid remote-hosts.json; using local data only.")
            return nil
        }
        guard !config.hosts.isEmpty else { return nil }
        let root = context.cacheDirectory.appendingPathComponent("remote-usage", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            let activeKeys = Set(config.hosts.map(\.key))
            lastAttempts = lastAttempts.filter { activeKeys.contains($0.key) }
            failedHosts.formIntersection(activeKeys)
            for child in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if !activeKeys.contains(child.lastPathComponent) { try? fileManager.removeItem(at: child) }
            }
            var rows = try localPath.map(Self.localRows) ?? []
            var included = 0
            var sourceNames: [String] = []
            for host in config.hosts {
                let directory = root.appendingPathComponent(host.key, isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
                let cache = directory.appendingPathComponent("snapshot.json")
                if lastAttempts[host.key].map({ context.now.timeIntervalSince($0) >= 300 }) ?? true {
                    lastAttempts[host.key] = context.now
                    do {
                        let data = try transport.map { try $0(host, directory) } ?? fetch(host: host, directory: directory)
                        let decoded = try Self.decode(data)
                        let age = context.now.timeIntervalSince1970 - decoded.collectedAt
                        guard age >= -300, age <= 600 else { throw Failure.snapshot }
                        try data.write(to: cache, options: .atomic)
                        failedHosts.remove(host.key)
                    } catch { failedHosts.insert(host.key) }
                }
                do {
                    guard let size = try cache.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size <= Self.maximumBytes else { throw Failure.snapshot }
                    let data = try Data(contentsOf: cache)
                    let snapshot = try Self.decode(data)
                    let age = context.now.timeIntervalSince1970 - snapshot.collectedAt
                    guard age >= -300, age <= 7 * 86400 else { throw Failure.snapshot }
                    rows += try materialize(data: data, snapshot: snapshot, host: host, directory: directory)
                    included += 1
                    sourceNames.append(host.name)
                    let freshness = failedHosts.contains(host.key) || age >= 600 ? "cached; last collected" : "collected"
                    let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: snapshot.collectedAt))
                    messages.append("SSH usage [\(host.name)]: \(freshness) \(date).")
                    if snapshot.missingRollouts > 0 {
                        messages.append("SSH usage [\(host.name)]: \(snapshot.missingRollouts) missing session logs; detailed coverage is incomplete.")
                    }
                } catch {
                    messages.append("SSH usage [\(host.name)]: unavailable (SSH, Python 3, database, or cache); excluded from totals.")
                }
            }
            guard included > 0 else { return nil }
            let merged = Self.merge(rows)
            let db = root.appendingPathComponent("usage-\(UUID().uuidString).sqlite")
            do { try Self.writeDatabase(rows: merged, to: db) }
            catch { try? fileManager.removeItem(at: db); throw error }
            includedSourceNames = sourceNames
            messages.append("Token totals and trends include local + \(included) SSH source(s). Tasks, tools, skills and inference performance remain local.")
            return db
        } catch {
            messages.append("SSH usage: could not prepare usage cache; using local data only.")
            return nil
        }
    }

    static func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= maximumBytes else { throw Failure.snapshot }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1, snapshot.collectedAt.isFinite,
              snapshot.missingRollouts >= 0, snapshot.threads.count <= 20_000,
              Set(snapshot.threads.map(\.id)).count == snapshot.threads.count,
              snapshot.threads.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 4096 &&
                  $0.tokens >= 0 && $0.tokens <= 1_000_000_000_000 &&
                  $0.updatedAt.isFinite && $0.updatedAt >= 0 && $0.updatedAt <= 32_503_680_000_000 &&
                  $0.cwd.utf8.count <= 4096 && ($0.model?.utf8.count ?? 0) <= 4096 })
        else { throw Failure.snapshot }
        // Validate the full allowlist before caching, including responses from an
        // unexpected remote command or a modified on-disk snapshot.
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(envelope.keys) == ["version", "collectedAt", "missingRollouts", "threads"],
              let objects = envelope["threads"] as? [[String: Any]] else { throw Failure.snapshot }
        for object in objects {
            guard Set(object.keys) == ["id", "tokens", "updatedAt", "model", "cwd", "events"],
                  let events = object["events"] as? [[String: Any]] else { throw Failure.snapshot }
            for event in events { try validateEvent(event) }
        }
        return snapshot
    }

    private static func validateEvent(_ event: [String: Any]) throws {
        guard Set(event.keys) == ["type", "timestamp", "payload"],
              let kind = event["type"] as? String,
              let payload = event["payload"] as? [String: Any],
              optionalText(event["timestamp"]) else { throw Failure.snapshot }
        switch kind {
        case "session_meta":
            guard Set(payload.keys) == ["forked_from_id"], optionalText(payload["forked_from_id"]) else { throw Failure.snapshot }
        case "turn_context":
            guard Set(payload.keys) == ["model"], optionalText(payload["model"]) else { throw Failure.snapshot }
        case "event_msg":
            if payload["type"] as? String == "thread_settings_applied" {
                guard Set(payload.keys) == ["type", "thread_settings"],
                      let settings = payload["thread_settings"] as? [String: Any],
                      Set(settings.keys) == ["service_tier"], optionalText(settings["service_tier"]) else { throw Failure.snapshot }
            } else {
                guard payload["type"] as? String == "token_count", Set(payload.keys) == ["type", "info"],
                      let info = payload["info"] as? [String: Any],
                      Set(info.keys).isSubset(of: ["total_token_usage", "last_token_usage"]) else { throw Failure.snapshot }
                let counters: Set<String> = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens",
                                             "output_tokens", "reasoning_output_tokens", "total_tokens"]
                for value in info.values {
                    guard let usage = value as? [String: Any], Set(usage.keys).isSubset(of: counters),
                          usage.values.allSatisfy({ value in
                              guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
                              return n.doubleValue >= 0 && n.doubleValue <= 1_000_000_000_000 && n.doubleValue.rounded() == n.doubleValue
                          }) else { throw Failure.snapshot }
                }
            }
        default: throw Failure.snapshot
        }
    }

    private static func optionalText(_ value: Any?) -> Bool {
        value is NSNull || (value as? String).map { $0.utf8.count <= 4096 } == true
    }

    private func materialize(data: Data, snapshot: Snapshot, host: Host, directory: URL) throws -> [Row] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objects = object["threads"] as? [[String: Any]], objects.count == snapshot.threads.count
        else { throw Failure.snapshot }
        var rows: [Row] = []
        var retained: Set<String> = ["snapshot.json"]
        for (thread, object) in zip(snapshot.threads, objects) {
            guard let events = object["events"] as? [[String: Any]] else { throw Failure.snapshot }
            let filename = SHA256.hash(data: Data(thread.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".jsonl"
            retained.insert(filename)
            let url = directory.appendingPathComponent(filename)
            var lines = Data()
            for event in events {
                lines.append(try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys, .withoutEscapingSlashes]))
                lines.append(10)
            }
            // Preserve modification time so the existing analytics cache remains useful.
            if (try? Data(contentsOf: url)) != lines { try lines.write(to: url, options: .atomic) }
            rows.append(Row(id: thread.id, tokens: thread.tokens, updatedAt: thread.updatedAt,
                            model: thread.model, cwd: "ssh:\(host.name):\(thread.cwd)", rollout: url.path,
                            title: "SSH · \(host.name)", archived: 0))
        }
        for child in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if !retained.contains(child.lastPathComponent) { try? fileManager.removeItem(at: child) }
        }
        return rows
    }

    /// Synced/moved sessions retain their UUID. Count one complete copy, never sum copies.
    /// Prefer the higher cumulative counter, then newer metadata; retain local on exact ties.
    static func merge(_ rows: [Row]) -> [Row] {
        var result: [String: Row] = [:]
        for row in rows {
            if let current = result[row.id],
               current.tokens > row.tokens || (current.tokens == row.tokens && current.updatedAt >= row.updatedAt) {
                continue
            }
            result[row.id] = row
        }
        return result.values.sorted { $0.id < $1.id }
    }

    private func fetch(host: Host, directory: URL) throws -> Data {
        guard let script = Bundle.main.url(forResource: "remote-usage-collector", withExtension: "py") else {
            throw Failure.process
        }
        return try Self.runSSH(host: host, script: script, directory: directory)
    }

    static func runSSH(host: Host, script: URL, directory: URL,
                       executable: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
                       timeout: TimeInterval = 30) throws -> Data {
        let fileManager = FileManager.default
        let outputURL = directory.appendingPathComponent("download.tmp")
        fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? fileManager.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL)
        let input = try FileHandle(forReadingFrom: script)
        defer { try? output.close(); try? input.close() }
        let process = Process()
        process.executableURL = executable
        var command = "python3 -"
        if let home = host.codexHome { command += " " + Self.shellQuote(home) }
        process.arguments = ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                             "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5",
                             "-o", "ServerAliveCountMax=1", "-o", "ControlMaster=no",
                             "-o", "ControlPath=none", "-o", "ClearAllForwardings=yes",
                             "-o", "ForkAfterAuthentication=no", "-o", "PermitLocalCommand=no",
                             "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
                             host.sshHost, command]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if Date() >= deadline || size > Self.maximumBytes {
                process.terminate()
                let grace = Date().addingTimeInterval(1)
                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw Failure.process
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumBytes else { throw Failure.process }
        return try Data(contentsOf: outputURL)
    }

    static func localRows(_ path: String) throws -> [Row] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw Failure.database
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)
        var statement: OpaquePointer?
        let sql = "SELECT id,tokens_used,updated_at,model,cwd,rollout_path,title,archived FROM threads"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure.database }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        var rows: [Row] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard rows.count < 100_000 else { throw Failure.database }
            rows.append(Row(id: string(0), tokens: sqlite3_column_int64(statement, 1),
                            updatedAt: sqlite3_column_double(statement, 2), model: string(3), cwd: string(4),
                            rollout: string(5), title: string(6), archived: Int(sqlite3_column_int(statement, 7))))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw Failure.database }
        return rows
    }

    static func writeDatabase(rows: [Row], to url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw Failure.database
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE threads (id TEXT PRIMARY KEY,tokens_used INTEGER,updated_at REAL,model TEXT,cwd TEXT,rollout_path TEXT,title TEXT,archived INTEGER,recency_at REAL); BEGIN", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO threads VALUES (?,?,?,?,?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw Failure.database }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, row.id, -1, transient)
            sqlite3_bind_int64(statement, 2, row.tokens)
            sqlite3_bind_double(statement, 3, row.updatedAt)
            if let model = row.model { sqlite3_bind_text(statement, 4, model, -1, transient) }
            else { sqlite3_bind_null(statement, 4) }
            sqlite3_bind_text(statement, 5, row.cwd, -1, transient)
            sqlite3_bind_text(statement, 6, row.rollout, -1, transient)
            sqlite3_bind_text(statement, 7, row.title, -1, transient)
            sqlite3_bind_int(statement, 8, Int32(row.archived))
            sqlite3_bind_double(statement, 9, row.updatedAt)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.database }
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
    }
}

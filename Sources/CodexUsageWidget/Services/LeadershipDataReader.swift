import Darwin
import Foundation

final class LeadershipDataReader {
    private let fileManager = FileManager.default
    private let cacheVersion = 1
    private let maximumCacheEntries = 2_048
    private let maximumCacheBytes: Int64 = 64 * 1_024 * 1_024
    private let maximumSQLiteOutputBytes = 32 * 1_024 * 1_024
    private let maximumSQLiteReadChunkBytes = 64 * 1_024

    func load(context: RuntimeLoadContext) -> LeadershipDashboardSnapshot {
        let earliestDay = context.statistics.calendar.date(
            byAdding: .day,
            value: -34,
            to: context.statistics.calendar.startOfDay(for: context.now)
        ) ?? context.now.addingTimeInterval(-34 * 24 * 3600)
        var cache = readCache(context: context)
        var parsedSources: [LeadershipParsedSource] = []
        var liveCacheKeys = Set<String>()
        var cacheChanged = false

        for metadata in codexSourceMetadata(context: context, earliestDate: earliestDay) {
            let url = URL(fileURLWithPath: metadata.rolloutPath)
            guard let fingerprint = fingerprint(url) else { continue }
            let key = stableHash("codex:\(metadata.rolloutPath)")
            liveCacheKeys.insert(key)
            if let entry = cache.entries[key], entry.matches(fingerprint) {
                parsedSources.append(entry.source)
                continue
            }
            let source = parseCodexSource(metadata, url: url, now: context.now)
            parsedSources.append(source)
            cache.entries[key] = LeadershipCacheEntry(fingerprint: fingerprint, source: source)
            cacheChanged = true
        }

        for url in claudeTranscriptURLs(context: context, earliestDate: earliestDay) {
            guard let fingerprint = fingerprint(url) else { continue }
            let key = stableHash("claude:\(url.path)")
            liveCacheKeys.insert(key)
            if let entry = cache.entries[key], entry.matches(fingerprint) {
                parsedSources.append(entry.source)
                continue
            }
            let source = parseClaudeSource(url: url)
            parsedSources.append(source)
            cache.entries[key] = LeadershipCacheEntry(fingerprint: fingerprint, source: source)
            cacheChanged = true
        }

        if cache.entries.keys.contains(where: { !liveCacheKeys.contains($0) }) {
            cache.entries = cache.entries.filter { liveCacheKeys.contains($0.key) }
            cacheChanged = true
        }
        if cache.entries.count > maximumCacheEntries {
            let retained = cache.entries.sorted {
                $0.value.source.lastActivityAt > $1.value.source.lastActivityAt
            }.prefix(maximumCacheEntries)
            cache.entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
            cacheChanged = true
        }
        if cacheChanged {
            writeCache(cache, context: context)
        }

        let workers = deduplicatedWorkers(parsedSources.compactMap(\.worker))
        let intervalByID = Dictionary(
            parsedSources.flatMap(\.intervals).map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return LeadershipAggregator().makeDashboard(
            workers: workers,
            intervals: Array(intervalByID.values),
            now: context.now,
            calendar: context.statistics.calendar
        )
    }

    /// One-time recovery from the previous reader's source cache; never reads session logs.
    func restoreCached(data: Data, observedAt: Date, calendar: Calendar) -> LeadershipDashboardSnapshot? {
        guard data.count <= 2 * 1_024 * 1_024,
              let cache = try? JSONDecoder().decode(LeadershipSourceCache.self, from: data),
              cache.version == cacheVersion, !cache.entries.isEmpty, cache.entries.count < maximumCacheEntries else { return nil }
        let sources = cache.entries.sorted { $0.key < $1.key }.map { $0.value.source }
        let workers = deduplicatedWorkers(sources.compactMap(\.worker))
        let intervals = Dictionary(sources.flatMap(\.intervals).map { ($0.id, $0) },
                                   uniquingKeysWith: { existing, _ in existing })
        return LeadershipAggregator().makeDashboard(workers: workers, intervals: Array(intervals.values),
                                                    now: observedAt, calendar: calendar)
    }

    private func deduplicatedWorkers(_ workers: [LeadershipWorker]) -> [LeadershipWorker] {
        var byID: [String: LeadershipWorker] = [:]
        for worker in workers {
            if let existing = byID[worker.id], existing.parentID != nil {
                continue
            }
            byID[worker.id] = worker
        }
        return Array(byID.values)
    }

    // MARK: - Codex

    private struct CodexSourceMetadata {
        let threadID: String
        let rolloutPath: String
        let cwd: String
        let createdAt: Date
        let updatedAt: Date
        let source: String
        let parentID: String?
        let automationID: String?
    }

    private func codexSourceMetadata(
        context: RuntimeLoadContext,
        earliestDate: Date
    ) -> [CodexSourceMetadata] {
        let candidates = [
            context.homeDirectory.appendingPathComponent(".codex/state_5.sqlite").path,
            context.homeDirectory.appendingPathComponent(".codex/sqlite/state_5.sqlite").path
        ]
        guard let databasePath = candidates.first(where: fileManager.fileExists(atPath:)),
              let sqlitePath = leadershipFirstExecutablePath([
                "/usr/bin/sqlite3",
                "/opt/homebrew/bin/sqlite3"
              ])
        else { return [] }

        let threshold = Int(earliestDate.timeIntervalSince1970)
        let query = """
        SELECT
          t.id,
          t.rollout_path AS rolloutPath,
          t.cwd,
          t.created_at AS createdAt,
          t.updated_at AS updatedAt,
          COALESCE(t.thread_source, '') AS source,
          e.parent_thread_id AS parentID,
          CASE
            WHEN t.thread_source = 'automation'
              AND instr(t.title, 'Automation ID: ') > 0
            THEN substr(
              substr(t.title, instr(t.title, 'Automation ID: ') + 15),
              1,
              instr(substr(t.title, instr(t.title, 'Automation ID: ') + 15), char(10)) - 1
            )
            ELSE ''
          END AS automationID
        FROM threads t
        LEFT JOIN thread_spawn_edges e ON e.child_thread_id = t.id
        WHERE t.rollout_path <> ''
          AND t.updated_at >= \(threshold)
        ORDER BY t.updated_at DESC;
        """
        return runSQLiteJSON(sqlitePath: sqlitePath, databasePath: databasePath, query: query).compactMap { row in
            guard let threadID = row["id"] as? String,
                  let rolloutPath = row["rolloutPath"] as? String,
                  let createdAt = numericValue(row["createdAt"]).map(Date.init(timeIntervalSince1970:)),
                  let updatedAt = numericValue(row["updatedAt"]).map(Date.init(timeIntervalSince1970:))
            else { return nil }
            let automationID = (row["automationID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CodexSourceMetadata(
                threadID: threadID,
                rolloutPath: rolloutPath,
                cwd: row["cwd"] as? String ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt,
                source: row["source"] as? String ?? "",
                parentID: row["parentID"] as? String,
                automationID: automationID.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    private func parseCodexSource(
        _ metadata: CodexSourceMetadata,
        url: URL,
        now: Date
    ) -> LeadershipParsedSource {
        let kind: LeadershipWorkerKind
        switch metadata.source.lowercased() {
        case "subagent": kind = .subagent
        case "automation": kind = .automation
        default: kind = .main
        }
        let workerID: String
        if kind == .automation, let automationID = metadata.automationID {
            workerID = "codex:automation:\(automationID)"
        } else {
            workerID = "codex:\(kind.rawValue):\(metadata.threadID)"
        }
        let project = projectIdentity(runtime: .codex, path: metadata.cwd)
        let parentID = metadata.parentID.map { "codex:main:\($0)" }
        let worker = LeadershipWorker(
            id: workerID,
            runtime: .codex,
            kind: kind,
            projectID: project.id,
            projectName: project.name,
            parentID: parentID
        )

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return LeadershipParsedSource(worker: worker, intervals: [], lastActivityAt: metadata.updatedAt)
        }
        var starts: [String: Date] = [:]
        var intervals: [LeadershipInterval] = []
        text.enumerateLines { line, _ in
            guard line.contains("\"type\":\"event_msg\"") else { return }
            if line.contains("\"type\":\"task_started\"") {
                guard let turnID = jsonString(in: line, key: "turn_id"),
                      let startedAt = jsonNumber(in: line, key: "started_at")
                else { return }
                starts[turnID] = Date(timeIntervalSince1970: startedAt)
                return
            }
            guard line.contains("\"type\":\"task_complete\""),
                  let turnID = jsonString(in: line, key: "turn_id"),
                  let completedAt = jsonNumber(in: line, key: "completed_at")
            else { return }
            let end = Date(timeIntervalSince1970: completedAt)
            let duration = jsonNumber(in: line, key: "duration_ms").map { $0 / 1_000 }
            guard let start = starts[turnID] ?? duration.map({ end.addingTimeInterval(-$0) }),
                  start >= metadata.createdAt.addingTimeInterval(-2),
                  end <= now.addingTimeInterval(5),
                  end > start
            else { return }
            let quality: LeadershipEvidenceQuality = kind == .automation && metadata.automationID == nil
                ? .derived
                : .fact
            intervals.append(LeadershipInterval(
                id: "codex:\(metadata.threadID):\(turnID)",
                workerID: workerID,
                runtime: .codex,
                workerKind: kind,
                projectID: project.id,
                startAt: start,
                endAt: end,
                quality: quality,
                isAutonomous: kind == .subagent || kind == .automation
            ))
        }
        return LeadershipParsedSource(
            worker: worker,
            intervals: intervals,
            lastActivityAt: intervals.map(\.endAt).max() ?? metadata.updatedAt
        )
    }

    private func runSQLiteJSON(
        sqlitePath: String,
        databasePath: String,
        query: String
    ) -> [[String: Any]] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = ["-readonly", "-json", databasePath, query]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            guard let data = readBoundedProcessOutput(
                output.fileHandleForReading,
                process: process,
                maximumBytes: maximumSQLiteOutputBytes
            ) else { return [] }
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return value
        } catch {
            return []
        }
    }

    private func readBoundedProcessOutput(
        _ handle: FileHandle,
        process: Process,
        maximumBytes: Int
    ) -> Data? {
        guard let descriptor = try? POSIXPipeReader.duplicateDescriptor(for: handle) else {
            terminate(process)
            return nil
        }
        defer {
            Darwin.close(descriptor)
            try? handle.close()
        }

        var result = Data()
        while true {
            let chunk: Data
            do {
                guard let next = try POSIXPipeReader.readChunk(
                    from: descriptor,
                    maximumBytes: maximumSQLiteReadChunkBytes
                ) else { break }
                chunk = next
            } catch {
                terminate(process)
                return nil
            }
            guard chunk.count <= maximumBytes,
                  result.count <= maximumBytes - chunk.count else {
                terminate(process)
                return nil
            }
            result.append(chunk)
        }
        return result
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning { Darwin.kill(pid, SIGKILL) }
        }
    }

    // MARK: - Claude Code

    private func claudeTranscriptURLs(
        context: RuntimeLoadContext,
        earliestDate: Date
    ) -> [URL] {
        let root = context.homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= earliestDate
            else { continue }
            urls.append(url)
        }
        return urls
    }

    private func parseClaudeSource(url: URL) -> LeadershipParsedSource {
        let isSubagent = url.path.contains("/subagents/")
        let kind: LeadershipWorkerKind = isSubagent ? .subagent : .main
        let fileID = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "agent-", with: "")
        let parentSessionID = isSubagent
            ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            : nil
        let workerID = isSubagent ? "claude:subagent:\(fileID)" : "claude:main:\(fileID)"
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var cwd: String?
        var intervals: [LeadershipInterval] = []

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return LeadershipParsedSource(worker: nil, intervals: [], lastActivityAt: .distantPast)
        }
        text.enumerateLines { line, _ in
            if cwd == nil {
                cwd = jsonString(in: line, key: "cwd")
            }
            guard let timestampText = jsonString(in: line, key: "timestamp"),
                  let timestamp = parseISODate(timestampText)
            else { return }
            firstTimestamp = firstTimestamp.map { min($0, timestamp) } ?? timestamp
            lastTimestamp = lastTimestamp.map { max($0, timestamp) } ?? timestamp

            guard !isSubagent,
                  line.contains("\"subtype\":\"turn_duration\""),
                  let durationMilliseconds = jsonNumber(in: line, key: "durationMs")
            else { return }
            let start = timestamp.addingTimeInterval(-durationMilliseconds / 1_000)
            guard timestamp > start else { return }
            let project = self.projectIdentity(runtime: .claudeCode, path: cwd ?? "")
            intervals.append(LeadershipInterval(
                id: "claude:\(fileID):\(timestamp.timeIntervalSince1970)",
                workerID: workerID,
                runtime: .claudeCode,
                workerKind: .main,
                projectID: project.id,
                startAt: start,
                endAt: timestamp,
                quality: .fact,
                isAutonomous: false
            ))
        }

        let project = projectIdentity(runtime: .claudeCode, path: cwd ?? "")
        if isSubagent, let start = firstTimestamp, let end = lastTimestamp,
           end.timeIntervalSince(start) >= 1 {
            intervals.append(LeadershipInterval(
                id: "claude:\(fileID):lifecycle",
                workerID: workerID,
                runtime: .claudeCode,
                workerKind: .subagent,
                projectID: project.id,
                startAt: start,
                endAt: end,
                quality: .derived,
                isAutonomous: true
            ))
        }
        let worker = LeadershipWorker(
            id: workerID,
            runtime: .claudeCode,
            kind: kind,
            projectID: project.id,
            projectName: project.name,
            parentID: parentSessionID.map { "claude:main:\($0)" }
        )
        return LeadershipParsedSource(
            worker: worker,
            intervals: intervals,
            lastActivityAt: lastTimestamp ?? .distantPast
        )
    }

    // MARK: - Cache and parsing helpers

    private struct LeadershipFingerprint: Codable, Equatable {
        let fileSize: Int64
        let modificationTimeNanoseconds: Int64
    }

    private struct LeadershipParsedSource: Codable {
        let worker: LeadershipWorker?
        let intervals: [LeadershipInterval]
        let lastActivityAt: Date
    }

    private struct LeadershipCacheEntry: Codable {
        let fingerprint: LeadershipFingerprint
        let source: LeadershipParsedSource

        func matches(_ other: LeadershipFingerprint) -> Bool { fingerprint == other }
    }

    private struct LeadershipSourceCache: Codable {
        let version: Int
        var entries: [String: LeadershipCacheEntry]
    }

    private func cacheURL(context: RuntimeLoadContext) -> URL {
        context.cacheDirectory.appendingPathComponent("leadership-sources-v1.json")
    }

    private func readCache(context: RuntimeLoadContext) -> LeadershipSourceCache {
        let url = cacheURL(context: context)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? 0) <= maximumCacheBytes,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(LeadershipSourceCache.self, from: data),
              cache.version == cacheVersion
        else { return LeadershipSourceCache(version: cacheVersion, entries: [:]) }
        return cache
    }

    private func writeCache(_ cache: LeadershipSourceCache, context: RuntimeLoadContext) {
        let url = cacheURL(context: context)
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            guard Int64(data.count) <= maximumCacheBytes else { return }
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    private func fingerprint(_ url: URL) -> LeadershipFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let fileSize = values.fileSize,
              let modifiedAt = values.contentModificationDate
        else { return nil }
        return LeadershipFingerprint(
            fileSize: Int64(fileSize),
            modificationTimeNanoseconds: Int64(modifiedAt.timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func projectIdentity(
        runtime: RuntimeScope,
        path: String
    ) -> (id: String, name: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("\(runtime.runtimeId):uncategorized", "未归类")
        }
        return (
            "\(runtime.runtimeId):\(stableHash(trimmed))",
            URL(fileURLWithPath: trimmed).lastPathComponent
        )
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private func jsonString(in line: String, key: String) -> String? {
    let marker = "\"\(key)\":\""
    guard let markerRange = line.range(of: marker) else { return nil }
    var index = markerRange.upperBound
    var value = ""
    var escaped = false
    while index < line.endIndex {
        let character = line[index]
        if escaped {
            switch character {
            case "n": value.append("\n")
            case "t": value.append("\t")
            case "r": value.append("\r")
            default: value.append(character)
            }
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else if character == "\"" {
            return value
        } else {
            value.append(character)
        }
        index = line.index(after: index)
    }
    return nil
}

private func jsonNumber(in line: String, key: String) -> Double? {
    let marker = "\"\(key)\":"
    guard let markerRange = line.range(of: marker) else { return nil }
    var index = markerRange.upperBound
    while index < line.endIndex, line[index].isWhitespace {
        index = line.index(after: index)
    }
    let start = index
    while index < line.endIndex {
        let character = line[index]
        guard character.isNumber || character == "." || character == "-" else { break }
        index = line.index(after: index)
    }
    guard start < index else { return nil }
    return Double(line[start..<index])
}

private func numericValue(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber: number.doubleValue
    case let string as String: Double(string)
    default: nil
    }
}

private func parseISODate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
}

private func leadershipFirstExecutablePath(_ paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

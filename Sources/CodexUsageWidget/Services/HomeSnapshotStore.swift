import CryptoKit
import Darwin
import Foundation

/// A bounded display cache, deliberately independent of session caches and indexes.
/// Call from the home I/O queue, never the main thread or the history worker.
struct HomeSnapshotStore {
    static let maximumBytes = 256 * 1_024
    static let maximumTasksPerRuntime = 24
    static let currentFileName = "home-snapshot-v1.json"
    static let previousFileName = "home-snapshot-v1.previous.json"
    private static let version = 2

    /// The short-lived reader helper uses the same fixed card budget as home,
    /// while preserving the states it has just observed rather than cache states.
    static func taskData(board: TaskBoard) -> Data? {
        let record = BoardRecord(board, preserveCurrentState: true)
        guard record.isValid, let data = try? JSONEncoder().encode(record),
              data.count <= maximumBytes else { return nil }
        return data
    }

    static func taskBoard(data: Data) -> TaskBoard? {
        guard data.count <= maximumBytes,
              let record = try? JSONDecoder().decode(BoardRecord.self, from: data), record.isValid,
              record.columns.allSatisfy({ $0.items.allSatisfy { $0.currentState != nil } }) else { return nil }
        return record.restore(preserveCurrentState: true)
    }

    func read(context: RuntimeLoadContext) -> MultiRuntimeUsageSnapshot? {
        for name in [Self.currentFileName, Self.previousFileName] {
            guard let data = boundedData(at: context.cacheDirectory.appendingPathComponent(name)),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.isValid, envelope.matches(context) else { continue }
            return envelope.restore(context: context)
        }
        return restoreLegacy(context: context)
    }

    @discardableResult
    func write(_ snapshot: MultiRuntimeUsageSnapshot, context: RuntimeLoadContext) -> Bool {
        guard snapshot.statisticsIdentity.resolvedIdentifier == context.statistics.resolvedIdentifier,
              context.statistics.dayKey(for: snapshot.statisticsIdentity.now)
                == context.statistics.dayKey(for: context.now) else { return false }
        let candidate = Envelope(snapshot: snapshot, context: context)
        guard candidate.isValid,
              let encoded = try? JSONEncoder().encode(candidate), encoded.count <= Self.maximumBytes else { return false }
        let currentURL = context.cacheDirectory.appendingPathComponent(Self.currentFileName)
        let previousURL = context.cacheDirectory.appendingPathComponent(Self.previousFileName)
        let currentData = boundedData(at: currentURL)
        // A newer application owns this file; leave it and its backup untouched.
        if let currentData,
           let header = try? JSONDecoder().decode(VersionHeader.self, from: currentData),
           header.version > Self.version { return false }
        let existing = currentData.flatMap { try? JSONDecoder().decode(Envelope.self, from: $0) }
        if let existing, existing.isValid, existing.matches(context),
           existing.observedAt > candidate.observedAt { return false }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: context.cacheDirectory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: context.cacheDirectory.path)
            if let existing, existing.isValid, let currentData {
                try durableWrite(currentData, to: previousURL)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previousURL.path)
            }
            try durableWrite(encoded, to: currentURL)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: currentURL.path)
            return true
        } catch {
            return false
        }
    }

    private func durableWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR else { throw CocoaError(.fileWriteUnknown) }
        let temporary = directory.appendingPathComponent(".home-" + UUID().uuidString)
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor); Darwin.unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0, Darwin.rename(temporary.path, url.path) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func boundedData(at url: URL, maximumBytes: Int = Self.maximumBytes) -> Data? {
        // O_NONBLOCK also prevents a substituted FIFO from blocking the cache queue.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= maximumBytes else { return nil }
        // The read itself is capped even if another process replaces or grows the file.
        guard let data = try? handle.read(upToCount: maximumBytes),
              data.count == before.st_size else { return nil }
        var after = stat()
        guard fstat(descriptor, &after) == 0, after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { return nil }
        return data
    }

    // Version 1 home envelopes may contain partial archives. Recover only from the
    // old full-scan analytics cache, restricted to its original default source root.
    private func restoreLegacy(context: RuntimeLoadContext) -> MultiRuntimeUsageSnapshot? {
        let manager = FileManager.default
        let defaultCache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("codexU", isDirectory: true)
        guard context.homeDirectory.standardizedFileURL == manager.homeDirectoryForCurrentUser.standardizedFileURL,
              context.cacheDirectory.standardizedFileURL == defaultCache?.standardizedFileURL else { return nil }
        let url = context.cacheDirectory.appendingPathComponent("local-analytics-v2.json")
        var runtimes: [RuntimeUsageSnapshot] = []
        var observed = context.now
        if let data = boundedData(at: url, maximumBytes: 2 * 1_024 * 1_024),
           let legacy = try? JSONDecoder().decode(LegacyAnalytics.self, from: data),
           legacy.version == 15, legacy.dayKey == context.statistics.dayKey(for: context.now),
           legacy.timeZoneIdentifier == context.statistics.resolvedIdentifier,
           let date = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
           date <= context.now {
            observed = date
            let detail = legacy.analytics.detailedUsage
            let local = LocalUsage(lifetimeTokens: detail.lifetime.tokens.totalTokens,
                todayTokens: detail.today.tokens.totalTokens, sevenDayTokens: detail.sevenDay.tokens.totalTokens,
                threadCount: detail.parsedFileCount, lastUpdatedAt: observed, dailyBuckets: [], recentThreads: [],
                detailedUsage: detail, usageTrend: nil, inferencePerformance: nil, projectBoard: nil, toolUsages: [], skillUsages: [])
            if LocalRecord(local).isValid {
                runtimes.append(RuntimeUsageSnapshot(scope: .codex,
                    snapshot: UsageSnapshot(refreshedAt: observed, account: nil, limitId: nil, limitName: nil,
                        quotaReadSucceeded: false, fiveHourQuota: nil, sevenDayQuota: nil, monthlyQuota: nil,
                        credits: nil, cloudLifetimeTokens: nil, local: local, taskBoard: nil, messages: []),
                    status: .localOnly, quotaSourceLabel: "", usageSourceLabel: "Local records · last known"))
            }
        }
        let leadershipURL = context.cacheDirectory.appendingPathComponent("leadership-sources-v1.json")
        var leadership = LeadershipDashboardSnapshot.empty
        if let bytes = boundedData(at: leadershipURL, maximumBytes: 2 * 1_024 * 1_024),
           let date = (try? manager.attributesOfItem(atPath: leadershipURL.path))?[.modificationDate] as? Date,
           date <= context.now, context.statistics.dayKey(for: date) == context.statistics.dayKey(for: context.now),
           let restored = LeadershipDataReader().restoreCached(data: bytes, observedAt: date, calendar: context.statistics.calendar),
           LeadershipRecord(restored).isValid {
            leadership = restored
        }
        guard !runtimes.isEmpty || leadership.defaultReport != nil else { return nil }
        if runtimes.isEmpty {
            observed = leadership.refreshedAt
            runtimes = [RuntimeUsageSnapshot(scope: .codex, snapshot: .empty, status: .unavailable,
                                            quotaSourceLabel: "", usageSourceLabel: "")]
        }
        let snapshot = MultiRuntimeUsageSnapshot(refreshedAt: observed, runtimes: runtimes,
            aggregate: AgentUsageAggregator().aggregate(runtimes, at: observed), leadership: leadership,
            statisticsIdentity: StatisticsIdentity(preference: context.statistics.preference,
                resolvedIdentifier: context.statistics.resolvedIdentifier, generation: 0, now: context.now))
        let envelope = Envelope(snapshot: snapshot, context: context)
        return envelope.isValid ? envelope.restore(context: context) : nil
    }

    private struct LegacyAnalytics: Decodable {
        let version: Int
        let dayKey: String
        let timeZoneIdentifier: String
        let analytics: Summary
        struct Summary: Decodable { let detailedUsage: DetailedUsage }
    }

    private struct VersionHeader: Decodable { let version: Int }

    private struct Envelope: Codable {
        let version: Int
        let sourceIdentity: String
        let day: String
        let timeZone: String
        let observedAt: Date
        let statisticsObservedAt: Date
        let runtimes: [RuntimeRecord]
        let leadership: LeadershipRecord

        init(snapshot: MultiRuntimeUsageSnapshot, context: RuntimeLoadContext) {
            version = HomeSnapshotStore.version
            sourceIdentity = Self.sourceIdentity(context)
            day = context.statistics.dayKey(for: snapshot.statisticsIdentity.now)
            timeZone = context.statistics.resolvedIdentifier
            observedAt = snapshot.refreshedAt
            statisticsObservedAt = snapshot.statisticsIdentity.now
            // Iterate a fixed prefix even if the caller supplies a malformed collection.
            runtimes = snapshot.runtimes.prefix(RuntimeScope.allCases.count).map(RuntimeRecord.init)
            leadership = LeadershipRecord(snapshot.leadership)
        }

        var isValid: Bool {
            version == HomeSnapshotStore.version && sourceIdentity.utf8.count == 64
                && day.utf8.count == 10 && timeZone.utf8.count <= 128
                && observedAt.timeIntervalSince1970.isFinite
                && statisticsObservedAt.timeIntervalSince1970.isFinite
                && !runtimes.isEmpty && runtimes.count <= RuntimeScope.allCases.count
                && Set(runtimes.map(\.scope)).count == runtimes.count
                && runtimes.allSatisfy(\.isValid) && leadership.isValid
        }

        func matches(_ context: RuntimeLoadContext) -> Bool {
            sourceIdentity == Self.sourceIdentity(context)
                && timeZone == context.statistics.resolvedIdentifier
                && day == context.statistics.dayKey(for: context.now)
                && day == context.statistics.dayKey(for: statisticsObservedAt)
        }

        func restore(context: RuntimeLoadContext) -> MultiRuntimeUsageSnapshot {
            let values = runtimes.map { $0.restore() }
            return MultiRuntimeUsageSnapshot(
                refreshedAt: observedAt,
                runtimes: values,
                aggregate: AgentUsageAggregator().aggregate(values, at: observedAt),
                leadership: leadership.restore(),
                statisticsIdentity: StatisticsIdentity(
                    preference: context.statistics.preference,
                    resolvedIdentifier: timeZone,
                    generation: 0,
                    now: statisticsObservedAt
                )
            )
        }

        private static func sourceIdentity(_ context: RuntimeLoadContext) -> String {
            // Providers currently derive both source roots from this home. Do not persist paths.
            let source = context.homeDirectory.standardizedFileURL.path + "\n.codex\n.claude"
            return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct RuntimeRecord: Codable {
        let scope: RuntimeScope
        let observedAt: Date
        let local: LocalRecord?
        let board: BoardRecord?

        init(_ value: RuntimeUsageSnapshot) {
            scope = value.scope
            observedAt = value.snapshot.refreshedAt
            local = value.snapshot.local.map(LocalRecord.init)
            board = value.snapshot.taskBoard.map { BoardRecord($0) }
        }

        var isValid: Bool {
            observedAt.timeIntervalSince1970.isFinite
                && (local?.isValid ?? true) && (board?.isValid ?? true)
        }

        func restore() -> RuntimeUsageSnapshot {
            RuntimeUsageSnapshot(
                scope: scope,
                snapshot: UsageSnapshot(
                    refreshedAt: observedAt, account: nil, limitId: nil, limitName: nil,
                    quotaReadSucceeded: false, fiveHourQuota: nil, sevenDayQuota: nil,
                    monthlyQuota: nil, credits: nil, cloudLifetimeTokens: nil,
                    local: local?.restore(), taskBoard: board?.restore(),
                    messages: ["已恢复上次本机统计，正在更新"]
                ),
                status: local == nil ? .unavailable : .localOnly,
                quotaSourceLabel: "",
                usageSourceLabel: "Local records · last known"
            )
        }
    }

    private struct LocalRecord: Codable {
        let lifetimeTokens: Int64
        let todayTokens: Int64
        let sevenDayTokens: Int64
        let threadCount: Int
        let lastUpdatedAt: Date?
        let detailedUsage: DetailedUsage?

        init(_ value: LocalUsage) {
            lifetimeTokens = value.lifetimeTokens
            todayTokens = value.todayTokens
            sevenDayTokens = value.sevenDayTokens
            threadCount = value.threadCount
            lastUpdatedAt = value.lastUpdatedAt
            detailedUsage = value.detailedUsage
        }

        var isValid: Bool {
            [lifetimeTokens, todayTokens, sevenDayTokens].allSatisfy(validTokens)
                && validCount(threadCount) && validDate(lastUpdatedAt)
                && (detailedUsage.map { value in
                    [value.today, value.sevenDay, value.month, value.lifetime].allSatisfy(validUsage)
                        && validCount(value.parsedFileCount) && validCount(value.tokenEventCount)
                } ?? true)
        }

        func restore() -> LocalUsage {
            LocalUsage(
                lifetimeTokens: lifetimeTokens, todayTokens: todayTokens,
                sevenDayTokens: sevenDayTokens, threadCount: threadCount,
                lastUpdatedAt: lastUpdatedAt, dailyBuckets: [], recentThreads: [],
                detailedUsage: detailedUsage, usageTrend: nil, inferencePerformance: nil,
                projectBoard: nil, toolUsages: [], skillUsages: []
            )
        }
    }

    private struct BoardRecord: Codable {
        let observedAt: Date
        let columns: [ColumnRecord]

        init(_ value: TaskBoard, preserveCurrentState: Bool = false) {
            observedAt = value.refreshedAt
            columns = value.columns.prefix(4).map { ColumnRecord($0, preserveCurrentState: preserveCurrentState) }
        }

        var isValid: Bool {
            observedAt.timeIntervalSince1970.isFinite && columns.count <= 4
                && Set(columns.map(\.kind)).count == columns.count
                && columns.allSatisfy(\.isValid)
        }

        func restore(preserveCurrentState: Bool = false) -> TaskBoard {
            TaskBoard(refreshedAt: observedAt,
                      columns: columns.map { $0.restore(preserveCurrentState: preserveCurrentState) })
        }
    }

    private struct ColumnRecord: Codable {
        let kind: String
        let title: String
        let count: Int
        let items: [TaskRecord]

        init(_ value: TaskColumn, preserveCurrentState: Bool = false) {
            kind = value.id.rawValue
            title = bounded(value.title, bytes: 96)
            count = value.count
            items = value.items.prefix(HomeSnapshotStore.maximumTasksPerRuntime / 4)
                .map { TaskRecord($0, preserveCurrentState: preserveCurrentState) }
        }

        var isValid: Bool {
            TaskColumnKind(rawValue: kind) != nil && title.utf8.count <= 96
                && validCount(count) && items.count <= HomeSnapshotStore.maximumTasksPerRuntime / 4
                && items.count <= count && Set(items.map(\.id)).count == items.count
                && items.allSatisfy(\.isValid)
        }

        func restore(preserveCurrentState: Bool = false) -> TaskColumn {
            let column = TaskColumnKind(rawValue: kind)!
            return TaskColumn(id: column, title: title, count: count,
                              items: items.map { $0.restore(kind: column, preserveCurrentState: preserveCurrentState) })
        }
    }

    private struct TaskRecord: Codable {
        let id: String
        let code: String
        let title: String
        let threadID: String?
        let updatedAt: Date?
        let tokens: Int64?
        let source: String
        let basis: String
        let currentState: CurrentTaskState?

        init(_ value: TaskItem, preserveCurrentState: Bool = false) {
            id = bounded(value.id, bytes: 192)
            code = bounded(value.code, bytes: 32)
            title = bounded(value.title, bytes: 512)
            // Never truncate an action identifier into a different target.
            threadID = value.threadID.flatMap { $0.utf8.count <= 192 ? $0 : nil }
            updatedAt = value.updatedAt
            tokens = value.tokens
            source = value.sourceKind.rawValue
            basis = value.stateBasis.rawValue
            currentState = preserveCurrentState ? CurrentTaskState(value) : nil
        }

        var isValid: Bool {
            !id.isEmpty && id.utf8.count <= 192 && code.utf8.count <= 32
                && title.utf8.count <= 512 && (threadID?.utf8.count ?? 0) <= 192
                && validDate(updatedAt) && (tokens.map(validTokens) ?? true)
                && TaskSourceKind(rawValue: source) != nil && TaskStateBasis(rawValue: basis) != nil
                && (currentState?.isValid ?? true)
        }

        func restore(kind: TaskColumnKind, preserveCurrentState: Bool = false) -> TaskItem {
            let state = preserveCurrentState ? currentState : nil
            return TaskItem(id: id, code: code, title: title,
                     detail: state?.detail ?? "上次记录", chip: state?.chip ?? "recorded",
                     updatedAt: updatedAt, tokens: tokens, kind: kind, threadID: threadID,
                     runtimeState: state.flatMap { TaskRuntimeState(rawValue: $0.runtimeState) } ?? .recorded,
                     isRealtime: state?.isRealtime ?? false,
                     sourceKind: TaskSourceKind(rawValue: source)!,
                     displayState: state.flatMap { TaskDisplayState(rawValue: $0.displayState) } ?? .unknown,
                     stateBasis: TaskStateBasis(rawValue: basis)!,
                     rawStatus: state?.rawStatus, nextRunAt: state?.nextRunAt)
        }
    }

    /// Included only in bounded IPC, never in the persisted home envelope.
    private struct CurrentTaskState: Codable {
        let runtimeState: String
        let displayState: String
        let isRealtime: Bool
        let detail: String
        let chip: String
        let rawStatus: String?
        let nextRunAt: Date?

        init(_ value: TaskItem) {
            runtimeState = value.runtimeState.rawValue
            displayState = value.displayState.rawValue
            isRealtime = value.isRealtime
            detail = bounded(value.detail, bytes: 512)
            chip = bounded(value.chip, bytes: 64)
            rawStatus = value.rawStatus.map { bounded($0, bytes: 128) }
            nextRunAt = value.nextRunAt
        }

        var isValid: Bool {
            TaskRuntimeState(rawValue: runtimeState) != nil && TaskDisplayState(rawValue: displayState) != nil
                && detail.utf8.count <= 512 && chip.utf8.count <= 64 && (rawStatus?.utf8.count ?? 0) <= 128
                && validDate(nextRunAt)
        }
    }

    private struct LeadershipRecord: Codable {
        let modelVersion: String
        let observedAt: Date
        let reports: [LeadershipReport]

        init(_ value: LeadershipDashboardSnapshot) {
            modelVersion = bounded(value.modelVersion, bytes: 64)
            observedAt = value.refreshedAt
            reports = value.reports.prefix(3).map { report in
                LeadershipReport(
                    period: report.period, score: report.score, coreScore: report.coreScore,
                    title: report.title.map {
                        LeadershipTitle(level: $0.level, name: bounded($0.name, bytes: 128),
                                        lowerBound: $0.lowerBound, upperBound: $0.upperBound)
                    },
                    dimensions: Array(report.dimensions.prefix(4)), maturity: report.maturity,
                    evidenceCoverage: report.evidenceCoverage, activeDayCount: report.activeDayCount,
                    agentCount: report.agentCount, aiHours: report.aiHours,
                    autonomousHours: report.autonomousHours, averageParallelism: report.averageParallelism,
                    peakConcurrency: report.peakConcurrency, projectCount: report.projectCount,
                    dailyPoints: [], projects: []
                )
            }
        }

        var isValid: Bool {
            modelVersion.utf8.count <= 64 && observedAt.timeIntervalSince1970.isFinite
                && reports.count <= 3 && Set(reports.map(\.period)).count == reports.count
                && reports.allSatisfy { report in
                    report.dimensions.count <= 4 && report.dailyPoints.isEmpty && report.projects.isEmpty
                        && (report.title?.name.utf8.count ?? 0) <= 128
                        && (report.title.map {
                            (1...7).contains($0.level) && (0...100).contains($0.lowerBound)
                                && ($0.lowerBound...100).contains($0.upperBound)
                        } ?? true)
                        && (report.score.map { (0...100).contains($0) } ?? true)
                        && (0...1).contains(report.maturity) && (0...1).contains(report.evidenceCoverage)
                        && validCount(report.activeDayCount) && validCount(report.projectCount)
                        && [report.agentCount, report.peakConcurrency].allSatisfy { $0.map(validCount) ?? true }
                        && [report.coreScore, report.aiHours, report.autonomousHours,
                            report.averageParallelism, report.maturity, report.evidenceCoverage]
                            .allSatisfy { value in
                                value.map { $0.isFinite && $0 >= 0 && $0 <= Double(Int.max / 8) } ?? true
                            }
                        && Set(report.dimensions.map(\.kind)).count == report.dimensions.count
                        && report.dimensions.allSatisfy {
                            (0...100).contains($0.score) && (0...1).contains($0.confidence)
                                && $0.summaryValue.isFinite && $0.summaryValue >= 0
                                && $0.summaryValue <= Double(Int.max / 8)
                        }
                }
        }

        func restore() -> LeadershipDashboardSnapshot {
            LeadershipDashboardSnapshot(
                modelVersion: modelVersion, refreshedAt: observedAt,
                reports: modelVersion == LeadershipScoreModel.version ? reports : []
            )
        }
    }

    private static func bounded(_ text: String, bytes: Int) -> String {
        String(decoding: text.utf8.prefix(bytes), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FFFD}"))
    }

    private static func validTokens(_ value: Int64) -> Bool { value >= 0 && value <= Int64.max / 8 }
    private static func validCount(_ value: Int) -> Bool { value >= 0 && value <= Int.max / 8 }
    private static func validDate(_ value: Date?) -> Bool { value?.timeIntervalSince1970.isFinite ?? true }

    private static func validUsage(_ usage: PricedTokenUsage) -> Bool {
        let value = usage.tokens
        return [value.inputTokens, value.cachedInputTokens, value.cacheWriteInputTokens,
                value.outputTokens, value.reasoningOutputTokens, value.totalTokens].allSatisfy(validTokens)
            && usage.estimatedCostUSD.isFinite && usage.estimatedCostUSD >= 0
            && usage.estimatedCostUSD <= Double.greatestFiniteMagnitude / 8
    }
}

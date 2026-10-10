import CryptoKit
import Foundation

/// Application lifetime history owner. Discovery, parsing and publication never run on the main queue.
final class UsageHistoryService {
    static let shared = UsageHistoryService()
    private let queue = DispatchQueue(label: "codexU.history.service", qos: .utility, autoreleaseFrequency: .workItem)
    private let discoveryQueue = DispatchQueue(label: "codexU.history.discovery", qos: .utility, autoreleaseFrequency: .workItem)
    private var worker: UsageIndexWorker?
    private var key: String?
    private var epoch: UInt64 = 0
    private var update: ((UsageArchivePresentation) -> Void)?
    private var failure: ((UsageIndexError) -> Void)?
    private var refreshScheduled = false
    private var lastProbeProgress: TimeInterval = 0
    private var stopping = false
    private var stopCompletions: [() -> Void] = []
    private var pendingContext: RuntimeLoadContext?

    func subscribe(context: RuntimeLoadContext, onFailure: ((UsageIndexError) -> Void)? = nil,
                   onUpdate: @escaping (UsageArchivePresentation) -> Void) {
        queue.async {
            self.update = onUpdate
            self.failure = onFailure
            let key = context.homeDirectory.standardizedFileURL.path + "\n" + context.cacheDirectory.path + "\n"
                + context.statistics.resolvedIdentifier + "\n" + context.statistics.dayKey(for: context.now)
            if self.key == key { return }
            self.key = key; self.epoch &+= 1; self.refreshScheduled = false
            self.pendingContext = context
            self.transition()
        }
    }

    private func transition() {
        guard !stopping else { return }
        if let previous = worker {
            stopping = true
            previous.stop {
                self.queue.async {
                    self.worker = nil; self.stopping = false
                    self.transition()
                }
            }
        } else if let context = pendingContext {
            pendingContext = nil
            start(context: context, epoch: epoch)
        } else {
            let completions = stopCompletions; stopCompletions.removeAll()
            for completion in completions { completion() }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        queue.async {
            if let completion { self.stopCompletions.append(completion) }
            self.epoch &+= 1; self.key = nil; self.update = nil; self.failure = nil
            self.pendingContext = nil; self.refreshScheduled = false
            self.transition()
        }
    }

    static func indexDirectory(context: RuntimeLoadContext) -> URL {
        let root = SHA256.hash(data: Data(context.homeDirectory.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = ProcessInfo.processInfo.environment["CODEXU_CACHE_OVERRIDE"] != nil
            ? context.cacheDirectory
            : context.homeDirectory.appendingPathComponent("Library/Application Support/codexU", isDirectory: true)
        return base.appendingPathComponent("usage-index/v1/" + root, isDirectory: true)
    }

    private func reportFailure(_ error: Error, epoch: UInt64) {
        let code = error as? UsageIndexError ?? .databaseFailure
        guard code != .cancelled && code != .sourceChanged else { return }
        queue.async {
            guard self.epoch == epoch else { return }
            self.failure?(code)
        }
    }

    private func start(context: RuntimeLoadContext, epoch: UInt64) {
        guard self.epoch == epoch else { return }
        let root = SHA256.hash(data: Data(context.homeDirectory.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = Self.indexDirectory(context: context)
        let worker = UsageIndexWorker(); self.worker = worker
        // Accessed only from this worker's serial writer callback.
        var lastDetails: [String: TimeInterval] = [:]
        var lastLeadership: TimeInterval?
        worker.start(directory: directory, sources: [], rootID: root, statistics: context.statistics, onArchive: { [weak self] store, build in
            do {
                let projectionContext = try store.ensureProjectionContext(root: root, statistics: context.statistics, now: context.now)
                let runtime = try store.rows("SELECT runtime FROM report_build WHERE id=?", [.text(build)], limit: 1).first?.first?.text ?? "codex"
                let presentation = try store.archivePresentation(context: projectionContext, statistics: context.statistics, runtime: runtime)
                if let presentation {
                    self?.queue.async {
                        guard let self, self.epoch == epoch else { return }
                        self.update?(presentation)
                    }
                }
                guard presentation?.complete == true else { return }
                let liveStatistics = StatisticsContext(preference: context.statistics.preference, now: Date())
                let clock = ProcessInfo.processInfo.systemUptime
                let detailInterval: TimeInterval = presentation?.complete == true ? 15 : 60
                if lastDetails[runtime].map({ clock-$0 >= detailInterval }) ?? true {
                  lastDetails[runtime] = clock
                  if let detailed = try? store.withDeadline(milliseconds: 10000, {
                    try store.archivePresentation(context: projectionContext, statistics: liveStatistics, runtime: runtime, includeDetails: true)
                }) {
                    self?.queue.async {
                        guard let self, self.epoch == epoch else { return }
                        self.update?(detailed)
                    }
                }
                }
                // Leadership is an independent domain; a detail limit or timeout cannot suppress it.
                let completeRuntimes = try store.scalar("SELECT count(*) FROM published_slice WHERE context_id=? AND domain='archive' AND coverage='completeAtRevision'", [.text(projectionContext)]) ?? 0
                let leadershipInterval: TimeInterval = completeRuntimes == 2 ? 15 : 60
                if completeRuntimes == 2, lastLeadership.map({ clock-$0 >= leadershipInterval }) ?? true {
                  lastLeadership = clock
                  if let leadership = try? store.withDeadline(milliseconds: 10000, {
                       try store.indexedLeadership(root: root, statistics: liveStatistics)
                   }),
                   var summary = try store.archivePresentation(context: projectionContext, statistics: liveStatistics, runtime: runtime) {
                    summary.leadership = leadership
                    summary.leadershipComplete = completeRuntimes == 2
                    let value = summary
                    self?.queue.async {
                        guard let self, self.epoch == epoch else { return }
                        self.update?(value)
                    }
                  }
                }
            } catch { self?.reportFailure(error, epoch: epoch) }
        }, onProgress: { progress in
            if let error = progress.error { self.reportFailure(error, epoch: epoch) }
            guard CommandLine.arguments.contains("--probe-history-index") else { return }
            self.queue.async {
                guard self.epoch == epoch else { return }
                let clock = ProcessInfo.processInfo.systemUptime
                guard clock-self.lastProbeProgress>=5 else { return }
                self.lastProbeProgress=clock
                let record:[String:Any] = ["committedBatches":progress.committedBatches,"parserReadBytes":progress.rawBytes,
                    "pendingJobs":progress.pendingJobs,"error":progress.error?.rawValue as Any? ?? NSNull()]
                if let data=try? JSONSerialization.data(withJSONObject:record,options:.sortedKeys) {
                    FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10]))
                }
            }
        })
        worker.perform({ store in
            try store.migrateInferenceRecordingStart(home: context.homeDirectory, now: context.now)
            let projectionContext = try store.ensureProjectionContext(root: root, statistics: context.statistics, now: context.now)
            for runtime in ["codex", "claude-code"] {
                if let presentation = try store.archivePresentation(context: projectionContext, statistics: context.statistics, runtime: runtime) {
                    self.queue.async { if self.epoch == epoch { self.update?(presentation) } }
                }
            }
        }, completion: { error in
            self.queue.async {
                guard self.epoch == epoch else { return }
                guard error == nil else {
                    if let error { self.reportFailure(error, epoch: epoch) }
                    self.key = nil
                    self.transition()
                    return
                }
                self.discoveryQueue.async { self.discover(context: context, directory: directory, root: root, epoch: epoch) }
            }
        })
    }

    private func discover(context: RuntimeLoadContext, directory: URL, root: String, epoch: UInt64) {
        guard let worker = queue.sync(execute: { self.epoch == epoch ? self.worker : nil }) else { return }
        let candidates = [context.homeDirectory.appendingPathComponent(".codex/state_5.sqlite"),
                          context.homeDirectory.appendingPathComponent(".codex/sqlite/state_5.sqlite")]
        let database = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
        let claudeRoot = context.homeDirectory.appendingPathComponent(".claude/projects")
        for runtime in ["codex", "claude-code"] {
        guard queue.sync(execute: { self.epoch == epoch }) else { return }
        // Capture the original SQLite snapshot quickly into a bounded private metadata spool. The
        // original database read transaction is closed before backpressure from index writes.
        let spool = directory.appendingPathComponent("inventory-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: spool) }
        do {
            guard FileManager.default.createFile(atPath: spool.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw UsageIndexError.diskFull
            }
            let output = try FileHandle(forWritingTo: spool)
            defer { try? output.close() }
            let writePage: ([UsageDiscoveredSource]) throws -> Void = { page in
                for source in page {
                    var data = try JSONEncoder().encode(source); data.append(10)
                    try output.write(contentsOf: data)
                }
            }
            let discovery: UsageDiscoveryResult
            if runtime == "codex", let database {
                discovery = try UsageSourceDiscovery.codex(databaseURL: database, page: writePage)
            } else if runtime == "claude-code", FileManager.default.fileExists(atPath: claudeRoot.path) {
                discovery = try UsageSourceDiscovery.claude(root: claudeRoot, page: writePage)
            } else {
                discovery = UsageDiscoveryResult(sources: 0, complete: true, metadataBytes: 0)
            }
            try output.close()
            var scan: Int64 = 0
            try awaitWorker(worker) { store in scan = try store.beginDiscovery(root: root, runtime: runtime, now: Date()) }
            let size = (try FileManager.default.attributesOfItem(atPath: spool.path)[.size] as? NSNumber)?.uint64Value ?? 0
            var cursor = UsageStreamCursor()
            while cursor.offset < size {
                guard queue.sync(execute: { self.epoch == epoch }) else { throw UsageIndexError.cancelled }
                var sources: [UsageDiscoveredSource] = []
                let batch = try UsageStreamParser.read(url: spool, targetEnd: size, cursor: cursor, maximumLines: 256) { line, _ in
                    sources.append(try JSONDecoder().decode(UsageDiscoveredSource.self, from: line))
                }
                cursor = batch.cursor
                let done = DispatchSemaphore(value: 0)
                var failure: UsageIndexError?
                worker.enqueue(sources: sources, rootID: root) { failure = $0; done.signal() }
                guard done.wait(timeout: .now() + 10) == .success else { throw UsageIndexError.cancelled }
                if let failure { throw failure }
                let ids = sources.map { UsageIndexWorker.sourceID(root: root, logicalID: $0.logicalID, runtime: $0.runtime) }
                try awaitWorker(worker) { store in
                    try store.transaction {
                        for id in ids { try store.execute("UPDATE source SET discovered_epoch=? WHERE id=?", [.integer(scan), .text(id)]) }
                    }
                }
            }
            try awaitWorker(worker) { store in try store.finishDiscovery(scan: scan, complete: discovery.complete, now: Date()) }
            worker.notifyInventoryChanged()
        } catch { reportFailure(error, epoch: epoch) }
        }
        scheduleDiscovery(context: context, directory: directory, root: root, epoch: epoch)
    }

    private func awaitWorker(_ worker: UsageIndexWorker, operation: @escaping (UsageIndexStore) throws -> Void) throws {
        let finished = DispatchSemaphore(value: 0)
        var failure: UsageIndexError?
        worker.perform(operation) { failure = $0; finished.signal() }
        guard finished.wait(timeout: .now() + 10) == .success else { throw UsageIndexError.cancelled }
        if let failure { throw failure }
    }

    private func scheduleDiscovery(context: RuntimeLoadContext, directory: URL, root: String, epoch: UInt64) {
        queue.async {
            guard self.epoch == epoch, !self.refreshScheduled else { return }
            self.refreshScheduled = true
            self.queue.asyncAfter(deadline: .now() + 30) {
                guard self.epoch == epoch else { return }
                self.refreshScheduled = false
                self.discoveryQueue.async { self.discover(context: context, directory: directory, root: root, epoch: epoch) }
            }
        }
    }
}

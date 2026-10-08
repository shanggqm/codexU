import CryptoKit
import Foundation

struct UsageIndexedCodexState: Codable {
    let parser: CodexIndexCheckpoint
    let stamp: UsageFileStamp
    var awaitingNewline: Bool = false
    var claude: ClaudeIndexCheckpoint? = nil
}

/// Owns the database and dispatches at most two isolated readers. All mutable state is queue-owned.
final class UsageIndexWorker {
    struct Progress {
        let committedBatches: Int
        let rawBytes: Int
        let pendingJobs: Int
        let error: UsageIndexError?
    }

    private let writer = DispatchQueue(label: "codexU.index.writer", qos: .utility, autoreleaseFrequency: .workItem)
    private let readers = [DispatchQueue(label: "codexU.index.parse.0", qos: .utility, autoreleaseFrequency: .workItem),
                           DispatchQueue(label: "codexU.index.parse.1", qos: .utility, autoreleaseFrequency: .workItem)]
    private let helpers = [UsageParseHelper(), UsageParseHelper()]
    private var busy = Set<Int>()
    private var store: UsageIndexStore?
    private var materializers: [String: UsageIndexMaterializer] = [:]
    private var dispatchScheduled = false
    private var active = false
    private var epoch: UInt64 = 0
    private var stopping: (() -> Void)?
    private var batches = 0
    private var rawBytes = 0
    private var failures: [String: Int] = [:]
    private var callback: ((Progress) -> Void)?
    private var lastSource: String?
    private var consecutiveSource = 0

    func start(directory: URL, sources: [UsageDiscoveredSource], rootID: String,
               statistics: StatisticsContext? = nil, onArchive: ((UsageIndexStore, String) -> Void)? = nil,
               onProgress: @escaping (Progress) -> Void) {
        writer.async {
            guard !self.active, self.busy.isEmpty else { return }
            self.epoch &+= 1
            self.active = true; self.callback = onProgress
            do {
                let store = try UsageIndexStore(directory: directory)
                self.store = store
                if let statistics {
                    for runtime in ["codex", "claude-code"] {
                        let materializer = try UsageIndexMaterializer(store: store, root: rootID, statistics: statistics, runtime: runtime)
                        materializer.onArchive = { build in onArchive?(store, build) }
                        self.materializers[runtime] = materializer
                    }
                }
                try store.recoverInterruptedJobs()
                try self.register(sources: sources, rootID: rootID)
                self.dispatch()
            } catch { self.publish(error as? UsageIndexError ?? .databaseFailure); self.active = false; self.materializers.removeAll(); self.store = nil }
        }
    }

    /// Discovery sends one bounded page at a time and waits for completion before producing another.
    func enqueue(sources: [UsageDiscoveredSource], rootID: String, completion: @escaping (UsageIndexError?) -> Void) {
        writer.async {
            do {
                guard self.active else { throw UsageIndexError.cancelled }
                try self.register(sources: sources, rootID: rootID)
                completion(nil)
                self.dispatch()
            } catch { completion(error as? UsageIndexError ?? .databaseFailure) }
        }
    }

    private func register(sources: [UsageDiscoveredSource], rootID: String) throws {
        guard let store, sources.count <= 256 else { throw UsageIndexError.resourceLimited }
        try store.transaction {
        for source in sources {
            guard ["codex", "claude-code"].contains(source.runtime) else { throw UsageIndexError.cacheInvalid }
            let id = Self.sourceID(root: rootID, logicalID: source.logicalID, runtime: source.runtime)
            try store.registerSource(id: id, root: rootID, runtime: source.runtime,
                                     logicalID: source.logicalID, locator: source.locator, now: Date())
            try store.execute("UPDATE source SET locator=? WHERE id=?", [.text(source.locator), .text(id)])
            let previous = try store.metadata(source: id, revision: Int64.max)
            try store.recordMetadata(source: id, metadata: UsageSourceMetadata(model: source.model,
                project: source.project, parentLogicalID: previous?.value.parentLogicalID,
                createdAt: source.createdAt, sourceKind: source.sourceKind, workerParentID: source.workerParentID,
                automationID: source.automationID), now: Date())
            try materializers[source.runtime]?.enqueue(id)
            try store.enqueueDiscoveredSource(id, priority: source.updatedAt >= Int64(Date().timeIntervalSince1970 - 7 * 86400) ? 1 : 2, now: Date())
        }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        writer.async {
            self.active = false; self.epoch &+= 1; self.callback = nil; self.stopping = completion
            self.finishStopIfDrained()
        }
    }

    private func finishStopIfDrained() {
        guard !active, busy.isEmpty else { return }
        materializers.removeAll(); store = nil
        let completion = stopping; stopping = nil
        // Execute after callbacks have released their captured database references.
        writer.async { completion?() }
    }

    static func sourceID(root: String, logicalID: String, runtime: String = "codex") -> String {
        SHA256.hash(data: Data((root + "\n" + runtime + "\n" + logicalID).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var lastMaintenance: TimeInterval = 0
    private func dispatch() {
        guard active, let store else { return }
        do {
            if ProcessInfo.processInfo.systemUptime-lastMaintenance >= 60 {
                lastMaintenance = ProcessInfo.processInfo.systemUptime
                do {
                    let removed = try store.collectGarbage(now: Date())
                    if removed > 0 {
                        // Drain a backlog in bounded slices while leaving ingestion turns between
                        // them. Waiting a minute per slice cannot keep up with archive publication.
                        lastMaintenance -= 59.95
                        scheduleDispatch(after: 0.05)
                    } else {
                        try store.collectVersionGarbage(now: Date())
                        try store.checkpointWAL()
                        writer.asyncAfter(deadline: .now()+60) { [weak self] in self?.dispatch() }
                    }
                } catch {
                    let code = error as? UsageIndexError ?? .databaseFailure
                    if code != .cancelled { publish(code) }
                    lastMaintenance -= 59
                    scheduleDispatch(after: 1)
                }
            }
            for slot in readers.indices where !busy.contains(slot) {
                guard let job = try store.claimJob(now: Date(), avoiding: consecutiveSource >= 2 ? lastSource : nil),
                      let source = job.source else { break }
                if source == lastSource { consecutiveSource += 1 } else { lastSource = source; consecutiveSource = 1 }
                do {
                guard let sourceRow = try store.rows("SELECT locator,runtime FROM source WHERE id=?", [.text(source)], limit: 1).first,
                      let path = sourceRow[0].text, let runtime = sourceRow[1].text else {
                    throw UsageIndexError.cacheInvalid
                }
                let checkpoint = try store.checkpoint(source: source)
                let state = try checkpoint.map { try JSONDecoder().decode(UsageIndexedCodexState.self, from: Data($0.state.utf8)) }
                let request = UsageParseRequest(id: UUID().uuidString, path: path,
                    targetEnd: checkpoint.map { UInt64($0.targetEnd) } ?? 0,
                    checkpoint: state?.parser ?? CodexIndexCheckpoint(), previousStamp: state?.stamp,
                    finishFrozenTail: state?.awaitingNewline ?? false, runtime: runtime, claudeCheckpoint: state?.claude,
                    forceRebuild: try checkpoint.map { cp in
                        (try store.scalar("SELECT parser_version FROM source_generation WHERE source_id=? AND generation=?", [.text(source),.integer(cp.generation)]) ?? 0) < 3
                    } ?? false)
                let requestEpoch = epoch
                busy.insert(slot)
                readers[slot].async {
                    let result = Result { try self.helpers[slot].parse(request) }
                    self.writer.async {
                        self.busy.remove(slot)
                        guard self.active, self.epoch == requestEpoch else { self.finishStopIfDrained(); return }
                        do {
                            switch result {
                            case .success(let response):
                                try store.transaction {
                                    try self.commit(response, source: source, checkpoint: checkpoint, job: job)
                                }
                            case .failure(let error): throw error
                            }
                        } catch {
                            let code = error as? UsageIndexError ?? .databaseFailure
                            try? store.observeSource(source: source, identity: checkpoint?.identity ?? "",
                                targetEnd: checkpoint?.targetEnd ?? 0, status: "unreadable", now: Date())
                            self.failures[source, default: 0] += 1
                            if self.failures[source, default: 0] >= 3 && code != .sourceChanged && code != .cancelled {
                                try? store.execute("UPDATE job SET status='error',cursor=? WHERE id=?", [.text("{\"error\":\""+code.rawValue+"\"}"),.text(job.id)])
                                try? store.execute("UPDATE source SET status='stale' WHERE id=?", [.text(source)])
                            } else {
                                try? store.finishJob(job, more: true, retryAt: Date().addingTimeInterval(1), now: Date())
                                self.writer.asyncAfter(deadline: .now() + 1) { self.dispatch() }
                            }
                            self.publish(code)
                        }
                        self.dispatch()
                    }
                }
                } catch {
                    let code = error as? UsageIndexError ?? .cacheInvalid
                    try? store.execute("UPDATE job SET status='error',cursor=? WHERE id=?", [.text("{\"error\":\""+code.rawValue+"\"}"),.text(job.id)])
                    publish(error as? UsageIndexError ?? .cacheInvalid)
                }
            }
            var derived = try store.stepClaudeOwnership(now: Date()) { source in try self.materializers["claude-code"]?.enqueue(source) }
            for runtime in ["codex", "claude-code"] { if try materializers[runtime]?.step() == true { derived = true } }
            if derived { scheduleDispatch() }
            else if materializers.values.contains(where: { $0.hasPendingWork }) { scheduleDispatch(after: 0.25) }
            else if (try store.scalar("SELECT count(*) FROM job WHERE status='queued' AND retry_at_ms IS NOT NULL") ?? 0) > 0 {
                scheduleDispatch(after: 1)
            }
            publish(nil)
        } catch {
            let code = error as? UsageIndexError ?? .databaseFailure
            if code == .diskFull { lastMaintenance = 0 }
            publish(code)
            scheduleDispatch(after: 1)
        }
    }

    private func scheduleDispatch(after delay: Double = 0) {
        guard !dispatchScheduled else { return }
        dispatchScheduled = true
        writer.asyncAfter(deadline: .now() + delay) {
            self.dispatchScheduled = false
            self.dispatch()
        }
    }

    func notifyInventoryChanged() {
        writer.async {
            for materializer in self.materializers.values { materializer.invalidateArchive() }
            self.scheduleDispatch()
        }
    }

    func perform(_ operation: @escaping (UsageIndexStore) throws -> Void, completion: @escaping (UsageIndexError?) -> Void) {
        writer.async {
            do {
                guard self.active, let store = self.store else { throw UsageIndexError.cancelled }
                try operation(store); completion(nil)
            } catch { completion(error as? UsageIndexError ?? .databaseFailure) }
        }
    }

    private func commit(_ response: UsageParseResponse, source: String,
                        checkpoint: UsageIndexCheckpoint?, job: UsageIndexJob) throws {
        guard let store else { throw UsageIndexError.cancelled }
        rawBytes += response.batch.readBytes
        try store.observeSource(source: source, identity: response.stamp.identity,
            targetEnd: Int64(response.stamp.size), status: "readable", now: Date())
        let encoder = JSONEncoder()
        func state(_ parser: CodexIndexCheckpoint, _ stamp: UsageFileStamp, awaiting: Bool = false) throws -> String {
            let data = try encoder.encode(UsageIndexedCodexState(parser: parser, stamp: stamp, awaitingNewline: awaiting, claude: response.claude?.checkpoint))
            guard data.count <= UsageIndexStore.maximumPayloadBytes else { throw UsageIndexError.resourceLimited }
            return String(decoding: data, as: UTF8.self)
        }
        if checkpoint == nil || response.requiresRebuild {
            _ = try store.beginGeneration(source: source, identity: response.stamp.identity,
                targetEnd: Int64(response.stamp.size), initialState: state(response.batch.checkpoint, response.stamp), now: Date())
            try store.finishJob(job, more: true, now: Date())
            return
        }
        guard let checkpoint else { throw UsageIndexError.cacheInvalid }
        guard response.stamp.identity == checkpoint.identity else { throw UsageIndexError.sourceChanged }
        let activeGeneration = try store.scalar("SELECT valid_from FROM source_generation WHERE source_id=? AND generation=?",
                                               [.text(source), .integer(checkpoint.generation)]) != nil
        if response.batch.readBytes == 0, !response.batch.awaitingNewline, activeGeneration, checkpoint.offset == checkpoint.targetEnd {
            if response.stamp.size > UInt64(checkpoint.targetEnd) {
                _ = try store.observeAppend(source: source, expected: checkpoint, targetEnd: Int64(response.stamp.size),
                                            verifiedIdentity: response.stamp.identity, now: Date())
                try store.finishJob(job, more: true, now: Date())
            } else { try store.finishJob(job, more: false, now: Date()) }
            try materializers[response.claude == nil ? "codex" : "claude-code"]?.enqueue(source)
            failures.removeValue(forKey: source)
            return
        }
        if let boundary = response.completedBoundary {
            let previous = try JSONDecoder().decode(UsageIndexedCodexState.self, from: Data(checkpoint.state.utf8))
            let cleared = try store.append(source: source, expected: checkpoint, offset: checkpoint.offset,
                state: state(previous.parser, previous.stamp), facts: [], now: Date(), completeOffset: Int64(previous.parser.cursor.lastCompleteOffset ?? previous.parser.cursor.offset))
            if activeGeneration {
                _ = try store.observeAppend(source: source, expected: cleared, targetEnd: Int64(boundary),
                    verifiedIdentity: response.stamp.identity, now: Date())
            } else {
                _ = try store.finishFrozenTail(source: source, expected: cleared, boundary: Int64(boundary),
                    verifiedIdentity: response.stamp.identity, now: Date())
            }
            try store.finishJob(job, more: true, now: Date())
            return
        }
        var facts: [UsageIndexFact] = []
        var sequence = try store.scalar("SELECT max(sequence) FROM fact WHERE source_id=? AND generation=?",
                                       [.text(source), .integer(checkpoint.generation)]) ?? 0
        func add(_ payload: UsageFactPayload, at date: Date) {
            sequence += 1
            facts.append(UsageIndexFact(logicalKey: String(format: "%020lld", sequence), occurredAt: date, payload: payload))
        }
        for delta in response.batch.deltas { add(.token(delta), at: delta.date) }
        for sample in response.batch.inferenceSamples { add(.inference(sample), at: sample.completedAt) }
        for (name, count) in response.batch.toolCalls.sorted(by: { $0.key < $1.key }) { add(.tool(name: name, count: count), at: Date()) }
        for skill in response.batch.skillLoads { add(.skill(skill), at: skill.date ?? Date()) }
        if let claude = response.claude {
            var messageKeys = Set<String>()
            for delta in claude.deltas {
                if let messageID = delta.messageId {
                    let key = "message:" + SHA256.hash(data: Data(messageID.utf8)).map { String(format: "%02x", $0) }.joined()
                    if !messageKeys.insert(key).inserted { continue }
                    if try store.scalar("SELECT 1 FROM fact WHERE source_id=? AND generation=? AND kind='claudeToken' AND logical_key=? LIMIT 1",
                        [.text(source), .integer(checkpoint.generation), .text(key)]) != nil { continue }
                    facts.append(UsageIndexFact(logicalKey: key, occurredAt: delta.date, payload: .claudeToken(delta)))
                } else { add(.claudeToken(delta), at: delta.date) }
            }
            for (name, count) in claude.tools.sorted(by: { $0.key < $1.key }) { add(.tool(name: name, count: count), at: Date()) }
            for skill in claude.skills { add(.claudeSkill(skill), at: skill.date ?? Date()) }
            for interval in claude.intervals {
                facts.append(UsageIndexFact(logicalKey: interval.id, occurredAt: interval.startAt, payload: .interval(interval)))
            }
        } else {
            facts.append(UsageIndexFact(logicalKey: "counter", occurredAt: Date(), payload: .counters(
                rawTokenEvents: response.batch.checkpoint.tokenEventCount, hasTokenEvents: response.batch.checkpoint.sawTokenEvent)))
        }
        if let metadata = try store.metadata(source: source, revision: Int64.max),
           let logicalID = try store.rows("SELECT logical_id FROM source WHERE id=?", [.text(source)], limit: 1).first?.first?.text {
            var starts: [String: Date] = [:]
            for event in response.batch.turnEvents {
                let key = "turn:" + event.turnID
                if event.isStart {
                    starts[event.turnID] = event.date
                    facts.append(UsageIndexFact(logicalKey: key, occurredAt: event.date, payload: .turnStart(event.date)))
                } else {
                    if starts[event.turnID] == nil,
                       let payload = try store.rows("SELECT payload FROM fact WHERE source_id=? AND generation=? AND kind='turnStart' AND logical_key=? ORDER BY sequence DESC LIMIT 1",
                           [.text(source), .integer(checkpoint.generation), .text(key)], limit: 1).first?.first?.text,
                       case .turnStart(let date) = try JSONDecoder().decode(UsageFactPayload.self, from: Data(payload.utf8)) {
                        starts[event.turnID] = date
                    }
                    if let interval = UsageLeadershipAdapter.interval(event: event, start: starts[event.turnID],
                        logicalID: logicalID, metadata: metadata.value, now: Date()) { add(.interval(interval), at: interval.startAt) }
                }
            }
        }
        let next = try store.append(source: source, expected: checkpoint, offset: Int64(response.batch.checkpoint.cursor.offset),
            state: state(response.batch.checkpoint, response.stamp, awaiting: response.batch.awaitingNewline), facts: facts, now: Date(),
            completeOffset: Int64(response.batch.checkpoint.cursor.lastCompleteOffset ?? (response.batch.checkpoint.cursor.skippingOversizedLine ? 0 : response.batch.checkpoint.cursor.offset)))
        if let metadata = try store.metadata(source: source, revision: Int64.max),
           metadata.value.parentLogicalID != response.batch.checkpoint.forkedFromID {
            var updated = metadata.value; updated.parentLogicalID = response.batch.checkpoint.forkedFromID
            try store.recordMetadata(source: source, metadata: updated, now: Date())
        }
        batches += 1
        if response.batch.reachedTarget, response.batch.checkpoint.cursor.oversizedLineCount > 0 {
            throw UsageIndexError.resourceLimited
        }
        if response.batch.reachedTarget, !activeGeneration {
            _ = try store.activate(source: source, expected: next, verifiedIdentity: response.stamp.identity, now: Date())
        }
        if response.batch.reachedTarget {
            if response.claude != nil { try store.enqueueClaudeOwnership(source: source, now: Date()) }
            try materializers[response.claude == nil ? "codex" : "claude-code"]?.enqueue(source)
        }
        if response.batch.awaitingNewline {
            try store.finishJob(job, more: true, retryAt: Date().addingTimeInterval(30), now: Date())
            writer.asyncAfter(deadline: .now() + 30) { self.dispatch() }
        } else {
            try store.finishJob(job, more: !response.batch.reachedTarget || response.stamp.size > UInt64(next.targetEnd), now: Date())
        }
        failures.removeValue(forKey: source)
    }

    private func publish(_ error: UsageIndexError?) {
        let pending = (try? store?.scalar("SELECT count(*) FROM job WHERE status IN ('queued','running')")) ?? 0
        callback?(Progress(committedBatches: batches, rawBytes: rawBytes, pendingJobs: Int(pending), error: error))
    }
}

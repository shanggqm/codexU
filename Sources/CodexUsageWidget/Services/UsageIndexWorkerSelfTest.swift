import Foundation

enum UsageIndexWorkerSelfTest {
    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tests/fixtures/history-index/codex-counters.jsonl")
            let path = root.appendingPathComponent("session.jsonl")
            let bytes = try Data(contentsOf: fixture)
            try bytes.write(to: path)
            var directory = root.appendingPathComponent("index")
            var source = UsageDiscoveredSource(runtime: "codex", logicalID: "one", locator: path.path,
                model: "gpt-5", project: "fixture", updatedAt: 0)
            func index(minimumBatches: Int = 0) throws -> Int {
                let worker = UsageIndexWorker()
                let finished = DispatchSemaphore(value: 0)
                let stopped = DispatchSemaphore(value: 0)
                var rawBytes = 0
                var committedBatches = 0
                var failure: UsageIndexError?
                var signalled = false
                worker.start(directory: directory, sources: [source], rootID: "test") { progress in
                    rawBytes = progress.rawBytes
                    committedBatches = progress.committedBatches
                    if let error = progress.error { failure = error }
                    if progress.pendingJobs == 0, !signalled {
                        signalled = true
                        worker.stop { stopped.signal() }
                        finished.signal()
                    }
                }
                guard finished.wait(timeout: .now() + 20) == .success,
                      stopped.wait(timeout: .now() + 5) == .success else {
                    worker.stop(); throw UsageIndexError.cancelled
                }
                if let failure { throw failure }
                guard committedBatches >= minimumBatches else { throw UsageIndexError.databaseFailure }
                return rawBytes
            }
            func total() throws -> Int64 {
                let store = try UsageIndexStore(directory: directory)
                let revision = try store.scalar("SELECT max(id) FROM revision") ?? 0
                let id = UsageIndexWorker.sourceID(root: "test", logicalID: "one")
                var key = ""
                var total: Int64 = 0
                while true {
                    let page = try store.factsAt(source: id, kind: "token", revision: revision, afterKey: key)
                    if page.isEmpty { break }
                    for row in page {
                        key = row[0].text!
                        if case .token(let token) = try JSONDecoder().decode(UsageFactPayload.self, from: Data(row[3].text!.utf8)) {
                            total += token.tokens.totalTokens
                        }
                    }
                }
                return total
            }
            guard try index() > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            guard try index() == 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            // An atomic replacement must stage and replace, never add its full history to the old generation.
            let first = bytes.prefix(through: bytes.firstIndex(of: 10)!)
            try first.write(to: path, options: .atomic)
            guard try index() > 0, try total() == 100 else { throw UsageIndexError.databaseFailure }
            let handle = try FileHandle(forWritingTo: path)
            try handle.seekToEnd(); try handle.write(contentsOf: bytes.dropFirst(first.count)); try handle.close()
            guard try index() > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            guard try index() == 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            // Stop with a >16 MiB line still lacking its newline, then resume after it arrives.
            let body:[String:Any] = ["type":"response_item","timestamp":"2026-09-19T10:00:00Z",
                "payload":["type":"function_call_output","output":String(repeating:"x",count:17*1024*1024)]]
            var pending=bytes;pending.append(try JSONSerialization.data(withJSONObject:body,options:.sortedKeys))
            try pending.write(to:path,options:.atomic)
            let halfWorker=UsageIndexWorker(),halfDone=DispatchSemaphore(value:0)
            var checked=false,halfFailure:UsageIndexError?
            let id=UsageIndexWorker.sourceID(root:"test",logicalID:"one")
            halfWorker.start(directory:directory,sources:[source],rootID:"test") { progress in
                if let error=progress.error { halfFailure=error }
                if !checked,progress.rawBytes>=pending.count {
                    checked=true
                    halfWorker.perform({ store in
                        guard let checkpoint=try store.checkpoint(source:id),checkpoint.offset==pending.count else { checked=false;return }
                        guard try store.completeOffset(source:id,checkpoint:checkpoint)==bytes.count,
                            try !store.observationIsCovered(source:id,revision:Int64.max) else { throw UsageIndexError.databaseFailure }
                    },completion:{ error in
                        if let error { halfFailure=error;checked=true }
                        if checked { halfWorker.stop { halfDone.signal() } }
                    })
                }
            }
            guard halfDone.wait(timeout:.now()+25) == .success else { halfWorker.stop();throw UsageIndexError.cancelled }
            if let halfFailure { throw halfFailure }
            let tail=try FileHandle(forWritingTo:path);try tail.seekToEnd();try tail.write(contentsOf:Data([10]));try tail.close()
            guard try index()<256*1024,try total()==175 else { throw UsageIndexError.databaseFailure }
            guard let zstd = UsageCompressedSource.executableURL else { throw UsageIndexError.resourceLimited }
            let compressed = path.appendingPathExtension("zst")
            func compress(_ contents: Data) throws {
                let input = root.appendingPathComponent("compression-input.jsonl")
                let output = root.appendingPathComponent("compression-output.zst")
                try contents.write(to: input, options: .atomic)
                let process = Process()
                process.executableURL = zstd
                process.arguments = ["-q", "-f", input.path, "-o", output.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw UsageIndexError.cacheInvalid }
                try Data(contentsOf: output).write(to: compressed, options: .atomic)
            }
            // Compression preserves one logical source even while state.sqlite retains its old path.
            try bytes.write(to: path, options: .atomic)
            guard try index() > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            try compress(bytes)
            try FileManager.default.removeItem(at: path)
            guard try index() > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            do {
                let migrated = try UsageIndexStore(directory: directory)
                guard try migrated.scalar("SELECT count(*) FROM source") == 1,
                      try migrated.rows("SELECT locator FROM source", limit: 1).first?.first?.text == compressed.path else {
                    throw UsageIndexError.databaseFailure
                }
            }
            guard try index() == 0, try total() == 175 else { throw UsageIndexError.databaseFailure }

            // A cold compressed source also accepts an explicit .zst locator and survives helper restarts.
            directory = root.appendingPathComponent("compressed-index")
            source = UsageDiscoveredSource(runtime: "codex", logicalID: "one", locator: compressed.path,
                model: "gpt-5", project: "fixture", updatedAt: 0)
            guard try index() > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            guard try index() == 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            try compress(Data(first))
            guard try index() > 0, try total() == 100 else { throw UsageIndexError.databaseFailure }

            var manyLines = bytes
            for _ in 0..<450 { manyLines.append(contentsOf: "{}\n".utf8) }
            try compress(manyLines)
            guard try index(minimumBatches: 3) > 0, try total() == 175 else { throw UsageIndexError.databaseFailure }
            guard try index() == 0, try total() == 175 else { throw UsageIndexError.databaseFailure }

            // Keep an unfinished mirror alive, then stop while retaining the worker itself.
            let marker = Data("{\"type\":\"fixture-marker\",\"id\":\"\(UUID().uuidString)\"}\n".utf8)
            var unfinished = marker
            unfinished.append(bytes); unfinished.append(contentsOf: "{}".utf8)
            try compress(unfinished)
            let stoppingWorker = UsageIndexWorker(), stopDone = DispatchSemaphore(value: 0)
            var stopRequested = false
            var mirrorDirectories: [URL] = []
            var stopFailure: UsageIndexError?
            stoppingWorker.start(directory: root.appendingPathComponent("stop-index"), sources: [source], rootID: "stop") { progress in
                if let error = progress.error { stopFailure = error }
                guard !stopRequested, progress.rawBytes > 0 || stopFailure != nil else { return }
                stopRequested = true
                do {
                    let directories = try FileManager.default.contentsOfDirectory(
                        at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)
                    for candidate in directories where candidate.lastPathComponent.hasPrefix("codexu-parser-") {
                        guard let handle = try? FileHandle(forReadingFrom: candidate.appendingPathComponent("source.jsonl")) else { continue }
                        defer { try? handle.close() }
                        if (try? handle.read(upToCount: marker.count)) == marker { mirrorDirectories.append(candidate) }
                    }
                    guard !mirrorDirectories.isEmpty else { throw UsageIndexError.databaseFailure }
                } catch { stopFailure = error as? UsageIndexError ?? .databaseFailure }
                stoppingWorker.stop { stopDone.signal() }
            }
            guard stopDone.wait(timeout: .now() + 20) == .success else {
                stoppingWorker.stop(); throw UsageIndexError.cancelled
            }
            if let stopFailure { throw stopFailure }
            try withExtendedLifetime(stoppingWorker) {
                guard mirrorDirectories.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) else {
                    throw UsageIndexError.databaseFailure
                }
            }

            // Corrupt compression must fail before it can publish a successful empty batch.
            try Data("invalid zstd frame".utf8).write(to: compressed, options: .atomic)
            var rejected = false
            do {
                _ = try UsageParseHelper().parse(UsageParseRequest(id: UUID().uuidString, path: compressed.path,
                    targetEnd: 0, checkpoint: CodexIndexCheckpoint(), previousStamp: nil))
            } catch { rejected = true }
            guard rejected, try total() == 175 else { throw UsageIndexError.databaseFailure }
            print("history worker: cold ingestion, zero-body restart, atomic replacement, append and compressed-source parity passed")
            return true
        } catch {
            print("history worker failed: \(error)")
            return false
        }
    }
}

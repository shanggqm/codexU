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
            let directory = root.appendingPathComponent("index")
            let source = UsageDiscoveredSource(runtime: "codex", logicalID: "one", locator: path.path,
                model: "gpt-5", project: "fixture", updatedAt: 0)
            func index() throws -> Int {
                let worker = UsageIndexWorker()
                let finished = DispatchSemaphore(value: 0)
                let stopped = DispatchSemaphore(value: 0)
                var rawBytes = 0
                var failure: UsageIndexError?
                var signalled = false
                worker.start(directory: directory, sources: [source], rootID: "test") { progress in
                    rawBytes = progress.rawBytes
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
            print("history worker: cold ingestion, zero-body restart, atomic replacement and append parity passed")
            return true
        } catch {
            print("history worker failed: \(error)")
            return false
        }
    }
}

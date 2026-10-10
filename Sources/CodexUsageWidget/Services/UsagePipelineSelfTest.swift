import Foundation

enum UsagePipelineSelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tests/fixtures/history-index/codex-counters.jsonl")
            let claude = directory.appendingPathComponent("claude.jsonl")
            try Data((#"{"timestamp":"2026-09-18T10:00:00Z","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":2}}}"# + "\n").utf8).write(to: claude)
            let sources = [
                UsageDiscoveredSource(runtime: "codex", logicalID: "one", locator: fixture.path, model: nil, project: "fixture", updatedAt: 0),
                UsageDiscoveredSource(runtime: "claude-code", logicalID: "two", locator: claude.path, model: nil, project: "fixture", updatedAt: 0)
            ]
            let worker = UsageIndexWorker()
            let ready = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0), stopped = DispatchSemaphore(value: 0)
            let now = Date()
            let statistics = StatisticsContext(preference: .init(selection: .utc, fixedIdentifier: "UTC"), now: now)
            var values: [String: Int64] = [:]
            var failure: UsageIndexError?
            var completed = false
            worker.start(directory: directory.appendingPathComponent("index"), sources: [], rootID: "fixture", statistics: statistics,
                onArchive: { store, build in
                    do {
                        let runtime = try store.rows("SELECT runtime FROM report_build WHERE id=?", [.text(build)], limit: 1).first?.first?.text ?? ""
                        let context = try store.ensureProjectionContext(root: "fixture", statistics: statistics, now: now)
                        if let presentation = try store.archivePresentation(context: context, statistics: statistics, runtime: runtime), presentation.complete {
                            values[runtime] = presentation.local.lifetimeTokens
                            if values.count == 2, !completed { completed = true; done.signal() }
                        }
                    } catch { failure = error as? UsageIndexError ?? .databaseFailure; done.signal() }
                }, onProgress: { progress in if let error = progress.error { failure = error } })
            worker.enqueue(sources: sources, rootID: "fixture") { error in failure = error; ready.signal() }
            guard ready.wait(timeout: .now() + 10) == .success, failure == nil else { throw failure ?? UsageIndexError.cancelled }
            worker.perform({ store in
                for runtime in ["codex", "claude-code"] {
                    let scan = try store.beginDiscovery(root: "fixture", runtime: runtime, now: now)
                    try store.execute("UPDATE source SET discovered_epoch=? WHERE runtime=?", [.integer(scan), .text(runtime)])
                    try store.finishDiscovery(scan: scan, complete: true, now: now)
                }
            }, completion: { error in
                if let error { failure = error; done.signal() }
                worker.notifyInventoryChanged()
            })
            guard done.wait(timeout: .now() + 30) == .success else { worker.stop(); throw UsageIndexError.cancelled }
            worker.stop { stopped.signal() }
            guard stopped.wait(timeout: .now() + 5) == .success else { throw UsageIndexError.cancelled }
            if let failure { throw failure }
            guard values["codex"] == 175, values["claude-code"] == 12 else { throw UsageIndexError.databaseFailure }
            print("history pipeline: shared two-reader ingestion, both runtime projections, certified inventory and published archives passed")
            return true
        } catch {
            print("history pipeline failed: \(error)")
            return false
        }
    }
}

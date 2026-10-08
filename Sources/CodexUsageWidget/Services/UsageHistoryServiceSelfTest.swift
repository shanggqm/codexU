import Foundation

enum UsageHistoryServiceSelfTest {
    static func run() -> Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        do {
            let project=directory.appendingPathComponent(".claude/projects/fixture")
            try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
            let line = #"{"timestamp":"2026-09-19T10:00:00Z","cwd":"/fixture","message":{"id":"one","model":"claude-sonnet-4","usage":{"input_tokens":30,"output_tokens":5}}}"# + "\n"
            try Data(line.utf8).write(to:project.appendingPathComponent("one.jsonl"))
            let service=UsageHistoryService()
            let completed=DispatchSemaphore(value:0)
            let stopped=DispatchSemaphore(value:0)
            let now=Date()
            var signaled=false
            for zone in ["UTC","Asia/Tokyo","Asia/Shanghai"] {
                let statistics=StatisticsContext(preference:.init(selection:.fixed,fixedIdentifier:zone),now:now)
                let context=RuntimeLoadContext(now:now,homeDirectory:directory,cacheDirectory:directory.appendingPathComponent("cache"),statistics:statistics)
                service.subscribe(context:context) { value in
                    if value.scope == .claudeCode, value.complete, value.local.lifetimeTokens == 35, !signaled {
                        signaled=true;completed.signal()
                    }
                }
            }
            let success=completed.wait(timeout:.now()+30) == .success
            service.stop { stopped.signal() }
            guard stopped.wait(timeout:.now()+10) == .success,success else { throw UsageIndexError.cancelled }
            print("history service: Claude-only discovery and rapid A/B/C context transition passed")
            return true
        } catch {
            print("history service failed: \(error)")
            return false
        }
    }
}

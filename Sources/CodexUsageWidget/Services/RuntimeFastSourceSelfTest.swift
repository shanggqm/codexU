import Foundation

enum RuntimeFastSourceSelfTest {
    static func run() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("codexu-fast-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        do {
            let application = root.appendingPathComponent("Renamed ChatGPT.app", isDirectory: true)
            let native = application.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            let launcher = application.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
            let legacy = application.appendingPathComponent("Contents/Resources/codex")
            let cli = root.appendingPathComponent("bin/codex")
            for executable in [native, launcher, legacy, cli] {
                try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            }
            func located() -> URL? {
                CodexExecutableLocator.resolve(applicationURLs: [application], cliPaths: [cli.path])
            }
            expect(located() == native, "new nested native CLI should be preferred, including a renamed app")
            try fileManager.removeItem(at: native)
            expect(located() == launcher, "new codex-cli/bin layout should be supported")
            try fileManager.removeItem(at: launcher)
            expect(located() == legacy, "legacy app layout must remain supported")
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path)
            expect(located() == cli, "non-executable app entries must fall back to a standard CLI")
            try fileManager.removeItem(at: legacy)
            try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
            expect(located() == cli, "an executable directory must not be launched as a CLI")
            let cliLink = root.appendingPathComponent("linked-codex")
            try fileManager.createSymbolicLink(at: cliLink, withDestinationURL: cli)
            expect(CodexExecutableLocator.resolve(applicationURLs: [], cliPaths: [cliLink.path]) == cliLink,
                   "standard CLI symlinks must remain supported")
            try fileManager.removeItem(at: cli)
            expect(located() == nil, "missing executables must remain unavailable")

            let cache = root.appendingPathComponent("cache", isDirectory: true)
            let statusDirectory = cache.appendingPathComponent("claude-code", isDirectory: true)
            try fileManager.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
            let now = Date()
            let capturedAt = now.addingTimeInterval(-60)
            let context = RuntimeLoadContext(
                now: now,
                homeDirectory: root,
                cacheDirectory: cache,
                statistics: StatisticsContext(preference: .default, now: now)
            )
            let statusURL = statusDirectory.appendingPathComponent("statusline-snapshot.json")
            let statusData = try JSONSerialization.data(withJSONObject: [
                "capturedAt": capturedAt.timeIntervalSince1970,
                "rateLimits": ["fiveHour": ["usedPercentage": 27, "resetsAt": now.addingTimeInterval(300).timeIntervalSince1970]]
            ])
            try statusData.write(to: statusURL)

            // Existing history and tasks must not populate or delay the quota slice.
            let project = root.appendingPathComponent(".claude/projects/test", isDirectory: true)
            try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
            let transcript = "{\"timestamp\":\"2026-09-10T00:00:00Z\",\"message\":{\"id\":\"test\",\"usage\":{\"input_tokens\":123,\"output_tokens\":45}}}\n"
            try Data(transcript.utf8).write(to: project.appendingPathComponent("session.jsonl"))
            let tasks = root.appendingPathComponent(".claude/tasks/test", isDirectory: true)
            try fileManager.createDirectory(at: tasks, withIntermediateDirectories: true)
            try Data("{\"subject\":\"test task\",\"status\":\"pending\"}".utf8).write(to: tasks.appendingPathComponent("1.json"))

            let claude = ClaudeCodeRuntimeProvider().loadQuotaSnapshot(context: context)
            expect(claude.snapshot.quotaReadSucceeded, "Claude bounded statusLine should provide quota")
            expect(claude.snapshot.fiveHourQuota?.usedPercent == 27, "Claude quota value should be preserved")
            expect(claude.snapshot.local == nil && claude.snapshot.taskBoard == nil, "quota slice must not contain history or tasks")
            expect(abs(claude.snapshot.refreshedAt.timeIntervalSince(capturedAt)) < 0.01, "statusLine age must use capture time")

            try Data(repeating: 32, count: 256 * 1_024 + 1).write(to: statusURL)
            let oversized = ClaudeCodeRuntimeProvider().loadQuotaSnapshot(context: context)
            expect(!oversized.snapshot.quotaReadSucceeded, "oversized statusLine must not be read as quota")
            expect(oversized.snapshot.messages.contains(where: { $0.contains("大小上限") }), "oversized snapshot should explain why data is unavailable")

            let server = root.appendingPathComponent("fake-codex")
            let script = #"""
            #!/bin/sh
            while IFS= read -r line; do
                printf '%s\n' "$line" >> "$0.requests"
                case "$line" in
                    *rateLimits*) printf '%s\n' '{"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":23,"windowDurationMins":300,"resetsAt":1800000000},"secondary":null}}}' ;;
                    *usage*) : ;;
                    *account*read*) printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}' ;;
                    *initialize*) printf '%s\n' '{"id":1,"result":{}}' ;;
                esac
            done
            """#
            try Data(script.utf8).write(to: server)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: server.path)
            let started = ProcessInfo.processInfo.systemUptime
            let quota = CodexUsageReader(codexExecutablePath: server.path).loadQuota(context: context)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            expect(quota.quotaReadSucceeded && quota.fiveHourQuota?.usedPercent == 23, "Codex quick source should return account plus normalized quota")
            expect(quota.account?.planType == "plus", "account response must accompany quota")
            expect(quota.local == nil && quota.taskBoard == nil && quota.cloudLifetimeTokens == nil, "Codex quota must remain independent of history, tasks, and optional cloud usage")
            expect(elapsed < 2, "responsive quota should return immediately without waiting for cloud usage")
            let requests = try String(contentsOfFile: server.path + ".requests", encoding: .utf8)
            let methods = requests.split(separator: "\n").compactMap { line -> String? in
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                return object["method"] as? String
            }
            expect(!methods.contains("account/usage/read"), "quick path should not request optional cloud usage")

            let unconfirmed = root.appendingPathComponent("unconfirmed-codex")
            let unconfirmedScript = script.replacingOccurrences(
                of: #"{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}"#,
                with: #"{"id":2,"error":{"message":"account unavailable"}}"#
            )
            try Data(unconfirmedScript.utf8).write(to: unconfirmed)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unconfirmed.path)
            let unconfirmedQuota = CodexUsageReader(codexExecutablePath: unconfirmed.path).loadQuota(context: context)
            expect(!unconfirmedQuota.quotaReadSucceeded && unconfirmedQuota.fiveHourQuota == nil, "quota must not be published as current when account confirmation failed")

            let silent = root.appendingPathComponent("silent-codex")
            try Data("#!/bin/sh\nwhile IFS= read -r line; do :; done\n".utf8).write(to: silent)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: silent.path)
            let timeoutStart = ProcessInfo.processInfo.systemUptime
            let timeout = CodexUsageReader(codexExecutablePath: silent.path).loadQuota(context: context)
            let timeoutElapsed = ProcessInfo.processInfo.systemUptime - timeoutStart
            expect(!timeout.quotaReadSucceeded, "silent source must not invent quota")
            expect(timeout.messages.contains(where: { $0.contains("超时") }), "silent source should end with a timeout state")
            expect(timeoutElapsed >= 11.8 && timeoutElapsed < 12.5, "quota request timeout should be bounded independently of the foreground deadline")
        } catch {
            failures.append("fixture failed: \(error)")
        }

        if failures.isEmpty {
            print("Runtime fast source self-test passed")
            return true
        }
        failures.forEach { print("Runtime fast source self-test failed: \($0)") }
        return false
    }
}

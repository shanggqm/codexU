import Foundation

enum AgentSelectionSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        testStoredIdentifiers(failures: &failures)
        testSelectionPersistence(failures: &failures)
        testProviderIsolation(failures: &failures)
        testMissingRuntimeDoesNotFallBack(failures: &failures)

        if failures.isEmpty {
            print("agent selection self-test passed")
            return true
        }
        failures.forEach { print("agent selection self-test failed: \($0)") }
        return false
    }

    private static func testStoredIdentifiers(failures: inout [String]) {
        let expected: [(String, RuntimeScope)] = [
            ("openclaw", .openClaw),
            ("open-claw", .openClaw),
            ("claudecode", .claudeCode),
            ("claude-code", .claudeCode),
            ("hermes", .hermes)
        ]
        for (value, scope) in expected where RuntimeScope.storedIdentifier(value) != scope {
            failures.append("stored identifier \(value) did not map to \(scope.runtimeId)")
        }
    }

    private static func testSelectionPersistence(failures: inout [String]) {
        let suite = "codexU.agent-selection-self-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            failures.append("could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = AppSettings(defaults: defaults)
        if initial.selectedAgentRuntime != .openClaw
            || initial.visibleRuntimeScopes != [.codex, .openClaw] {
            failures.append("fresh install did not default to Codex + OpenClaw")
        }
        if !initial.selectAgentRuntime(.hermes)
            || initial.visibleRuntimeScopes != [.codex, .hermes] {
            failures.append("Hermes selection did not replace the companion Agent")
        }
        if initial.selectAgentRuntime(.codex) || initial.selectedAgentRuntime != .hermes {
            failures.append("Codex was accepted as the replaceable companion Agent")
        }

        let restored = AppSettings(defaults: defaults)
        if restored.selectedAgentRuntime != .hermes
            || restored.visibleRuntimeScopes != [.codex, .hermes] {
            failures.append("selected companion Agent was not persisted")
        }

        defaults.removeObject(forKey: "codexU.selectedAgentRuntime.v1")
        defaults.set(["codex", "claude-code"], forKey: "codexU.visibleRuntimeScopes")
        let migrated = AppSettings(defaults: defaults)
        if migrated.selectedAgentRuntime != .claudeCode {
            failures.append("legacy visible runtime preference did not migrate to Claude Code")
        }
    }

    private static func testProviderIsolation(failures: inout [String]) {
        let providers = RuntimeScope.allCases.map(CountingRuntimeProvider.init)
        let reader = MultiRuntimeUsageReader(
            registry: RuntimeProviderRegistry(providers: providers),
            aggregator: AgentUsageAggregator()
        )
        let snapshot = reader.load(scopes: [.codex, .hermes])
        let loadedScopes = Set(snapshot.runtimes.map(\.scope))
        if loadedScopes != Set([.codex, .hermes]) {
            failures.append("runtime reader returned unselected providers")
        }
        for provider in providers {
            let expectedCount = provider.scope == .codex || provider.scope == .hermes ? 1 : 0
            if provider.snapshotLoadCount != expectedCount {
                failures.append("\(provider.scope.runtimeId) provider load count was \(provider.snapshotLoadCount), expected \(expectedCount)")
            }
        }
    }

    private static func testMissingRuntimeDoesNotFallBack(failures: inout [String]) {
        let codex = RuntimeUsageSnapshot(
            scope: .codex,
            snapshot: .empty,
            status: .unavailable,
            quotaSourceLabel: "test",
            usageSourceLabel: "test"
        )
        let multi = MultiRuntimeUsageSnapshot(
            refreshedAt: Date(),
            runtimes: [codex],
            aggregate: .empty,
            statisticsIdentity: .empty()
        )
        let missing = multi.displaySnapshot(for: .hermes)
        if missing.local != nil || missing.taskBoard != nil || missing.quotaReadSucceeded {
            failures.append("missing Hermes runtime fell back to another provider")
        }
    }
}

private final class CountingRuntimeProvider: RuntimeUsageProvider {
    let scope: RuntimeScope
    private(set) var snapshotLoadCount = 0

    init(_ scope: RuntimeScope) {
        self.scope = scope
    }

    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot {
        snapshotLoadCount += 1
        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: .empty,
            status: .unavailable,
            quotaSourceLabel: "test",
            usageSourceLabel: "test"
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        nil
    }
}

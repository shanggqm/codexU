import Foundation

struct TaskNavigationTarget: Equatable {
    let codexThreadID: String

    private init(codexThreadID: String) {
        self.codexThreadID = codexThreadID
    }

    static func codexThread(id rawValue: String?) -> TaskNavigationTarget? {
        guard let rawValue else { return nil }
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false)
        let expectedLengths = [8, 4, 4, 4, 12]
        guard parts.count == expectedLengths.count,
              zip(parts, expectedLengths).allSatisfy({ part, length in
                  part.count == length && part.allSatisfy(\.isHexDigit)
              }),
              let uuid = UUID(uuidString: candidate) else {
            return nil
        }
        return TaskNavigationTarget(codexThreadID: uuid.uuidString.lowercased())
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(codexThreadID)"
        return components.url
    }
}

enum TaskPrimaryAction: Equatable {
    case showDetail
}

func taskPrimaryAction(for item: TaskItem) -> TaskPrimaryAction {
    .showDetail
}

extension TaskItem {
    var codexNavigationTarget: TaskNavigationTarget? {
        guard source == .codex else { return nil }
        return navigationTarget
    }
}

enum TaskNavigationSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        let validID = "019f6334-12a8-7f90-b8ff-624e315204d6"
        let validTarget = TaskNavigationTarget.codexThread(id: validID)
        if validTarget?.codexThreadID != validID {
            failures.append("valid Codex thread ID was not preserved")
        }
        if validTarget?.url?.absoluteString != "codex://threads/\(validID)" {
            failures.append("valid Codex thread deep link was incorrect")
        }
        if TaskNavigationTarget.codexThread(id: validID.uppercased())?.codexThreadID != validID {
            failures.append("uppercase UUID was not canonicalized")
        }

        let invalidValues: [String?] = [
            nil,
            "",
            "not-a-thread",
            "codex://threads/\(validID)",
            validID + "/extra",
            "../../\(validID)",
            "{\(validID)}"
        ]
        for value in invalidValues where TaskNavigationTarget.codexThread(id: value) != nil {
            failures.append("invalid Codex thread ID produced a navigation target")
        }

        let codexItem = makeItem(source: .codex, navigationTarget: validTarget)
        if codexItem.codexNavigationTarget != validTarget {
            failures.append("Codex task lost its independent navigation target")
        }
        if taskPrimaryAction(for: codexItem) != .showDetail {
            failures.append("Codex task primary action no longer shows detail")
        }

        let openClawItem = makeItem(source: .openClaw, navigationTarget: validTarget)
        if openClawItem.codexNavigationTarget != nil {
            failures.append("non-Codex task exposed Codex navigation")
        }
        if taskPrimaryAction(for: openClawItem) != .showDetail {
            failures.append("OpenClaw task primary action no longer shows detail")
        }

        let automationItem = makeItem(source: .codex, navigationTarget: nil)
        if automationItem.codexNavigationTarget != nil {
            failures.append("Codex automation exposed thread navigation")
        }

        if failures.isEmpty {
            print("task navigation self-test passed")
            return true
        }
        failures.forEach { print("task navigation self-test failed: \($0)") }
        return false
    }

    private static func makeItem(
        source: RuntimeScope,
        navigationTarget: TaskNavigationTarget?
    ) -> TaskItem {
        TaskItem(
            id: "self-test",
            code: "TEST",
            title: "Self test",
            detail: "",
            chip: "Test",
            updatedAt: nil,
            tokens: nil,
            kind: .active,
            source: source,
            summary: nil,
            recentReply: nil,
            navigationTarget: navigationTarget
        )
    }
}

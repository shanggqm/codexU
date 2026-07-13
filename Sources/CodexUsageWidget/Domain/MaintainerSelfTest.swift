import Foundation

enum MaintainerSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        var task = fixtureTask(now: now)
        expect(task.status == .discovered, "new task starts discovered")
        do {
            try task.beginReview(at: now)
            expect(task.status == .reviewing, "beginReview transition")
            let review = MaintainerReview(verdict: "comment", summary: "summary", markdown: "body", completedAt: now)
            try task.completeReview(review, threadID: "thread-test", at: now)
            expect(task.status == .awaitingApproval, "completeReview transition")
            expect(task.codexThreadID == "thread-test", "thread id persistence")
            try task.beginPublishing(at: now)
            try task.completePublishing(commentURL: URL(string: "https://github.com/o/r/issues/1#issuecomment-1"), at: now)
            expect(task.status == .published, "publishing transition")
        } catch {
            failures.append("valid transition threw: \(error)")
        }

        do {
            var invalid = fixtureTask(now: now)
            try invalid.beginPublishing(at: now)
            failures.append("invalid publishing transition was accepted")
        } catch {
            expect(true, "invalid transition rejected")
        }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexu-maintainer-selftest-\(UUID().uuidString).json")
        let repository = MaintainerTaskRepository(fileURL: temporary)
        do {
            try repository.save([task])
            expect(repository.load() == [task], "task persistence round trip")
        } catch {
            failures.append("task persistence failed: \(error)")
        }
        try? FileManager.default.removeItem(at: temporary)

        let marker = GitHubMaintainerClient(ghPath: "/bin/false").commentMarker(for: fixtureTask(now: now))
        expect(marker.contains("codexu-maintainer:o/r:issue:1"), "comment marker contains stable task id")
        expect(MaintainerTask.stableID(repository: "O/R", kind: .issue, number: 1) == "o/r:issue:1", "stable id normalization")

        let validConfig = MaintainerConfiguration(
            enabled: true,
            repository: "o/r",
            localRepositoryPath: "/tmp/repo",
            triggerLabel: "codex:review",
            pollIntervalSeconds: 60
        )
        expect(validConfig.isValid, "valid configuration")
        var invalidConfig = validConfig
        invalidConfig.repository = "missing-slash"
        expect(!invalidConfig.isValid, "invalid repository rejected")

        if failures.isEmpty {
            print("maintainer self-test passed")
            return true
        }
        failures.forEach { fputs("maintainer self-test failed: \($0)\n", stderr) }
        return false
    }

    private static func fixtureTask(now: Date) -> MaintainerTask {
        MaintainerTask(
            id: MaintainerTask.stableID(repository: "o/r", kind: .issue, number: 1),
            repository: "o/r",
            number: 1,
            kind: .issue,
            title: "test",
            url: URL(string: "https://github.com/o/r/issues/1")!,
            author: "author",
            sourceUpdatedAt: now,
            revision: "rev-1",
            status: .discovered,
            discoveredAt: now,
            updatedAt: now,
            codexThreadID: nil,
            review: nil,
            errorMessage: nil,
            publishedCommentURL: nil
        )
    }
}

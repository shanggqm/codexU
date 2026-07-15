import Foundation

enum CodexRateLimitNormalizerSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        let fiveHour = window(usedPercent: 12, durationMins: 300)
        let sevenDay = window(usedPercent: 34, durationMins: 10_080)

        let standard = CodexRateLimitNormalizer.normalize([fiveHour, sevenDay])
        expect(standard.fiveHour == fiveHour, "standard response should classify the 300-minute window as 5h")
        expect(standard.sevenDay == sevenDay, "standard response should classify the 10080-minute window as 7d")
        expect(
            CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: true,
                hasMalformedWindow: false,
                normalized: standard
            ),
            "a complete known response should define an authoritative topology"
        )

        let weeklyOnly = CodexRateLimitNormalizer.normalize([sevenDay, nil])
        expect(weeklyOnly.fiveHour == nil, "weekly-only response must not populate the 5h quota")
        expect(weeklyOnly.sevenDay == sevenDay, "weekly-only response should keep the 7d quota")
        expect(
            CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: true,
                hasMalformedWindow: false,
                normalized: weeklyOnly
            ),
            "a weekly-only response should still define an authoritative topology"
        )

        let fiveHourOnly = CodexRateLimitNormalizer.normalize([fiveHour, nil])
        expect(fiveHourOnly.fiveHour == fiveHour, "5h-only response should keep the 5h quota")
        expect(fiveHourOnly.sevenDay == nil, "5h-only response must not populate the 7d quota")

        let reversed = CodexRateLimitNormalizer.normalize([sevenDay, fiveHour])
        expect(reversed.fiveHour == fiveHour, "slot order must not change the 5h classification")
        expect(reversed.sevenDay == sevenDay, "slot order must not change the 7d classification")

        let other = window(usedPercent: 56, durationMins: 43_200)
        let futureWindow = CodexRateLimitNormalizer.normalize([other, sevenDay])
        expect(futureWindow.fiveHour == nil, "an unknown duration must not be labeled as 5h")
        expect(futureWindow.sevenDay == sevenDay, "known windows should survive alongside unknown durations")
        expect(futureWindow.unclassified == [other], "unknown durations should remain available for diagnostics")
        expect(
            !CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: true,
                hasMalformedWindow: false,
                normalized: futureWindow
            ),
            "unknown windows must not be mistaken for an authoritative no-limit topology"
        )

        let missingDuration = window(usedPercent: 78, durationMins: nil)
        let incomplete = CodexRateLimitNormalizer.normalize([missingDuration, nil])
        expect(incomplete.fiveHour == nil && incomplete.sevenDay == nil, "missing duration must fail closed")
        expect(incomplete.unclassified == [missingDuration], "missing duration should remain available for diagnostics")

        let duplicateFiveHour = CodexRateLimitNormalizer.normalize([
            fiveHour,
            window(usedPercent: 90, durationMins: 300)
        ])
        expect(duplicateFiveHour.fiveHour == nil, "duplicate 5h windows must be treated as ambiguous")
        expect(duplicateFiveHour.fiveHourMatchCount == 2, "duplicate 5h windows should be reported")
        expect(
            !CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: true,
                hasMalformedWindow: false,
                normalized: duplicateFiveHour
            ),
            "duplicate windows must not define an authoritative topology"
        )
        expect(
            !CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: false,
                hasMalformedWindow: false,
                normalized: CodexRateLimitNormalizer.normalize([nil, nil])
            ),
            "missing window fields must not be interpreted as an authoritative zero-limit response"
        )
        expect(
            !CodexRateLimitNormalizer.isAuthoritative(
                hasWindowFields: true,
                hasMalformedWindow: true,
                normalized: CodexRateLimitNormalizer.normalize([nil, nil])
            ),
            "malformed window payloads must not be interpreted as an authoritative zero-limit response"
        )

        let weeklyRuntime = runtime(
            status: .available,
            quotaReadSucceeded: true,
            fiveHour: nil,
            sevenDay: sevenDay
        )
        let failedRefresh = runtime(
            status: .localOnly,
            quotaReadSucceeded: false,
            fiveHour: nil,
            sevenDay: nil
        )
        let retained = RuntimeQuotaContinuity.reconcile(
            previous: [weeklyRuntime],
            incoming: [failedRefresh]
        )[0]
        expect(retained.status == .stale, "a failed refresh should retain the last confirmed quota as stale")
        expect(retained.snapshot.sevenDayQuota == sevenDay, "a failed refresh must not collapse the last 7d-only layout")
        expect(!retained.snapshot.quotaReadSucceeded, "retained stale quota data must not look like a fresh response")
        let retainedAgain = RuntimeQuotaContinuity.reconcile(
            previous: [retained],
            incoming: [failedRefresh]
        )[0]
        expect(
            retainedAgain.quotaSourceLabel == "test · stale",
            "repeated failures should not append duplicate stale source markers"
        )

        let dualRuntime = runtime(
            status: .available,
            quotaReadSucceeded: true,
            fiveHour: fiveHour,
            sevenDay: sevenDay
        )
        let partiallyParsedRefresh = runtime(
            status: .localOnly,
            quotaReadSucceeded: false,
            fiveHour: nil,
            sevenDay: sevenDay
        )
        let retainedDual = RuntimeQuotaContinuity.reconcile(
            previous: [dualRuntime],
            incoming: [partiallyParsedRefresh]
        )[0]
        expect(
            retainedDual.snapshot.fiveHourQuota == fiveHour
                && retainedDual.snapshot.sevenDayQuota == sevenDay,
            "a non-authoritative partial refresh must retain the complete confirmed topology"
        )
        expect(retainedDual.status == .stale, "a retained partial refresh must be marked stale")

        let authoritativeNoLimit = runtime(
            status: .available,
            quotaReadSucceeded: true,
            fiveHour: nil,
            sevenDay: nil
        )
        let cleared = RuntimeQuotaContinuity.reconcile(
            previous: [weeklyRuntime],
            incoming: [authoritativeNoLimit]
        )[0]
        expect(cleared.status == .available, "a successful zero-limit response should stay authoritative")
        expect(
            cleared.snapshot.fiveHourQuota == nil && cleared.snapshot.sevenDayQuota == nil,
            "a successful zero-limit response must clear the previous topology"
        )

        if failures.isEmpty {
            print("Codex rate-limit normalizer self-test passed")
            return true
        }

        for failure in failures {
            print("Codex rate-limit normalizer self-test failed: \(failure)")
        }
        return false
    }

    private static func window(usedPercent: Double, durationMins: Int?) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowDurationMins: durationMins,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func runtime(
        status: RuntimeMenuStatus,
        quotaReadSucceeded: Bool,
        fiveHour: RateWindow?,
        sevenDay: RateWindow?
    ) -> RuntimeUsageSnapshot {
        RuntimeUsageSnapshot(
            scope: .codex,
            snapshot: UsageSnapshot(
                refreshedAt: Date(timeIntervalSince1970: 1_800_000_000),
                account: nil,
                limitId: "codex",
                limitName: "Codex",
                quotaReadSucceeded: quotaReadSucceeded,
                fiveHourQuota: fiveHour,
                sevenDayQuota: sevenDay,
                credits: nil,
                cloudLifetimeTokens: nil,
                local: nil,
                taskBoard: nil,
                messages: []
            ),
            status: status,
            quotaSourceLabel: "test",
            usageSourceLabel: "test"
        )
    }
}

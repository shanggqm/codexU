import Foundation

struct CodexTokenCounterSample: Equatable {
    let inputTokens: Int64?
    let cachedInputTokens: Int64?
    let outputTokens: Int64?
    let reasoningOutputTokens: Int64?
    let totalTokens: Int64?

    var hasNegativeValue: Bool {
        [inputTokens, cachedInputTokens, outputTokens, reasoningOutputTokens, totalTokens]
            .compactMap { $0 }
            .contains { $0 < 0 }
    }

    func snapshot(missingFrom previous: TokenBreakdown = .zero) -> TokenBreakdown {
        TokenBreakdown(
            inputTokens: max(inputTokens ?? previous.inputTokens, 0),
            cachedInputTokens: max(cachedInputTokens ?? previous.cachedInputTokens, 0),
            outputTokens: max(outputTokens ?? previous.outputTokens, 0),
            reasoningOutputTokens: max(reasoningOutputTokens ?? previous.reasoningOutputTokens, 0),
            totalTokens: max(totalTokens ?? previous.totalTokens, 0)
        )
    }
}

struct CodexTokenCounterState {
    var cumulative: TokenBreakdown?
}

enum CodexTokenCounterNormalizer {
    static func consume(
        cumulative sample: CodexTokenCounterSample?,
        lastUsage: CodexTokenCounterSample?,
        state: inout CodexTokenCounterState
    ) -> TokenBreakdown? {
        let lastDelta = validatedLastUsage(lastUsage)

        guard let sample, !sample.hasNegativeValue else {
            return nonzero(lastDelta)
        }

        guard let previous = state.cumulative else {
            let current = sample.snapshot()
            state.cumulative = current
            return nonzero(lastDelta ?? current)
        }

        if isConfirmedReset(sample, previous: previous) {
            let current = sample.snapshot()
            state.cumulative = current
            // `last_token_usage` is the event-level delta. A cumulative reset
            // is exactly where it is expected to differ from the new epoch's
            // whole baseline, so never reject it for that mismatch.
            return nonzero(lastDelta ?? current)
        }

        // Cumulative usage fields are expected to be monotonic. Missing fields,
        // temporary zeroes, reclassification, or an auxiliary counter moving
        // backwards must not lower the baseline: otherwise its next recovery
        // would be counted a second time.
        let observed = sample.snapshot(missingFrom: previous)
        let highWater = TokenBreakdown(
            inputTokens: max(previous.inputTokens, observed.inputTokens),
            cachedInputTokens: max(previous.cachedInputTokens, observed.cachedInputTokens),
            outputTokens: max(previous.outputTokens, observed.outputTokens),
            reasoningOutputTokens: max(previous.reasoningOutputTokens, observed.reasoningOutputTokens),
            totalTokens: max(previous.totalTokens, observed.totalTokens)
        )
        let fallback = highWater.delta(from: previous)
        state.cumulative = highWater

        guard !fallback.isZero else { return nil }
        return nonzero(lastDelta ?? fallback)
    }

    private static func validatedLastUsage(_ sample: CodexTokenCounterSample?) -> TokenBreakdown? {
        guard let sample, !sample.hasNegativeValue else { return nil }
        return nonzero(sample.snapshot())
    }

    private static func isConfirmedReset(
        _ sample: CodexTokenCounterSample,
        previous: TokenBreakdown
    ) -> Bool {
        guard let total = sample.totalTokens,
              let input = sample.inputTokens
        else { return false }

        // A single optional counter can move backwards when event schemas or
        // cache classification change. Treat a reset as real only when both
        // the canonical total and its dominant input counter restart.
        return total >= 0
            && input >= 0
            && total < previous.totalTokens
            && input < previous.inputTokens
    }

    private static func nonzero(_ value: TokenBreakdown?) -> TokenBreakdown? {
        guard let value, !value.isZero else { return nil }
        return value
    }
}

enum CodexDetailedUsageSanity {
    static func isSuspicious(_ detailed: Int64, comparedWith approximate: Int64) -> Bool {
        guard approximate >= 1_000_000,
              detailed > approximate,
              detailed - approximate >= 500_000_000
        else { return false }

        return Double(detailed) / Double(approximate) >= 8
    }
}

enum CodexTokenCounterNormalizerSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        func sample(
            input: Int64? = nil,
            cached: Int64? = nil,
            output: Int64? = nil,
            reasoning: Int64? = nil,
            total: Int64? = nil
        ) -> CodexTokenCounterSample {
            CodexTokenCounterSample(
                inputTokens: input,
                cachedInputTokens: cached,
                outputTokens: output,
                reasoningOutputTokens: reasoning,
                totalTokens: total
            )
        }

        var state = CodexTokenCounterState()
        let first = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 80, cached: 50, output: 20, reasoning: 10, total: 100),
            lastUsage: sample(input: 80, cached: 50, output: 20, reasoning: 10, total: 100),
            state: &state
        )
        expect(first?.totalTokens == 100, "first cumulative event should be counted once")

        let sparse = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 120, cached: 70, output: 25, total: 145),
            lastUsage: sample(input: 40, cached: 20, output: 5, reasoning: 0, total: 45),
            state: &state
        )
        expect(sparse == TokenBreakdown(inputTokens: 40, cachedInputTokens: 20, outputTokens: 5, reasoningOutputTokens: 0, totalTokens: 45), "missing auxiliary fields should not trigger a reset")

        let auxiliaryRegression = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 130, cached: 60, output: 27, reasoning: 2, total: 157),
            lastUsage: sample(input: 10, cached: 0, output: 2, reasoning: 0, total: 12),
            state: &state
        )
        expect(auxiliaryRegression?.totalTokens == 12, "auxiliary regression must not replay the cumulative total")
        expect(auxiliaryRegression?.cachedInputTokens == 0, "regressed cache counter should contribute no fallback delta")

        let duplicate = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 130, cached: 60, output: 27, reasoning: 2, total: 157),
            lastUsage: sample(input: 10, cached: 0, output: 2, reasoning: 0, total: 12),
            state: &state
        )
        expect(duplicate == nil, "unchanged cumulative snapshots should be deduplicated")

        let recoveredAuxiliary = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 140, cached: 75, output: 30, reasoning: 12, total: 170),
            lastUsage: sample(input: 10, cached: 5, output: 3, reasoning: 2, total: 13),
            state: &state
        )
        expect(recoveredAuxiliary?.cachedInputTokens == 5, "auxiliary recovery should count only growth above its high-water mark")
        expect(recoveredAuxiliary?.totalTokens == 13, "normal growth should prefer matching last_token_usage")

        let reset = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 80, cached: 40, output: 20, reasoning: 5, total: 100),
            lastUsage: sample(input: 8, cached: 4, output: 2, reasoning: 1, total: 10),
            state: &state
        )
        expect(reset?.totalTokens == 10, "confirmed cumulative reset should prefer the event-level delta")
        expect(reset?.inputTokens == 8, "reset baseline must not replace last_token_usage splits")

        let afterReset = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 90, cached: 45, output: 22, reasoning: 5, total: 112),
            lastUsage: sample(input: 10, cached: 5, output: 2, reasoning: 0, total: 12),
            state: &state
        )
        expect(afterReset?.totalTokens == 12, "events after a confirmed reset should resume normal deltas")

        var repeatedResetState = CodexTokenCounterState()
        var repeatedResetTotal: Int64 = 0
        if let initial = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 1_800, cached: 1_500, output: 200, reasoning: 50, total: 2_000),
            lastUsage: sample(input: 8, cached: 6, output: 2, reasoning: 1, total: 10),
            state: &repeatedResetState
        ) {
            repeatedResetTotal += initial.totalTokens
        }
        for _ in 0..<60 {
            if let resetEvent = CodexTokenCounterNormalizer.consume(
                cumulative: sample(input: 900, cached: 750, output: 100, reasoning: 25, total: 1_000),
                lastUsage: sample(input: 8, cached: 6, output: 2, reasoning: 1, total: 10),
                state: &repeatedResetState
            ) {
                repeatedResetTotal += resetEvent.totalTokens
            }
            if let growthEvent = CodexTokenCounterNormalizer.consume(
                cumulative: sample(input: 1_800, cached: 1_500, output: 200, reasoning: 50, total: 2_000),
                lastUsage: sample(input: 8, cached: 6, output: 2, reasoning: 1, total: 10),
                state: &repeatedResetState
            ) {
                repeatedResetTotal += growthEvent.totalTokens
            }
        }
        expect(repeatedResetTotal == 1_210, "repeated resets must sum event deltas instead of replaying cumulative baselines")

        var lastOnlyState = CodexTokenCounterState()
        let lastOnly = CodexTokenCounterNormalizer.consume(
            cumulative: nil,
            lastUsage: sample(input: 25, cached: 20, output: 3, reasoning: 1, total: 28),
            state: &lastOnlyState
        )
        expect(lastOnly?.totalTokens == 28, "last_token_usage should remain usable without a cumulative snapshot")
        expect(lastOnly?.uncachedInputTokens == 5, "last-only events should preserve token splits")

        var legacyState = CodexTokenCounterState()
        _ = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 1_000, cached: 800, output: 100, reasoning: 50, total: 1_100),
            lastUsage: nil,
            state: &legacyState
        )
        let legacyRegression = CodexTokenCounterNormalizer.consume(
            cumulative: sample(input: 1_010, cached: 0, output: 105, reasoning: 0, total: 1_115),
            lastUsage: nil,
            state: &legacyState
        )
        expect(legacyRegression?.totalTokens == 15, "legacy fallback should use the cumulative total delta")
        expect(legacyRegression?.visibleTotalTokens == 15, "legacy auxiliary regression must not inflate visible totals")

        expect(
            CodexDetailedUsageSanity.isSuspicious(119_100_000_000, comparedWith: 2_000_000_000),
            "extreme detailed/SQLite divergence should trigger the safety fallback"
        )
        expect(
            !CodexDetailedUsageSanity.isSuspicious(2_382_000_000, comparedWith: 2_465_000_000),
            "nearby detailed and SQLite totals should remain on the detailed path"
        )
        expect(
            !CodexDetailedUsageSanity.isSuspicious(2_000_000_000, comparedWith: 0),
            "missing SQLite data must not suppress detailed usage"
        )

        if failures.isEmpty {
            print("Codex token counter normalizer self-test passed")
            return true
        }

        failures.forEach { print("Codex token counter normalizer self-test failed: \($0)") }
        return false
    }
}

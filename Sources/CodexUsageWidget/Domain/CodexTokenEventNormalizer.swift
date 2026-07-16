import Foundation

enum CodexTokenEventNormalizer {
    static func normalizedDelta(
        totalUsage: TokenBreakdown?,
        lastUsage: TokenBreakdown?,
        previousTotal: inout TokenBreakdown
    ) -> TokenBreakdown? {
        if let totalUsage {
            let cumulativeDelta = totalUsage.delta(from: previousTotal)
            previousTotal = totalUsage

            if let lastUsage, !lastUsage.hasNegativeValue {
                return lastUsage
            }

            return clampedToNonnegative(cumulativeDelta)
        }

        guard let lastUsage, !lastUsage.hasNegativeValue else { return nil }
        return lastUsage
    }

    private static func clampedToNonnegative(_ usage: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            inputTokens: max(usage.inputTokens, 0),
            cachedInputTokens: max(usage.cachedInputTokens, 0),
            outputTokens: max(usage.outputTokens, 0),
            reasoningOutputTokens: max(usage.reasoningOutputTokens, 0),
            totalTokens: max(usage.totalTokens, 0)
        )
    }
}

enum CodexTokenEventNormalizerSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        var modernPrevious = TokenBreakdown.zero
        let first = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: usage(input: 1_000, cached: 800, output: 100, reasoning: 20, total: 1_100),
            lastUsage: usage(input: 1_000, cached: 800, output: 100, reasoning: 20, total: 1_100),
            previousTotal: &modernPrevious
        )
        if first?.totalTokens != 1_100 {
            failures.append("first per-turn usage was not preserved")
        }

        let regressed = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: usage(input: 950, cached: 760, output: 98, reasoning: 19, total: 1_048),
            lastUsage: usage(input: 200, cached: 160, output: 10, reasoning: 3, total: 210),
            previousTotal: &modernPrevious
        )
        if regressed?.totalTokens != 210 || regressed?.inputTokens != 200 {
            failures.append("last_token_usage did not override a regressed cumulative snapshot")
        }

        var legacyPrevious = TokenBreakdown.zero
        _ = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: usage(input: 500, cached: 300, output: 50, reasoning: 5, total: 550),
            lastUsage: nil,
            previousTotal: &legacyPrevious
        )
        let legacyIncrease = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: usage(input: 700, cached: 450, output: 70, reasoning: 7, total: 770),
            lastUsage: nil,
            previousTotal: &legacyPrevious
        )
        if legacyIncrease?.totalTokens != 220 || legacyIncrease?.cachedInputTokens != 150 {
            failures.append("legacy monotonic cumulative delta changed")
        }

        let legacyRegression = CodexTokenEventNormalizer.normalizedDelta(
            totalUsage: usage(input: 690, cached: 440, output: 69, reasoning: 6, total: 759),
            lastUsage: nil,
            previousTotal: &legacyPrevious
        )
        if legacyRegression != .zero {
            failures.append("legacy cumulative regression was counted as a fresh total")
        }

        if failures.isEmpty {
            print("Codex token event normalizer self-test passed")
            return true
        }

        failures.forEach { print("Codex token event normalizer self-test failed: \($0)") }
        return false
    }

    private static func usage(
        input: Int64,
        cached: Int64,
        output: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        TokenBreakdown(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
    }
}

import Foundation

enum UsageTrendMetric: String, CaseIterable, Identifiable {
    case tokens
    case estimatedCostUSD

    var id: String { rawValue }

    func value(for bucket: UsageDayBucket) -> Double {
        switch self {
        case .tokens:
            return Double(bucket.tokens)
        case .estimatedCostUSD:
            return bucket.usage.estimatedCostUSD
        }
    }
}

enum UsageTrendWindow: Int, CaseIterable, Identifiable, Equatable {
    case thirtyDays = 30
    case sixtyDays = 60
    case ninetyDays = 90
    case oneEightyDays = 180

    static let storageKey = "codexU.usageTrend.windowDays"
    static let defaultWindow: UsageTrendWindow = .thirtyDays

    var id: Int { rawValue }
    var dayCount: Int { rawValue }

    static func storedOrDefault(defaults: UserDefaults = .standard) -> UsageTrendWindow {
        guard let stored = UsageTrendWindow(rawValue: defaults.integer(forKey: storageKey)) else {
            return defaultWindow
        }
        return stored
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

struct ModelUsageMetricSummary: Equatable {
    let recentValue: Double
    let dailyAverageValue: Double
    let changePercent: Double?
    let isNewActivity: Bool

    static func make(from trend: UsageTrend, metric: UsageTrendMetric) -> ModelUsageMetricSummary {
        let recentBuckets = Array(trend.dayBuckets.suffix(7))
        let previousBuckets = Array(trend.dayBuckets.dropLast(7).suffix(7))
        let recentValue = recentBuckets.reduce(0) { $0 + metric.value(for: $1) }
        let previousValue = previousBuckets.reduce(0) { $0 + metric.value(for: $1) }
        let changePercent: Double?
        let isNewActivity: Bool
        if previousValue > 0 {
            changePercent = (recentValue - previousValue) / previousValue * 100
            isNewActivity = false
        } else {
            changePercent = nil
            isNewActivity = recentValue > 0
        }

        return ModelUsageMetricSummary(
            recentValue: recentValue,
            dailyAverageValue: recentValue / 7,
            changePercent: changePercent,
            isNewActivity: isNewActivity
        )
    }
}

struct ModelUsageAreaSeries: Identifiable, Equatable, Codable {
    let id: String
    let model: String?
    let isAggregate: Bool
    let dayBuckets: [UsageDayBucket]
    let activeDayCount: Int
    let sourceQuality: UsageSourceQuality
    let costAvailable: Bool
    let usesReferencePricing: Bool
}

enum ModelUsageAreaSeriesBuilder {
    static let visibleModelLimit = 8
    static let otherModelID = "other-models"

    static func build(from trend: UsageTrend) -> [ModelUsageAreaSeries] {
        build(
            modelTrends: trend.modelTrends ?? [],
            dateBuckets: trend.dayBuckets,
            sourceQuality: trend.sourceQuality
        )
    }

    static func build(from trend: UsageTrend, window: UsageTrendWindow) -> [ModelUsageAreaSeries] {
        let visibleBuckets = dateBuckets(from: trend, window: window)
        return build(
            modelTrends: trend.modelTrends ?? [],
            dateBuckets: visibleBuckets,
            sourceQuality: trend.sourceQuality
        )
    }

    static func dateBuckets(
        from trend: UsageTrend,
        window: UsageTrendWindow,
        referenceDate: Date = Date()
    ) -> [UsageDayBucket] {
        Array(
            trend.dayBuckets
                .filter { $0.date <= referenceDate }
                .suffix(window.dayCount)
        )
    }

    static func build(
        modelTrends: [ModelUsageTrend],
        dateBuckets: [UsageDayBucket],
        sourceQuality: UsageSourceQuality
    ) -> [ModelUsageAreaSeries] {
        guard !dateBuckets.isEmpty else { return [] }

        let visibleDateIDs = Set(dateBuckets.map(\.id))
        let recentDateIDs = Set(dateBuckets.suffix(7).map(\.id))
        let sortedTrends = modelTrends
            .filter { trend in
                trend.dayBuckets.contains { bucket in
                    visibleDateIDs.contains(bucket.id) && bucket.tokens > 0
                }
            }
            .sorted { lhs, rhs in
                sortModels(
                    lhs,
                    rhs,
                    visibleDateIDs: visibleDateIDs,
                    recentDateIDs: recentDateIDs
                )
            }
        let visible = Array(sortedTrends.prefix(visibleModelLimit))
        let remainder = Array(sortedTrends.dropFirst(visibleModelLimit))

        var result = visible.map {
            makeSeries(
                from: [$0],
                dateBuckets: dateBuckets,
                sourceQuality: sourceQuality,
                isAggregate: false,
                id: $0.id,
                model: $0.model
            )
        }

        if !remainder.isEmpty {
            result.append(
                makeSeries(
                    from: remainder,
                    dateBuckets: dateBuckets,
                    sourceQuality: sourceQuality,
                    isAggregate: true,
                    id: otherModelID,
                    model: nil
                )
            )
        }
        return result
    }

    private static func sortModels(
        _ lhs: ModelUsageTrend,
        _ rhs: ModelUsageTrend,
        visibleDateIDs: Set<String>,
        recentDateIDs: Set<String>
    ) -> Bool {
        let lhsTotal = lhs.dayBuckets
            .filter { visibleDateIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.tokens }
        let rhsTotal = rhs.dayBuckets
            .filter { visibleDateIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.tokens }
        if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }

        let lhsRecent = lhs.dayBuckets
            .filter { recentDateIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.tokens }
        let rhsRecent = rhs.dayBuckets
            .filter { recentDateIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.tokens }
        if lhsRecent != rhsRecent { return lhsRecent > rhsRecent }

        return lhs.id < rhs.id
    }

    private static func makeSeries(
        from trends: [ModelUsageTrend],
        dateBuckets: [UsageDayBucket],
        sourceQuality: UsageSourceQuality,
        isAggregate: Bool,
        id: String,
        model: String?
    ) -> ModelUsageAreaSeries {
        let lookup = trends.reduce(into: [String: UsageDayBucket]()) { result, trend in
            for bucket in trend.dayBuckets {
                var usage = result[bucket.id]?.usage ?? .zero
                usage.add(tokens: bucket.usage.tokens, costUSD: bucket.usage.estimatedCostUSD)
                result[bucket.id] = UsageDayBucket(
                    id: bucket.id,
                    date: bucket.date,
                    usage: usage,
                    sourceQuality: sourceQuality
                )
            }
        }

        let buckets = dateBuckets.map { reference in
            lookup[reference.id] ?? UsageDayBucket(
                id: reference.id,
                date: reference.date,
                usage: .zero,
                sourceQuality: sourceQuality
            )
        }

        return ModelUsageAreaSeries(
            id: id,
            model: model,
            isAggregate: isAggregate,
            dayBuckets: buckets,
            activeDayCount: buckets.filter { $0.tokens > 0 }.count,
            sourceQuality: sourceQuality,
            costAvailable: sourceQuality == .detailed,
            usesReferencePricing: sourceQuality == .detailed
                && trends.contains { modelUsageUsesReferencePricing($0.model) }
        )
    }
}

enum ModelUsageTrendSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
            abs(lhs - rhs) < 0.000_001
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let dates = (0..<32).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateBuckets = dates.map { date in
            UsageDayBucket(
                id: dateFormatter.string(from: date),
                date: date,
                usage: .zero,
                sourceQuality: .detailed
            )
        }

        func aggregateUsage(_ buckets: [UsageDayBucket]) -> PricedTokenUsage {
            buckets.reduce(into: PricedTokenUsage.zero) { result, bucket in
                result.add(tokens: bucket.usage.tokens, costUSD: bucket.usage.estimatedCostUSD)
            }
        }

        func summary(for buckets: [UsageDayBucket]) -> UsageTrendSummary {
            let recent = aggregateUsage(Array(buckets.suffix(7)))
            let previous = aggregateUsage(Array(buckets.dropLast(7).suffix(7)))
            let recentTokens = recent.tokens.visibleTotalTokens
            let previousTokens = previous.tokens.visibleTotalTokens
            return UsageTrendSummary(
                sevenDay: recent,
                dailyAverageTokens: recentTokens / 7,
                peakDay: buckets.max { $0.tokens < $1.tokens },
                changePercent: previousTokens > 0
                    ? (Double(recentTokens - previousTokens) / Double(previousTokens)) * 100
                    : nil,
                isNewActivity: previousTokens == 0 && recentTokens > 0
            )
        }

        func trend(model: String?, index: Int) -> ModelUsageTrend {
            let buckets = dateBuckets.enumerated().map { dayIndex, bucket in
                let totalTokens = Int64(10 - index) * Int64(dayIndex + 1)
                return UsageDayBucket(
                    id: bucket.id,
                    date: bucket.date,
                    usage: PricedTokenUsage(
                        tokens: TokenBreakdown(
                            inputTokens: 0,
                            cachedInputTokens: 0,
                            outputTokens: 0,
                            reasoningOutputTokens: 0,
                            totalTokens: totalTokens
                        ),
                        estimatedCostUSD: Double(index + 1) * Double(dayIndex + 1) / 10
                    ),
                    sourceQuality: .detailed
                )
            }
            return ModelUsageTrend(
                id: modelUsageIdentifier(for: model),
                model: model,
                dayBuckets: buckets,
                summary: summary(for: buckets),
                activeDayCount: buckets.count
            )
        }

        let tenModels = (0..<10).map { index in
            trend(model: "model-" + String(index), index: index)
        }
        let overallBuckets = dateBuckets.enumerated().map { dayIndex, bucket in
            var usage = PricedTokenUsage.zero
            for model in tenModels {
                usage.add(
                    tokens: model.dayBuckets[dayIndex].usage.tokens,
                    costUSD: model.dayBuckets[dayIndex].usage.estimatedCostUSD
                )
            }
            return UsageDayBucket(
                id: bucket.id,
                date: bucket.date,
                usage: usage,
                sourceQuality: .detailed
            )
        }
        let overallTrend = UsageTrend(
            dayBuckets: overallBuckets,
            heatmapWeeks: [],
            heatmapThresholds: [],
            summary: summary(for: overallBuckets),
            modelTrends: tenModels,
            month: aggregateUsage(overallBuckets),
            projectedMonthCostUSD: nil,
            activeDayCount: overallBuckets.count,
            sourceQuality: .detailed
        )
        let visibleWindowBuckets = ModelUsageAreaSeriesBuilder.dateBuckets(
            from: overallTrend,
            window: .thirtyDays,
            referenceDate: dates[30]
        )
        expect(visibleWindowBuckets.count == 30, "thirty-day window should cap the visible date axis")
        expect(visibleWindowBuckets.first?.id == dateBuckets[1].id, "thirty-day window should exclude the oldest bucket")
        expect(visibleWindowBuckets.last?.id == dateBuckets[30].id, "window should exclude future buckets")

        let expectedRecentTokens = Double(aggregateUsage(Array(overallBuckets.suffix(7))).tokens.visibleTotalTokens)
        let expectedPreviousTokens = Double(aggregateUsage(Array(overallBuckets.dropLast(7).suffix(7))).tokens.visibleTotalTokens)
        let tokenSummary = ModelUsageMetricSummary.make(from: overallTrend, metric: .tokens)
        expect(nearlyEqual(tokenSummary.recentValue, expectedRecentTokens), "token summary should include the latest seven-day total")
        expect(nearlyEqual(tokenSummary.dailyAverageValue, expectedRecentTokens / 7), "token summary should calculate a seven-day average")
        expect(nearlyEqual(tokenSummary.changePercent ?? .nan, (expectedRecentTokens - expectedPreviousTokens) / expectedPreviousTokens * 100), "token summary should compare the previous seven days")

        let expectedRecentCost = aggregateUsage(Array(overallBuckets.suffix(7))).estimatedCostUSD
        let expectedPreviousCost = aggregateUsage(Array(overallBuckets.dropLast(7).suffix(7))).estimatedCostUSD
        let costSummary = ModelUsageMetricSummary.make(from: overallTrend, metric: .estimatedCostUSD)
        expect(nearlyEqual(costSummary.recentValue, expectedRecentCost), "cost summary should use the same latest seven-day dates")
        expect(nearlyEqual(costSummary.dailyAverageValue, expectedRecentCost / 7), "cost summary should calculate a seven-day average")
        expect(nearlyEqual(costSummary.changePercent ?? .nan, (expectedRecentCost - expectedPreviousCost) / expectedPreviousCost * 100), "cost summary should compare the previous seven days")

        let capped = ModelUsageAreaSeriesBuilder.build(
            modelTrends: tenModels,
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        expect(capped.count == 9, "ten models should produce eight visible series and one aggregate")
        expect(capped.first?.model == "model-0", "series should be ordered by six-month token total")
        expect(capped.last?.id == ModelUsageAreaSeriesBuilder.otherModelID, "remainder should be named other-models")
        expect(capped.last?.dayBuckets.first?.tokens == 3, "other-models should sum the daily token buckets")
        expect(capped.allSatisfy { $0.dayBuckets.count == dateBuckets.count }, "all series should share one date axis")
        expect(capped.allSatisfy(\.costAvailable), "detailed series should expose estimated cost")
        expect(capped.allSatisfy(\.usesReferencePricing), "unknown model prices should be marked as reference pricing")
        for dayIndex in dateBuckets.indices {
            let seriesTokens = capped.reduce(Int64(0)) { result, series in
                result + series.dayBuckets[dayIndex].tokens
            }
            let seriesCost = capped.reduce(0.0) { result, series in
                result + series.dayBuckets[dayIndex].usage.estimatedCostUSD
            }
            expect(seriesTokens == overallBuckets[dayIndex].tokens, "model series should sum to the overall token bucket on each day")
            expect(nearlyEqual(seriesCost, overallBuckets[dayIndex].usage.estimatedCostUSD), "model series should sum to the overall cost bucket on each day")
        }
        let tokenModeSeries = ModelUsageAreaSeriesBuilder.build(
            modelTrends: tenModels,
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        let costModeSeries = ModelUsageAreaSeriesBuilder.build(
            modelTrends: tenModels,
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        expect(
            tokenModeSeries.map { $0.dayBuckets.map(\.id) } == costModeSeries.map { $0.dayBuckets.map(\.id) },
            "token and cost modes should share one date axis"
        )

        let topEightTooltipRowCount = 1 + capped.count + 2 // total + models + runtime/source
        let compactTooltip = ChartTooltipLayout.isCompact(rowCount: topEightTooltipRowCount)
        let compactTooltipHeight = ChartTooltipLayout.estimatedHeight(
            rowCount: topEightTooltipRowCount,
            compact: compactTooltip
        )
        let compactTooltipPosition = ChartTooltipLayout.position(
            anchor: CGPoint(x: 52, y: 26),
            containerSize: CGSize(width: 760, height: 192),
            rowCount: topEightTooltipRowCount,
            compact: compactTooltip
        )
        expect(compactTooltip, "top eight plus other tooltip should use compact layout")
        expect(
            compactTooltipPosition.y - compactTooltipHeight / 2 >= 8
                && compactTooltipPosition.y + compactTooltipHeight / 2 <= 184,
            "top eight plus other tooltip should remain inside the plot viewport"
        )

        let small = ModelUsageAreaSeriesBuilder.build(
            modelTrends: Array(tenModels.prefix(8)),
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        expect(small.count == 8, "eight or fewer models should not create an aggregate")

        let zeroModel = ModelUsageTrend(
            id: "unrecorded-model",
            model: nil,
            dayBuckets: dateBuckets,
            summary: summary(for: dateBuckets),
            activeDayCount: 0
        )
        let withoutZeroSeries = ModelUsageAreaSeriesBuilder.build(
            modelTrends: tenModels + [zeroModel],
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        expect(!withoutZeroSeries.contains(where: { $0.id == zeroModel.id }), "zero-only unrecorded models should not render a series")

        let approximate = ModelUsageAreaSeriesBuilder.build(
            modelTrends: Array(tenModels.prefix(1)),
            dateBuckets: dateBuckets,
            sourceQuality: .approximate
        )
        expect(approximate.first?.costAvailable == false, "approximate series should disable cost mode")
        expect(approximate.first?.usesReferencePricing == false, "disabled cost mode should not advertise reference pricing")

        let catalogPriced = ModelUsageAreaSeriesBuilder.build(
            modelTrends: [trend(model: "gpt-5.5", index: 0)],
            dateBuckets: dateBuckets,
            sourceQuality: .detailed
        )
        expect(catalogPriced.first?.usesReferencePricing == false, "catalog-priced models should not be marked as reference pricing")
        expect(modelUsageUsesReferencePricing("gpt-5.6-luna"), "unknown models should use the documented reference price")
        expect(!modelUsageUsesReferencePricing("gpt-5.5"), "catalog-priced models should retain their explicit price basis")

        let unsupportedTrend = UsageTrend(
            dayBuckets: overallBuckets,
            heatmapWeeks: [],
            heatmapThresholds: [],
            summary: summary(for: overallBuckets),
            modelTrends: nil,
            month: aggregateUsage(overallBuckets),
            projectedMonthCostUSD: nil,
            activeDayCount: overallBuckets.count,
            sourceQuality: .detailed
        )
        expect(unsupportedTrend.modelTrends == nil, "unsupported providers should not use an empty model list")
        expect(ModelUsageAreaSeriesBuilder.build(from: unsupportedTrend).isEmpty, "unsupported providers should not emit model series")

        expect(resolvedModelUsageName(turnContextModel: "gpt-turn", threadModel: "gpt-thread") == "gpt-turn", "turn context model should win")
        expect(resolvedModelUsageName(turnContextModel: "", threadModel: "gpt-thread") == "gpt-thread", "empty turn context should fall back to thread model")
        expect(resolvedModelUsageName(turnContextModel: nil, threadModel: nil) == nil, "missing models should remain unrecorded")
        var activeModel: String?
        applyTurnContextModel("model-a", to: &activeModel)
        expect(resolvedModelUsageName(turnContextModel: activeModel, threadModel: "thread-model") == "model-a", "a recorded turn context should override the thread model")
        applyTurnContextModel("model-b", to: &activeModel)
        expect(resolvedModelUsageName(turnContextModel: activeModel, threadModel: "thread-model") == "model-b", "a newer turn context should replace the previous model")
        applyTurnContextModel(nil, to: &activeModel)
        expect(resolvedModelUsageName(turnContextModel: activeModel, threadModel: "thread-model") == "thread-model", "a turn context without a model should clear the prior model before the next token event")

        if failures.isEmpty {
            print("model usage trend self-test passed")
            return true
        }
        failures.forEach { print("model usage trend self-test failed: \($0)") }
        return false
    }
}

import Foundation

let modelInferenceMinimumCallDurationSeconds: Double = 0.1

struct ModelInferenceSample: Equatable, Codable {
    let completedAt: Date
    let durationSeconds: Double
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let model: String
    let effort: String
    let eventIdentity: CodexTokenEventIdentity
}

enum ModelInferencePeriod: String, Codable, CaseIterable, Identifiable, Equatable {
    case today
    case sevenDays
    case twentyEightDays

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .today: 1
        case .sevenDays: 7
        case .twentyEightDays: 28
        }
    }
}

struct ModelInferencePerformanceGroup: Identifiable, Equatable, Codable {
    let id: String
    let model: String
    let effort: String
    let callCount: Int
    let averageDailyCallCount: Double
    let averageDurationSeconds: Double
    let p50DurationSeconds: Double
    let p90DurationSeconds: Double
    let effectiveOutputTokensPerSecond: Double
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
}

struct ModelInferencePerformance: Equatable, Codable {
    let period: ModelInferencePeriod
    let coverageDayCount: Int
    let groups: [ModelInferencePerformanceGroup]
    let totalCallCount: Int

    func displayGroups() -> [ModelInferencePerformanceGroup] {
        groups.sorted { lhs, rhs in
            if lhs.callCount != rhs.callCount { return lhs.callCount > rhs.callCount }
            if lhs.p50DurationSeconds != rhs.p50DurationSeconds {
                return lhs.p50DurationSeconds < rhs.p50DurationSeconds
            }
            return lhs.id < rhs.id
        }
    }
}

struct ModelInferencePerformanceHistory: Equatable, Codable {
    let recordingStartedAt: Date
    let today: ModelInferencePerformance?
    let sevenDays: ModelInferencePerformance?
    let twentyEightDays: ModelInferencePerformance?

    func performance(for period: ModelInferencePeriod) -> ModelInferencePerformance? {
        switch period {
        case .today: today
        case .sevenDays: sevenDays
        case .twentyEightDays: twentyEightDays
        }
    }
}

struct ModelInferenceHistoryArchive: Equatable, Codable {
    var recordingStartedAt: Date
    var samplesBySourceID: [String: [ModelInferenceSample]]

    init(recordingStartedAt: Date, samplesBySourceID: [String: [ModelInferenceSample]] = [:]) {
        self.recordingStartedAt = recordingStartedAt
        self.samplesBySourceID = samplesBySourceID
    }

    var samples: [ModelInferenceSample] {
        samplesBySourceID.values.flatMap { $0 }
    }

    mutating func replaceSamples(
        for sourceID: String,
        with samples: [ModelInferenceSample],
        retainingSince retentionStart: Date
    ) {
        guard !sourceID.isEmpty else { return }
        let retained = samples
            .filter {
                $0.completedAt >= retentionStart
                    && $0.durationSeconds >= modelInferenceMinimumCallDurationSeconds
            }
            .sorted { $0.completedAt < $1.completedAt }
        if retained.isEmpty {
            samplesBySourceID.removeValue(forKey: sourceID)
        } else {
            samplesBySourceID[sourceID] = retained
            if let earliest = retained.first?.completedAt, earliest < recordingStartedAt {
                recordingStartedAt = earliest
            }
        }
    }

    mutating func compact(retainingSince retentionStart: Date, maximumSampleCount: Int) {
        let retained = samplesBySourceID.flatMap { sourceID, samples in
            samples
                .filter {
                    $0.completedAt >= retentionStart
                        && $0.durationSeconds >= modelInferenceMinimumCallDurationSeconds
                }
                .map { (sourceID: sourceID, sample: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.sample.completedAt != rhs.sample.completedAt {
                return lhs.sample.completedAt > rhs.sample.completedAt
            }
            return lhs.sourceID < rhs.sourceID
        }
        .prefix(max(maximumSampleCount, 0))

        var grouped: [String: [ModelInferenceSample]] = [:]
        for item in retained {
            grouped[item.sourceID, default: []].append(item.sample)
        }
        samplesBySourceID = grouped.mapValues { samples in
            samples.sorted { $0.completedAt < $1.completedAt }
        }
    }
}

struct ModelInferenceCallTracker: Codable {
    private var activeModel: String?
    private var activeEffort: String?
    private var callStartedAt: Date?
    private var observedModelOutput = false

    mutating func applyTurnContext(model: String?, effort: String?, at date: Date) {
        activeModel = normalizedValue(model)
        activeEffort = normalizedValue(effort)?.lowercased()
        callStartedAt = date
        observedModelOutput = false
    }

    mutating func applyInputBoundary(at date: Date) {
        if callStartedAt == nil || date > (callStartedAt ?? .distantPast) {
            callStartedAt = date
        }
        observedModelOutput = false
    }

    mutating func observeModelOutput() {
        observedModelOutput = true
    }

    mutating func consumeTokenEvent(
        at completedAt: Date,
        lastUsage: CodexTokenCounterSample?,
        eventIdentity: CodexTokenEventIdentity
    ) -> ModelInferenceSample? {
        defer {
            callStartedAt = completedAt
            observedModelOutput = false
        }

        guard let model = activeModel,
              let effort = activeEffort,
              let startedAt = callStartedAt,
              observedModelOutput,
              completedAt.timeIntervalSince(startedAt) >= modelInferenceMinimumCallDurationSeconds,
              let lastUsage,
              !lastUsage.hasNegativeValue
        else { return nil }

        let usage = lastUsage.snapshot()
        guard usage.outputTokens > 0 else { return nil }

        return ModelInferenceSample(
            completedAt: completedAt,
            durationSeconds: completedAt.timeIntervalSince(startedAt),
            outputTokens: usage.outputTokens,
            reasoningOutputTokens: min(max(usage.reasoningOutputTokens, 0), usage.outputTokens),
            model: model,
            effort: effort,
            eventIdentity: eventIdentity
        )
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum ModelInferencePerformanceBuilder {
    static func makeHistory(
        samples: [ModelInferenceSample],
        recordingStartedAt: Date,
        dayStart: Date,
        calendar: Calendar
    ) -> ModelInferencePerformanceHistory? {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)

        func performance(for period: ModelInferencePeriod) -> ModelInferencePerformance? {
            let windowStart = calendar.date(
                byAdding: .day,
                value: 1 - period.dayCount,
                to: dayStart
            ) ?? dayStart
            let recordingDayStart = calendar.startOfDay(for: recordingStartedAt)
            let coverageStart = max(windowStart, recordingDayStart)
            let elapsedDays = calendar.dateComponents(
                [.day],
                from: coverageStart,
                to: dayStart
            ).day ?? 0
            let coverageDayCount = min(max(elapsedDays + 1, 1), period.dayCount)
            return make(
                samples: samples,
                period: period,
                windowStart: windowStart,
                windowEnd: dayEnd,
                coverageDayCount: coverageDayCount
            )
        }

        let history = ModelInferencePerformanceHistory(
            recordingStartedAt: recordingStartedAt,
            today: performance(for: .today),
            sevenDays: performance(for: .sevenDays),
            twentyEightDays: performance(for: .twentyEightDays)
        )
        guard history.today != nil || history.sevenDays != nil || history.twentyEightDays != nil else {
            return nil
        }
        return history
    }

    static func make(
        samples: [ModelInferenceSample],
        dayStart: Date,
        dayEnd: Date
    ) -> ModelInferencePerformance? {
        make(
            samples: samples,
            period: .today,
            windowStart: dayStart,
            windowEnd: dayEnd,
            coverageDayCount: 1
        )
    }

    static func make(
        samples: [ModelInferenceSample],
        period: ModelInferencePeriod,
        windowStart: Date,
        windowEnd: Date,
        coverageDayCount: Int
    ) -> ModelInferencePerformance? {
        let selectedSamples = samples.filter {
            $0.completedAt >= windowStart
                && $0.completedAt < windowEnd
                && $0.durationSeconds >= modelInferenceMinimumCallDurationSeconds
                && $0.outputTokens > 0
        }
        guard !selectedSamples.isEmpty else { return nil }

        let grouped = Dictionary(grouping: selectedSamples) { sample in
            modelInferencePerformanceID(model: sample.model, effort: sample.effort)
        }

        let groups = grouped.compactMap { id, values -> ModelInferencePerformanceGroup? in
            guard let first = values.first else { return nil }
            let durations = values.map(\.durationSeconds).sorted()
            let totalDuration = durations.reduce(0, +)
            let outputTokens = values.reduce(Int64(0)) { $0 + $1.outputTokens }
            let reasoningTokens = values.reduce(Int64(0)) { $0 + $1.reasoningOutputTokens }
            guard totalDuration > 0, outputTokens > 0 else { return nil }

            return ModelInferencePerformanceGroup(
                id: id,
                model: first.model,
                effort: first.effort,
                callCount: values.count,
                averageDailyCallCount: Double(values.count) / Double(max(coverageDayCount, 1)),
                averageDurationSeconds: totalDuration / Double(values.count),
                p50DurationSeconds: percentile(durations, fraction: 0.5),
                p90DurationSeconds: percentile(durations, fraction: 0.9),
                effectiveOutputTokensPerSecond: Double(outputTokens) / totalDuration,
                outputTokens: outputTokens,
                reasoningOutputTokens: reasoningTokens
            )
        }
        .sorted { lhs, rhs in
            if lhs.callCount != rhs.callCount { return lhs.callCount > rhs.callCount }
            return lhs.id < rhs.id
        }

        guard !groups.isEmpty else { return nil }
        return ModelInferencePerformance(
            period: period,
            coverageDayCount: max(coverageDayCount, 1),
            groups: groups,
            totalCallCount: groups.reduce(0) { $0 + $1.callCount }
        )
    }

    static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard let first = sortedValues.first else { return 0 }
        guard sortedValues.count > 1 else { return first }
        let clamped = min(max(fraction, 0), 1)
        let position = Double(sortedValues.count - 1) * clamped
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return sortedValues[lowerIndex] }
        let progress = position - Double(lowerIndex)
        return sortedValues[lowerIndex]
            + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * progress
    }
}

func modelInferencePerformanceID(model: String, effort: String) -> String {
    "\(model.lowercased())::\(effort.lowercased())"
}

enum ModelInferencePerformanceSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000_1) -> Bool {
            abs(lhs - rhs) <= tolerance
        }

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = CodexTokenCounterSample(
            inputTokens: 100,
            cachedInputTokens: 50,
            outputTokens: 40,
            reasoningOutputTokens: 10,
            totalTokens: 140
        )
        let identity = CodexTokenEventIdentity(cumulative: nil, lastUsage: usage)

        var tracker = ModelInferenceCallTracker()
        tracker.applyTurnContext(model: "gpt-test", effort: "High", at: base)
        tracker.applyInputBoundary(at: base.addingTimeInterval(1))
        tracker.observeModelOutput()
        let first = tracker.consumeTokenEvent(
            at: base.addingTimeInterval(5),
            lastUsage: usage,
            eventIdentity: identity
        )
        expect(nearlyEqual(first?.durationSeconds ?? 0, 4), "turn input should define the first call boundary")
        expect(first?.effort == "high", "effort should be normalized")

        tracker.applyInputBoundary(at: base.addingTimeInterval(20))
        tracker.observeModelOutput()
        let afterTool = tracker.consumeTokenEvent(
            at: base.addingTimeInterval(22),
            lastUsage: usage,
            eventIdentity: identity
        )
        expect(nearlyEqual(afterTool?.durationSeconds ?? 0, 2), "tool output should exclude tool execution time")

        tracker.applyTurnContext(model: "gpt-test", effort: nil, at: base.addingTimeInterval(30))
        tracker.observeModelOutput()
        let missingEffort = tracker.consumeTokenEvent(
            at: base.addingTimeInterval(31),
            lastUsage: usage,
            eventIdentity: identity
        )
        expect(missingEffort == nil, "missing effort must clear previous attribution")

        tracker.applyTurnContext(model: "gpt-test", effort: "high", at: base.addingTimeInterval(35))
        tracker.observeModelOutput()
        let timestampNoise = tracker.consumeTokenEvent(
            at: base.addingTimeInterval(35.01),
            lastUsage: usage,
            eventIdentity: identity
        )
        expect(timestampNoise == nil, "sub-100ms timestamp noise must not become a complete model call")

        tracker.applyTurnContext(model: "gpt-test", effort: "high", at: base.addingTimeInterval(40))
        let baselineSnapshot = tracker.consumeTokenEvent(
            at: base.addingTimeInterval(40.001),
            lastUsage: usage,
            eventIdentity: identity
        )
        expect(baselineSnapshot == nil, "token snapshots without new model output must not become calls")

        let durations = [2.0, 4.0, 8.0]
        let samples = durations.enumerated().map { index, duration in
            ModelInferenceSample(
                completedAt: base.addingTimeInterval(Double(index + 1) * 60),
                durationSeconds: duration,
                outputTokens: Int64([20, 40, 80][index]),
                reasoningOutputTokens: Int64([5, 10, 20][index]),
                model: "gpt-test",
                effort: "high",
                eventIdentity: identity
            )
        }
        let performance = ModelInferencePerformanceBuilder.make(
            samples: samples,
            dayStart: base,
            dayEnd: base.addingTimeInterval(24 * 60 * 60)
        )
        let group = performance?.groups.first
        expect(group?.callCount == 3, "samples should aggregate by model and effort")
        expect(nearlyEqual(group?.averageDailyCallCount ?? 0, 3), "today should use the observed daily call count")
        expect(nearlyEqual(group?.averageDurationSeconds ?? 0, 14.0 / 3.0), "average duration")
        expect(nearlyEqual(group?.p50DurationSeconds ?? 0, 4), "p50 duration")
        expect(nearlyEqual(group?.p90DurationSeconds ?? 0, 7.2), "interpolated p90 duration")
        expect(nearlyEqual(group?.effectiveOutputTokensPerSecond ?? 0, 10), "effective throughput must use total output over total duration")

        let outside = ModelInferenceSample(
            completedAt: base.addingTimeInterval(-1),
            durationSeconds: 1,
            outputTokens: 10,
            reasoningOutputTokens: 0,
            model: "gpt-other",
            effort: "low",
            eventIdentity: identity
        )
        let filtered = ModelInferencePerformanceBuilder.make(
            samples: samples + [outside],
            dayStart: base,
            dayEnd: base.addingTimeInterval(24 * 60 * 60)
        )
        expect(filtered?.groups.count == 1, "samples outside the selected day must be excluded")

        var expandedSamples: [ModelInferenceSample] = []
        for index in 0..<7 {
            let sample = ModelInferenceSample(
                completedAt: base.addingTimeInterval(Double(index + 1) * 60),
                durationSeconds: Double(index + 1),
                outputTokens: Int64((index + 1) * 10),
                reasoningOutputTokens: 0,
                model: "gpt-test-\(index)",
                effort: "high",
                eventIdentity: identity
            )
            expandedSamples.append(sample)
        }
        let expandedPerformance = ModelInferencePerformanceBuilder.make(
            samples: expandedSamples,
            dayStart: base,
            dayEnd: base.addingTimeInterval(24 * 60 * 60)
        )
        expect(
            expandedPerformance?.displayGroups().count == expandedSamples.count,
            "display groups must not truncate valid model and effort combinations"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let priorDay = ModelInferenceSample(
            completedAt: base.addingTimeInterval(-24 * 60 * 60),
            durationSeconds: 5,
            outputTokens: 50,
            reasoningOutputTokens: 10,
            model: "gpt-test",
            effort: "high",
            eventIdentity: identity
        )
        let history = ModelInferencePerformanceBuilder.makeHistory(
            samples: samples + [priorDay],
            recordingStartedAt: priorDay.completedAt,
            dayStart: base,
            calendar: calendar
        )
        expect(history?.today?.totalCallCount == 3, "today history should exclude prior-day calls")
        expect(history?.sevenDays?.totalCallCount == 4, "seven-day history should retain prior-day calls")
        expect(nearlyEqual(history?.sevenDays?.groups.first?.averageDailyCallCount ?? 0, 2), "rolling call bubbles should use daily averages over recorded coverage")

        var archive = ModelInferenceHistoryArchive(recordingStartedAt: base)
        archive.replaceSamples(
            for: "thread-a",
            with: samples + [outside],
            retainingSince: base
        )
        expect(archive.samples.count == samples.count, "history archive should discard samples before retention")
        archive.compact(retainingSince: base, maximumSampleCount: 2)
        expect(archive.samples.count == 2, "history archive must remain bounded")

        if failures.isEmpty {
            print("model inference performance self-test passed")
            return true
        }
        failures.forEach { print("model inference performance self-test failed: \($0)") }
        return false
    }
}

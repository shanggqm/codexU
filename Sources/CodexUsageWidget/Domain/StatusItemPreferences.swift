import Foundation

enum StatusItemDisplayMode: String, CaseIterable, Codable, Identifiable, Equatable {
    case minimal
    case classic
    case rich

    var id: String { rawValue }
}

enum QuotaDisplayMode: String, CaseIterable, Codable, Identifiable, Equatable {
    case used
    case remaining

    var id: String { rawValue }

    var drawsClockwise: Bool { self == .used }
    var startsAtLeadingEdge: Bool { self == .used }
}

enum StatusItemMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case fiveHourQuota
    case sevenDayQuota
    case monthlyQuota
    case todayTokens

    static let allCases: [StatusItemMetric] = [
        .fiveHourQuota,
        .sevenDayQuota,
        .todayTokens
    ]

    var id: String { rawValue }

    var isQuota: Bool {
        self == .fiveHourQuota || self == .sevenDayQuota || self == .monthlyQuota
    }
}

enum StatusItemPreferenceError: Error, Equatable {
    case requiresVisibleMetric
    case minimalRequiresQuotaMetric
}

struct StatusItemPreferences: Equatable {
    var displayMode: StatusItemDisplayMode
    var quotaMode: QuotaDisplayMode
    var visibleMetrics: Set<StatusItemMetric>
    var showsResetCountdown: Bool

    static let `default` = StatusItemPreferences(
        displayMode: .rich,
        quotaMode: .used,
        visibleMetrics: [.fiveHourQuota, .sevenDayQuota],
        showsResetCountdown: true
    )

    var orderedVisibleMetrics: [StatusItemMetric] {
        StatusItemMetric.allCases.filter { visibleMetrics.contains($0) }
    }

    var hasVisibleQuota: Bool {
        visibleMetrics.contains(where: \.isQuota)
    }

    func validationError() -> StatusItemPreferenceError? {
        if visibleMetrics.isEmpty {
            return .requiresVisibleMetric
        }
        if displayMode == .minimal, !hasVisibleQuota {
            return .minimalRequiresQuotaMetric
        }
        return nil
    }

    func normalized() -> StatusItemPreferences {
        var result = self
        if result.visibleMetrics.isEmpty {
            result.visibleMetrics = Self.default.visibleMetrics
        }
        if result.displayMode == .minimal, !result.hasVisibleQuota {
            result.visibleMetrics.formUnion(Self.default.visibleMetrics)
        }
        return result
    }
}

enum StatusItemPreferencesStore {
    static let displayModeKey = "codexU.statusItem.displayMode"
    static let quotaModeKey = "codexU.statusItem.quotaMode"
    static let visibleMetricsKey = "codexU.statusItem.visibleMetrics"
    static let showsResetCountdownKey = "codexU.statusItem.showsResetCountdown"

    static func load(defaults: UserDefaults = .standard) -> StatusItemPreferences {
        let fallback = StatusItemPreferences.default
        let displayMode = defaults.string(forKey: displayModeKey)
            .flatMap(StatusItemDisplayMode.init(rawValue:)) ?? fallback.displayMode
        let quotaMode = defaults.string(forKey: quotaModeKey)
            .flatMap(QuotaDisplayMode.init(rawValue:)) ?? fallback.quotaMode

        let visibleMetrics: Set<StatusItemMetric>
        if let rawMetrics = defaults.array(forKey: visibleMetricsKey) as? [String] {
            visibleMetrics = Set(rawMetrics.compactMap(StatusItemMetric.init(rawValue:)))
        } else {
            visibleMetrics = fallback.visibleMetrics
        }

        let showsResetCountdown: Bool
        if defaults.object(forKey: showsResetCountdownKey) == nil {
            showsResetCountdown = fallback.showsResetCountdown
        } else {
            showsResetCountdown = defaults.bool(forKey: showsResetCountdownKey)
        }

        return StatusItemPreferences(
            displayMode: displayMode,
            quotaMode: quotaMode,
            visibleMetrics: visibleMetrics,
            showsResetCountdown: showsResetCountdown
        ).normalized()
    }

    static func save(_ preferences: StatusItemPreferences, defaults: UserDefaults = .standard) {
        let normalized = preferences.normalized()
        defaults.set(normalized.displayMode.rawValue, forKey: displayModeKey)
        defaults.set(normalized.quotaMode.rawValue, forKey: quotaModeKey)
        defaults.set(normalized.orderedVisibleMetrics.map(\.rawValue), forKey: visibleMetricsKey)
        defaults.set(normalized.showsResetCountdown, forKey: showsResetCountdownKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: displayModeKey)
        defaults.removeObject(forKey: quotaModeKey)
        defaults.removeObject(forKey: visibleMetricsKey)
        defaults.removeObject(forKey: showsResetCountdownKey)
    }
}

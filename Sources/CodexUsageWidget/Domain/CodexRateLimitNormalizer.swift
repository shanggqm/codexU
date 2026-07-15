import Foundation

struct CodexNormalizedRateWindows: Equatable {
    let fiveHour: RateWindow?
    let sevenDay: RateWindow?
    let unclassified: [RateWindow]
    let fiveHourMatchCount: Int
    let sevenDayMatchCount: Int
}

enum CodexRateLimitNormalizer {
    static let fiveHourDurationMins = 300
    static let sevenDayDurationMins = 10_080

    static func normalize(_ windows: [RateWindow?]) -> CodexNormalizedRateWindows {
        let available = windows.compactMap { $0 }
        let fiveHourMatches = available.filter {
            $0.windowDurationMins == fiveHourDurationMins
        }
        let sevenDayMatches = available.filter {
            $0.windowDurationMins == sevenDayDurationMins
        }
        let unclassified = available.filter { window in
            guard let duration = window.windowDurationMins else { return true }
            return duration != fiveHourDurationMins && duration != sevenDayDurationMins
        }

        return CodexNormalizedRateWindows(
            fiveHour: fiveHourMatches.count == 1 ? fiveHourMatches[0] : nil,
            sevenDay: sevenDayMatches.count == 1 ? sevenDayMatches[0] : nil,
            unclassified: unclassified,
            fiveHourMatchCount: fiveHourMatches.count,
            sevenDayMatchCount: sevenDayMatches.count
        )
    }

    static func isAuthoritative(
        hasWindowFields: Bool,
        hasMalformedWindow: Bool,
        normalized: CodexNormalizedRateWindows
    ) -> Bool {
        hasWindowFields
            && !hasMalformedWindow
            && normalized.fiveHourMatchCount <= 1
            && normalized.sevenDayMatchCount <= 1
            && normalized.unclassified.isEmpty
    }
}

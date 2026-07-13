import Foundation

enum StatisticsTimeZoneSelection: String, CaseIterable, Codable, Equatable, Identifiable {
    case system
    case utc
    case fixed

    var id: String { rawValue }
}

struct StatisticsTimeZonePreference: Equatable, Codable {
    var selection: StatisticsTimeZoneSelection
    var fixedIdentifier: String

    static let `default` = StatisticsTimeZonePreference(
        selection: .system,
        fixedIdentifier: TimeZone.current.identifier
    )

    func resolvedTimeZone(system: TimeZone = .current) -> TimeZone {
        switch selection {
        case .system:
            return system
        case .utc:
            return TimeZone(secondsFromGMT: 0)!
        case .fixed:
            return TimeZone(identifier: fixedIdentifier) ?? system
        }
    }

    func repaired(system: TimeZone = .current) -> StatisticsTimeZonePreference {
        guard selection == .fixed, TimeZone(identifier: fixedIdentifier) == nil else { return self }
        return StatisticsTimeZonePreference(selection: .system, fixedIdentifier: system.identifier)
    }
}

enum StatisticsTimeZonePreferenceStore {
    private static let selectionKey = "codexU.statisticsTimeZone.selection"
    private static let fixedIdentifierKey = "codexU.statisticsTimeZone.fixedIdentifier"

    static func load(defaults: UserDefaults = .standard, system: TimeZone = .current) -> StatisticsTimeZonePreference {
        let selection = defaults.string(forKey: selectionKey)
            .flatMap(StatisticsTimeZoneSelection.init(rawValue:)) ?? .system
        let identifier = defaults.string(forKey: fixedIdentifierKey) ?? system.identifier
        let stored = StatisticsTimeZonePreference(selection: selection, fixedIdentifier: identifier)
        let repaired = stored.repaired(system: system)
        if repaired != stored {
            save(repaired, defaults: defaults)
        }
        return repaired
    }

    static func save(_ preference: StatisticsTimeZonePreference, defaults: UserDefaults = .standard) {
        let repaired = preference.repaired()
        defaults.set(repaired.selection.rawValue, forKey: selectionKey)
        defaults.set(repaired.fixedIdentifier, forKey: fixedIdentifierKey)
    }
}

struct StatisticsContext: Equatable {
    let preference: StatisticsTimeZonePreference
    let timeZone: TimeZone
    let now: Date

    init(
        preference: StatisticsTimeZonePreference,
        now: Date,
        systemTimeZone: TimeZone = .current
    ) {
        let repaired = preference.repaired(system: systemTimeZone)
        self.preference = repaired
        timeZone = repaired.resolvedTimeZone(system: systemTimeZone)
        self.now = now
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    var resolvedIdentifier: String { timeZone.identifier }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

struct StatisticsIdentity: Equatable {
    let preference: StatisticsTimeZonePreference
    let resolvedIdentifier: String
    let generation: UInt64
    let now: Date

    static func empty(now: Date = Date()) -> StatisticsIdentity {
        let preference = StatisticsTimeZonePreference.default
        return StatisticsIdentity(
            preference: preference,
            resolvedIdentifier: preference.resolvedTimeZone().identifier,
            generation: 0,
            now: now
        )
    }
}

enum StatisticsTimeZoneSelfTest {
    static func run() -> Bool {
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                print("statistics time zone self-test failed: \(message)")
                failures += 1
                return
            }
        }

        let utc = StatisticsContext(
            preference: StatisticsTimeZonePreference(selection: .utc, fixedIdentifier: "UTC"),
            now: Date(timeIntervalSince1970: 0)
        )
        let shanghai = StatisticsContext(
            preference: StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: "Asia/Shanghai"),
            now: Date(timeIntervalSince1970: 0)
        )
        let event = ISO8601DateFormatter().date(from: "2026-09-04T17:30:00Z")!
        expect(utc.dayKey(for: event) == "2026-09-04", "UTC day key")
        expect(shanghai.dayKey(for: event) == "2026-09-05", "Shanghai cross-day key")

        let losAngeles = StatisticsContext(
            preference: StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: "America/Los_Angeles"),
            now: Date(timeIntervalSince1970: 0)
        )
        let spring = ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z")!
        let springNext = losAngeles.calendar.date(byAdding: .day, value: 1, to: losAngeles.startOfDay(for: spring))!
        expect(Int(springNext.timeIntervalSince(losAngeles.startOfDay(for: spring))) == 23 * 3600, "DST spring day")
        let fall = ISO8601DateFormatter().date(from: "2026-11-01T07:00:00Z")!
        let fallNext = losAngeles.calendar.date(byAdding: .day, value: 1, to: losAngeles.startOfDay(for: fall))!
        expect(Int(fallNext.timeIntervalSince(losAngeles.startOfDay(for: fall))) == 25 * 3600, "DST fall day")

        let suite = "codexU.statistics-time-zone.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        StatisticsTimeZonePreferenceStore.save(
            StatisticsTimeZonePreference(selection: .fixed, fixedIdentifier: "Asia/Shanghai"),
            defaults: defaults
        )
        expect(StatisticsTimeZonePreferenceStore.load(defaults: defaults).fixedIdentifier == "Asia/Shanghai", "preference persistence")
        defaults.set("fixed", forKey: "codexU.statisticsTimeZone.selection")
        defaults.set("Invalid/Zone", forKey: "codexU.statisticsTimeZone.fixedIdentifier")
        expect(StatisticsTimeZonePreferenceStore.load(defaults: defaults).selection == .system, "invalid zone repair")
        expect(
            preferredRuntimeTodayTokens(detailed: 490_100_000, fallback: 650_900_000) == 490_100_000,
            "runtime summaries must prefer detailed token_count usage"
        )
        expect(
            preferredRuntimeTodayTokens(detailed: nil, fallback: 650_900_000) == 650_900_000,
            "runtime summaries should use SQLite only as a fallback"
        )

        let sampleEvents = (0..<25_000).map { index in
            Date(timeIntervalSince1970: 1_767_225_600 + Double(index * 37))
        }
        let started = CFAbsoluteTimeGetCurrent()
        let grouped = Dictionary(grouping: sampleEvents, by: utc.dayKey(for:))
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        expect(grouped.values.reduce(0) { $0 + $1.count } == sampleEvents.count, "25K event conservation")
        expect(elapsed < 0.5, "25K grouping should remain comfortably interactive")

        if failures == 0 {
            print("statistics time zone self-test passed")
        }
        return failures == 0
    }
}

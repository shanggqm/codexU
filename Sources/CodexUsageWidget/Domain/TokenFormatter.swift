import Foundation

enum TokenFormatter {
    private struct Unit {
        let divisor: Double
        let suffix: String
    }

    private static let units = [
        Unit(divisor: 1_000, suffix: "K"),
        Unit(divisor: 1_000_000, suffix: "M"),
        Unit(divisor: 1_000_000_000, suffix: "B")
    ]

    static func format(_ value: Int64?) -> String {
        guard let value else { return "--" }

        let magnitude = abs(Double(value))
        guard magnitude >= units[0].divisor else { return "\(value)" }

        var unitIndex = units.lastIndex { magnitude >= $0.divisor } ?? 0
        var scaledValue = Double(value) / units[unitIndex].divisor
        var roundedValue = (scaledValue * 10).rounded() / 10

        // Rounding values such as 999,999 should promote them to 1.0M instead
        // of producing the awkward 1000.0K representation.
        if abs(roundedValue) >= 1_000, unitIndex < units.count - 1 {
            unitIndex += 1
            scaledValue = Double(value) / units[unitIndex].divisor
            roundedValue = (scaledValue * 10).rounded() / 10
        }

        return String(
            format: "%.1f%@",
            locale: Locale(identifier: "en_US_POSIX"),
            roundedValue,
            units[unitIndex].suffix
        )
    }
}

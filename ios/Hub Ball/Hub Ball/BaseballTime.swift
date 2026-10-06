import Foundation

nonisolated enum BaseballTime {
    static let timeZone = TimeZone(identifier: "America/New_York")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func format(_ date: Date, _ style: Date.FormatStyle) -> String {
        var easternStyle = style
        easternStyle.calendar = calendar
        easternStyle.timeZone = timeZone
        return date.formatted(easternStyle)
    }
}

/// Immutable ISO parser styles can be shared across decoding tasks and UI reads.
nonisolated enum FeedDate {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let internet = Date.ISO8601FormatStyle()
    static func date(from value: String) -> Date? {
        (try? fractional.parse(value)) ?? (try? internet.parse(value))
    }
}

/// Fixed-format display helpers. Formatters are configured once, never mutated
/// after publication; Foundation synchronizes DateFormatter operations.
nonisolated enum BaseballDateFormat {
    static let day = formatter("yyyy-MM-dd")
    static let news = formatter("MM/dd h:mm a")
    static let hour = formatter("ha")
    static let hourMinute = formatter("h:mma")
    static let weekday = formatter("EEE, MMM d")
    static let shortDate = formatter("MM/dd/yy")
    static let longDate = formatter("MMMM d, yyyy")
    static let abbreviatedDate = formatter("MMM d, yyyy")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = BaseballTime.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = BaseballTime.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

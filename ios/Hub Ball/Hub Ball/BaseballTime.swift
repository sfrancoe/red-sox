import Foundation

enum BaseballTime {
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

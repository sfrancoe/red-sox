import Foundation

enum NewsSource: String, CaseIterable, Identifiable, Sendable {
    case nyTimes = "nytimes"
    case nyPost = "nypost"
    case dailyNews = "dailynews"
    case athletic

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .nyTimes: "NY Times"
        case .nyPost: "NY Post"
        case .dailyNews: "Daily News"
        case .athletic: "Athletic"
        }
    }

    var fileName: String { rawValue }
}

struct NewsFeed: Codable, Sendable {
    let generatedAt: String
    let source: String
    let sourceUrl: String
    let articles: [NewsArticle]

    var refreshedText: String {
        guard let date = NewsDateParser.date(from: generatedAt) else {
            return generatedAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct NewsArticle: Codable, Identifiable, Sendable {
    let title: String
    let description: String
    let url: String
    let published: String
    let category: String

    var id: String { url }

    func isNew(asOf now: Date) -> Bool {
        guard let date = NewsDateParser.date(from: published) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < 6 * 60 * 60
    }

    var publishedText: String {
        guard let date = NewsDateParser.date(from: published) else {
            return published
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum NewsDateParser {
    static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

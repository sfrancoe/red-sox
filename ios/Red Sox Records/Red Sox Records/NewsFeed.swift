import Foundation

enum NewsSource: String, CaseIterable, Identifiable, Sendable {
    case globe
    case herald
    case athletic
    case massLive = "masslive"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .globe: "Globe"
        case .herald: "Herald"
        case .athletic: "Athletic"
        case .massLive: "MassLive"
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

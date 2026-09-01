import Foundation

enum XFeedMode: String, CaseIterable, Identifiable, Sendable {
    case recent
    case liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Most Recent"
        case .liked: "Most Liked (24 Hours)"
        }
    }
}

struct XFeed: Codable, Sendable {
    let generatedAt: String
    let source: String
    let sourceUrl: String
    let recent: [XPost]
    let popular: [XPost]

    var checkedText: String {
        guard let date = XDateParser.date(from: generatedAt) else {
            return generatedAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct XPost: Codable, Identifiable, Sendable {
    let id: String
    let text: String
    let url: String
    let published: String
    let likes: Int
    let author: String
    let handle: String
    let avatar: String
    let media: String
    let quotedText: String
    let quotedAuthor: String
    let quotedHandle: String

    var publishedText: String {
        guard let date = XDateParser.date(from: published) else {
            return published
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum XDateParser {
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

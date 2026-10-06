import Foundation

nonisolated enum XFeedMode: String, CaseIterable, Identifiable, Sendable {
    case recent
    case liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Most Recent"
        case .liked: "Most Like 24H"
        }
    }
}

nonisolated struct XFeed: Codable, Sendable {
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

nonisolated struct XPost: Codable, Identifiable, Sendable {
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

    var publishedDate: Date? {
        XDateParser.date(from: published)
    }

    var publishedText: String {
        guard let date = publishedDate else {
            return published
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

nonisolated private enum XDateParser {
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

nonisolated extension XPost {
    private enum CodingKeys: String, CodingKey {
        case id, text, url, published, likes, author, handle, avatar, media, quotedText, quotedAuthor, quotedHandle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        url = try values.decode(String.self, forKey: .url)
        published = try values.decode(String.self, forKey: .published)
        likes = try values.decode(Int.self, forKey: .likes)
        author = try values.decode(String.self, forKey: .author)
        handle = try values.decode(String.self, forKey: .handle)
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        media = try values.decodeIfPresent(String.self, forKey: .media) ?? ""
        quotedText = try values.decodeIfPresent(String.self, forKey: .quotedText) ?? ""
        quotedAuthor = try values.decodeIfPresent(String.self, forKey: .quotedAuthor) ?? ""
        quotedHandle = try values.decodeIfPresent(String.self, forKey: .quotedHandle) ?? ""
    }
}

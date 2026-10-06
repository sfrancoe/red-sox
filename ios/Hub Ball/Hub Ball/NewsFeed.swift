import Foundation

nonisolated struct NewsFeed: Codable, Sendable {
    let generatedAt: String
    let source: String
    let sourceUrl: String
    let articles: [NewsArticle]

    var refreshedText: String {
        guard let date = FeedDate.date(from: generatedAt) else {
            return generatedAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

nonisolated struct NewsArticle: Codable, Identifiable, Sendable {
    let title: String
    let description: String
    let url: String
    let published: String
    let category: String

    var id: String {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "\(title)\u{1F}\(published)" : value
    }

    func isNew(asOf now: Date) -> Bool {
        guard let date = FeedDate.date(from: published) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < 6 * 60 * 60
    }

    var publishedText: String {
        guard let date = FeedDate.date(from: published) else {
            return published
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}


nonisolated extension NewsArticle {
    private enum CodingKeys: String, CodingKey {
        case title, description, url, published, category
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try values.decode(String.self, forKey: .url)
        published = try values.decode(String.self, forKey: .published)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? ""
    }
}

nonisolated extension NewsFeed {
    private enum CodingKeys: String, CodingKey { case generatedAt, source, sourceUrl, articles }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try values.decode(String.self, forKey: .generatedAt)
        source = try values.decode(String.self, forKey: .source)
        sourceUrl = try values.decode(String.self, forKey: .sourceUrl)
        var seen = Set<String>()
        articles = try values.decode([NewsArticle].self, forKey: .articles).filter { seen.insert($0.id).inserted }
    }
}

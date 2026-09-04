import Foundation
import Observation

@MainActor
@Observable
final class HeadlinesStore {
    var selectedSource: NewsSource = .nyTimes
    var feeds: [NewsSource: NewsFeed] = [:]
    var isLoading = false
    var errorMessage: String?

    var selectedFeed: NewsFeed? {
        feeds[selectedSource]
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let nyTimes = Self.fetch(.nyTimes)
            async let nyPost = Self.fetch(.nyPost)
            async let dailyNews = Self.fetch(.dailyNews)
            async let athletic = Self.fetch(.athletic)

            let loadedFeeds = try await [nyTimes, nyPost, dailyNews, athletic]
            feeds = Dictionary(
                uniqueKeysWithValues: loadedFeeds.map { ($0.source, $0.feed) }
            )
        } catch {
            errorMessage = "We couldn't load the headlines. Check your connection and try again."
        }
    }

    private static func fetch(
        _ source: NewsSource
    ) async throws -> (source: NewsSource, feed: NewsFeed) {
        let url = URL(
            string: TeamConfig.dataURL("\(source.fileName).json").absoluteString
        )!
        let data = try await FeedDataLoader.data(
            from: url,
            bundledResource: "yankees-\(source.fileName)"
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (source, try decoder.decode(NewsFeed.self, from: data))
    }
}

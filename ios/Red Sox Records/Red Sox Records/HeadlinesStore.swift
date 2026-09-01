import Foundation
import Observation

@MainActor
@Observable
final class HeadlinesStore {
    var selectedSource: NewsSource = .globe
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
            async let globe = Self.fetch(.globe)
            async let herald = Self.fetch(.herald)
            async let athletic = Self.fetch(.athletic)
            async let massLive = Self.fetch(.massLive)

            let loadedFeeds = try await [globe, herald, athletic, massLive]
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
            string: "https://red-sox.netlify.app/data/\(source.fileName).json"
        )!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HeadlinesError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (source, try decoder.decode(NewsFeed.self, from: data))
    }
}

private enum HeadlinesError: Error {
    case badResponse
}

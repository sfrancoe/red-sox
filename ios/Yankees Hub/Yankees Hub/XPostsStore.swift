import Foundation
import Observation

@MainActor
@Observable
final class XPostsStore {
    private static let curatedEndpoint = TeamConfig.apiURL(
        "x-posts",
        queryItems: [URLQueryItem(name: "team", value: "yankees")]
    )
    private static let discoveryEndpoint = TeamConfig.apiURL(
        "x-discovery",
        queryItems: [URLQueryItem(name: "team", value: "yankees")]
    )

    var feed: XFeed?
    var selectedMode: XFeedMode = .liked
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let curatedRequest = fetchFeed(from: Self.curatedEndpoint)
            async let discoveryRequest = optionalFeed(from: Self.discoveryEndpoint)
            let (curated, discovery) = try await (curatedRequest, discoveryRequest)
            feed = mergedFeed(curated: curated, discovery: discovery)
        } catch {
            errorMessage = "We couldn't load the X posts. Check your connection and try again."
        }
    }

    private func optionalFeed(from endpoint: URL) async -> XFeed? {
        try? await fetchFeed(from: endpoint)
    }

    private func fetchFeed(from endpoint: URL) async throws -> XFeed {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw XPostsError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XFeed.self, from: data)
    }

    private func mergedFeed(curated: XFeed, discovery: XFeed?) -> XFeed {
        guard let discovery else { return curated }

        var uniquePosts = Dictionary(uniqueKeysWithValues: curated.popular.map { ($0.id, $0) })
        for post in discovery.popular {
            if let existing = uniquePosts[post.id], existing.likes > post.likes {
                continue
            }
            uniquePosts[post.id] = post
        }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let leaderboardSize = curated.popular.count
        let rankedPosts = uniquePosts.values
            .filter { $0.publishedDate.map { $0 >= cutoff } ?? false }
            .sorted {
                if $0.likes != $1.likes { return $0.likes > $1.likes }
                return $0.published > $1.published
            }
        let popular = Array(rankedPosts.prefix(leaderboardSize))

        return XFeed(
            generatedAt: max(curated.generatedAt, discovery.generatedAt),
            source: curated.source,
            sourceUrl: curated.sourceUrl,
            recent: curated.recent,
            popular: popular
        )
    }
}

private enum XPostsError: Error {
    case badResponse
}

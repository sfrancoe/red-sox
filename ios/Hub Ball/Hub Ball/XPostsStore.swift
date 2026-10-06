import Foundation
import Observation

@MainActor
@Observable
final class XPostsStore {
    private let api: APIClient
    private let curatedEndpoint: URL
    private let discoveryEndpoint: URL

    var feed: XFeed?
    var selectedMode: XFeedMode = .recent
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston, api: APIClient = .shared) {
        self.api = api
        curatedEndpoint = AppBackend.apiURL("x-posts", team: team)
        discoveryEndpoint = AppBackend.apiURL("x-discovery", team: team)
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let curatedRequest = fetchFeed(from: curatedEndpoint)
            async let discoveryRequest = optionalFeed(from: discoveryEndpoint)
            let (curated, discovery) = try await (curatedRequest, discoveryRequest)
            feed = mergedFeed(curated: curated, discovery: discovery)
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            errorMessage = "We couldn't load the X posts. Check your connection and try again."
        }
    }

    private func optionalFeed(from endpoint: URL) async -> XFeed? {
        try? await fetchFeed(from: endpoint)
    }

    private func fetchFeed(from endpoint: URL) async throws -> XFeed {
        try await api.get(.url(endpoint))
    }

    private func mergedFeed(curated: XFeed, discovery: XFeed?) -> XFeed {
        guard let discovery else { return curated }

        var uniquePosts = curated.popular.reduce(into: [String: XPost]()) { $0[$1.id] = $1 }
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


import Foundation
import Observation

@MainActor
@Observable
final class HeadlinesStore {
    private let team: HubTeam
    var selectedSource: NewsSource
    var feeds: [NewsSource: NewsFeed] = [:]
    var isLoading = false
    var errorMessage: String?

    var selectedFeed: NewsFeed? {
        feeds[selectedSource]
    }

    init(team: HubTeam = .boston) {
        self.team = team
        selectedSource = team.newsSources[0]
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedFeeds = try await withThrowingTaskGroup(
                of: (source: NewsSource, feed: NewsFeed).self
            ) { group in
                for source in team.newsSources {
                    group.addTask { [team] in
                        try await Self.fetch(source, team: team)
                    }
                }

                var results: [(source: NewsSource, feed: NewsFeed)] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            feeds = Dictionary(
                uniqueKeysWithValues: loadedFeeds.map { ($0.source, $0.feed) }
            )
        } catch {
            errorMessage = "We couldn't load the headlines. Check your connection and try again."
        }
    }

    private static func fetch(
        _ source: NewsSource,
        team: HubTeam
    ) async throws -> (source: NewsSource, feed: NewsFeed) {
        let url = AppBackend.dataURL("\(source.fileName).json", team: team)
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

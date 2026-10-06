import Foundation
import Observation

@MainActor
@Observable
final class HeadlinesStore {
    private let api: APIClient
    private let team: HubTeam
    var selectedSource: NewsSource
    var feeds: [NewsSource: NewsFeed] = [:]
    var isLoading = false
    var errorMessage: String?

    var selectedFeed: NewsFeed? {
        feeds[selectedSource]
    }

    init(team: HubTeam = .boston, api: APIClient = .shared) {
        self.api = api
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
                    group.addTask { [team, api] in
                        (source, try await api.get(.data("\(source.fileName).json", team: team)) as NewsFeed)
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

}

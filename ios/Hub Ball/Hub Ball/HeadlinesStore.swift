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
    var errors: [NewsSource: String] = [:]
    var errorMessage: String? { errors.isEmpty ? nil : "Some newspapers are unavailable. Pull to refresh or try again." }

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
        defer { isLoading = false }
        let api = self.api
        let team = self.team
        await withTaskGroup(of: (NewsSource, Result<NewsFeed, Error>).self) { group in
            for source in team.newsSources {
                group.addTask {
                    do { return (source, .success(try await api.get(.data("\(source.fileName).json", team: team)))) }
                    catch { return (source, .failure(error)) }
                }
            }
            for await (source, result) in group {
                guard !Task.isCancelled else { return }
                switch result {
                case let .success(feed): feeds[source] = feed; errors[source] = nil
                case let .failure(error):
                    if !APIError.isCancellation(error) { errors[source] = "Newspaper unavailable" }
                }
            }
        }
    }
}

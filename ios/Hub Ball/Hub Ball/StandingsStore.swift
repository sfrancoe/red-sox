import Foundation
import Observation

@MainActor
@Observable
final class StandingsStore {
    private let api: APIClient
    private let endpoints: [StandingsLeague: URL]

    let selectedLeague: StandingsLeague
    var feeds: [StandingsLeague: StandingsFeed] = [:]
    var mode: StandingsMode
    var isLoading = false
    var errors: [StandingsLeague: String] = [:]
    var errorMessage: String? { errors.isEmpty ? nil : "Some standings are unavailable. Showing the latest loaded sections." }

    init(team: HubTeam = .boston, api: APIClient = .shared) {
        self.api = api
        let league: StandingsLeague = team.definition.league == "NL" ? .national : .american
        selectedLeague = league
        mode = league.divisionsMode

        let americanSource = league == .american ? team : HubTeam.boston
        let nationalSource = league == .national ? team : HubTeam.newYorkMets
        endpoints = [
            .american: AppBackend.apiURL("mlb/standings", team: americanSource),
            .national: AppBackend.apiURL("mlb/standings", team: nationalSource),
        ]
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        let api = self.api
        await withTaskGroup(of: (StandingsLeague, Result<StandingsFeed, Error>).self) { group in
            for (league, endpoint) in endpoints {
                group.addTask {
                    do { return (league, .success(try await api.get(.url(endpoint)))) }
                    catch { return (league, .failure(error)) }
                }
            }
            for await (league, result) in group {
                guard !Task.isCancelled else { return }
                switch result {
                case let .success(feed):
                    feeds[league] = feed
                    errors[league] = nil
                case let .failure(error):
                    if !APIError.isCancellation(error) { errors[league] = "Standings unavailable" }
                }
            }
        }
    }
}

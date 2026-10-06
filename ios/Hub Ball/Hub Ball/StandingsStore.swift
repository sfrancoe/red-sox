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
    var errorMessage: String?

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
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let americanURL = endpoints[.american],
                  let nationalURL = endpoints[.national] else {
                throw URLError(.badServerResponse)
            }
            async let americanData = fetch(americanURL)
            async let nationalData = fetch(nationalURL)
            let (loadedAmericanData, loadedNationalData) = try await (americanData, nationalData)
            feeds = [
                .american: try await api.decode(StandingsFeed.self, from: loadedAmericanData),
                .national: try await api.decode(StandingsFeed.self, from: loadedNationalData),
            ]
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            errorMessage = "We couldn't load the standings. Check your connection and try again."
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        try await api.data(.url(url))
    }
}


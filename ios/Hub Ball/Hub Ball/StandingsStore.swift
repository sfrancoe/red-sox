import Foundation
import Observation

@MainActor
@Observable
final class StandingsStore {
    private let endpoints: [StandingsLeague: URL]

    let selectedLeague: StandingsLeague
    var feeds: [StandingsLeague: StandingsFeed] = [:]
    var mode: StandingsMode
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston) {
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
                throw StandingsError.badResponse
            }
            async let americanData = Self.fetch(americanURL)
            async let nationalData = Self.fetch(nationalURL)
            let (loadedAmericanData, loadedNationalData) = try await (americanData, nationalData)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feeds = [
                .american: try decoder.decode(StandingsFeed.self, from: loadedAmericanData),
                .national: try decoder.decode(StandingsFeed.self, from: loadedNationalData),
            ]
        } catch {
            errorMessage = "We couldn't load the standings. Check your connection and try again."
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StandingsError.badResponse
        }
        return data
    }
}

private enum StandingsError: Error {
    case badResponse
}

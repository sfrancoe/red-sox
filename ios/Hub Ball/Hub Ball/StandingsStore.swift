import Foundation
import Observation

@MainActor
@Observable
final class StandingsStore {
    private let endpoint: URL

    var feed: StandingsFeed?
    var mode: StandingsMode = .divisions
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston) {
        endpoint = AppBackend.dataURL("standings.json", team: team)
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw StandingsError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feed = try decoder.decode(StandingsFeed.self, from: data)
        } catch {
            errorMessage = "We couldn't load the standings. Check your connection and try again."
        }
    }
}

private enum StandingsError: Error {
    case badResponse
}

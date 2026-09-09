import Foundation
import Observation

@MainActor
@Observable
final class PlayersStore {
    let team: HubTeam

    var feed: PlayersFeed?
    var filter: PlayerPositionFilter = .all
    var searchText = ""
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam) {
        self.team = team
    }

    var visiblePlayers: [RedSoxPlayer] {
        guard let feed else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return feed.players.filter { player in
            let matchesPosition = filter == .all || player.positionFilter == filter
            let matchesSearch = query.isEmpty
                || player.name.localizedCaseInsensitiveContains(query)
                || player.position.name.localizedCaseInsensitiveContains(query)
                || player.number == query
            return matchesPosition && matchesSearch
        }
    }

    func player(id: Int) -> RedSoxPlayer? {
        feed?.players.first { $0.id == id }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let bundled = try? loadBundledSnapshot()
        if let bundled {
            feed = bundled
        }
        do {
            let remote = try await loadRemote()
            let bundledSeason = bundled?.source.statsThrough ?? 0
            let remoteSeason = remote.source.statsThrough ?? 0
            if bundled == nil || remoteSeason >= bundledSeason {
                feed = remote
            }
        } catch {
            if feed == nil {
                errorMessage = "We couldn't load the \(team.shortName) roster. Check your connection and try again."
            }
        }
    }

    private func loadRemote() async throws -> PlayersFeed {
        var request = URLRequest(url: AppBackend.dataURL("players.json", team: team))
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw PlayersError.badResponse
        }
        return try decode(data)
    }

    private func loadBundledSnapshot() throws -> PlayersFeed {
        guard team == .boston else {
            throw PlayersError.missingSnapshot
        }
        guard let url = Bundle.main.url(forResource: "players", withExtension: "json") else {
            throw PlayersError.missingSnapshot
        }
        return try decode(Data(contentsOf: url))
    }

    private func decode(_ data: Data) throws -> PlayersFeed {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PlayersFeed.self, from: data)
    }
}

private enum PlayersError: Error {
    case badResponse
    case missingSnapshot
}

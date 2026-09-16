import Foundation
import Observation

@MainActor
@Observable
final class PlayersStore {
    let team: HubTeam

    var feed: PlayersFeed?
    var filter: PlayerPositionFilter = .all
    var searchText = ""
    var sort: PlayerDirectorySort = .name
    var sortsAscending = true
    var isLoading = false
    var errorMessage: String?
    private var careers: [Int: PlayerCareerFeed] = [:]
    private var careerErrors: [Int: String] = [:]
    private var loadingCareerIDs = Set<Int>()

    init(team: HubTeam) {
        self.team = team
    }

    var visiblePlayers: [RedSoxPlayer] {
        guard let feed else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = feed.players.filter { player in
            let matchesPosition = filter == .all || player.positionFilter == filter
            let matchesSearch = query.isEmpty
                || player.name.localizedCaseInsensitiveContains(query)
                || player.position.name.localizedCaseInsensitiveContains(query)
                || player.number == query
            return matchesPosition && matchesSearch
        }
        return filtered.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .number:
                comparison = (Int(lhs.number ?? "") ?? Int.max) < (Int(rhs.number ?? "") ?? Int.max) ? .orderedAscending : .orderedDescending
            case .position:
                comparison = lhs.position.abbreviation.localizedCaseInsensitiveCompare(rhs.position.abbreviation)
            case .batsThrows:
                comparison = "\(lhs.bats ?? "")/\(lhs.throws ?? "")".localizedCaseInsensitiveCompare("\(rhs.bats ?? "")/\(rhs.throws ?? "")")
            case .age:
                comparison = (lhs.age ?? Int.max) < (rhs.age ?? Int.max) ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return sortsAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    func player(id: Int) -> RedSoxPlayer? {
        feed?.players.first { $0.id == id }
    }

    func career(for player: RedSoxPlayer) -> PlayerCareerFeed? {
        careers[player.id]
    }

    func careerError(for player: RedSoxPlayer) -> String? {
        careerErrors[player.id]
    }

    func isLoadingCareer(for player: RedSoxPlayer) -> Bool {
        loadingCareerIDs.contains(player.id)
    }

    func toggleSort(_ column: PlayerDirectorySort) {
        if sort == column {
            sortsAscending.toggle()
        } else {
            sort = column
            sortsAscending = true
        }
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

    func loadCareer(for player: RedSoxPlayer) async {
        guard careers[player.id] == nil, !loadingCareerIDs.contains(player.id) else { return }
        loadingCareerIDs.insert(player.id)
        careerErrors[player.id] = nil
        defer { loadingCareerIDs.remove(player.id) }

        do {
            var request = URLRequest(url: AppBackend.sharedDataURL("player-careers/\(player.id).json"))
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw PlayersError.missingCareer
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            careers[player.id] = try decoder.decode(PlayerCareerFeed.self, from: data)
        } catch {
            // A roster profile remains useful while the independent detailed feed is
            // unavailable. The card makes that gap explicit instead of inventing rows.
            careerErrors[player.id] = "The detailed career record is not available in this snapshot."
        }
    }
}

private enum PlayersError: Error {
    case badResponse
    case missingSnapshot
    case missingCareer
}

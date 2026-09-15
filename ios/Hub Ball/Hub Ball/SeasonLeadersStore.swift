import Foundation
import Observation

@MainActor
@Observable
final class SeasonLeadersStore {
    private let seasonsURL: URL
    private let metadataURL: URL

    var seasons: [String: SeasonLeaders] = [:]
    var metadata: LeadersMetadata?
    var isLoading = false
    var errorMessage: String?
    var comparisons: [String: LeagueLeadersPayload] = [:]
    var comparisonErrors: [String: String] = [:]
    private var comparisonTasks: [String: Task<Void, Never>] = [:]

    init(team: HubTeam = .boston) {
        seasonsURL = AppBackend.dataURL("seasons.json", team: team)
        metadataURL = AppBackend.dataURL("meta.json", team: team)
    }

    var sortedYears: [String] {
        seasons.keys.sorted(by: >)
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let seasonsData = Self.fetch(seasonsURL)
            async let metadataData = Self.fetch(metadataURL)
            let (loadedSeasonsData, loadedMetadataData) = try await (
                seasonsData,
                metadataData
            )

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            seasons = try decoder.decode(
                [String: SeasonLeaders].self,
                from: loadedSeasonsData
            )
            metadata = try decoder.decode(
                LeadersMetadata.self,
                from: loadedMetadataData
            )
            if let newest = sortedYears.first {
                await loadComparison(year: newest)
            }
        } catch {
            errorMessage = "We couldn't load the season leaders. Check your connection and try again."
        }
    }

    func comparison(year: String) -> LeagueLeadersPayload? { comparisons[year] }

    func loadComparison(year: String) async {
        guard comparisons[year] == nil, comparisonTasks[year] == nil else { return }
        let task = Task { @MainActor [weak self] in
            defer { self?.comparisonTasks[year] = nil }
            do {
                let data = try await Self.fetch(AppBackend.sharedDataURL("leaderboards/\(year).json"))
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let payload = try decoder.decode(LeagueLeadersPayload.self, from: data)
                guard payload.schemaVersion == 1, payload.season == Int(year) else { throw SeasonLeadersError.badResponse }
                self?.comparisons[year] = payload
                self?.comparisonErrors.removeValue(forKey: year)
            } catch {
                self?.comparisonErrors[year] = "League leaders unavailable."
            }
        }
        comparisonTasks[year] = task
        await task.value
    }

    func retryComparison(year: String) async {
        comparisons.removeValue(forKey: year)
        comparisonErrors.removeValue(forKey: year)
        await loadComparison(year: year)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SeasonLeadersError.badResponse
        }
        return data
    }
}

private enum SeasonLeadersError: Error {
    case badResponse
}

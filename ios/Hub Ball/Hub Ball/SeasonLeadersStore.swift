import Foundation
import Observation

@MainActor
@Observable
final class SeasonLeadersStore {
    private let api: APIClient
    private let seasonsURL: URL
    private let metadataURL: URL

    var seasons: [String: SeasonLeaders] = [:]
    var metadata: LeadersMetadata?
    var isLoading = false
    var errorMessage: String?
    var comparisons: [String: LeagueLeadersPayload] = [:]
    var comparisonErrors: [String: String] = [:]
    private var comparisonTasks: [String: Task<Void, Never>] = [:]

    init(team: HubTeam = .boston, api: APIClient = .shared) {
        self.api = api
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
            async let seasonsData = fetch(seasonsURL)
            async let metadataData = fetch(metadataURL)
            let (loadedSeasonsData, loadedMetadataData) = try await (
                seasonsData,
                metadataData
            )

            seasons = try await api.decode(
                [String: SeasonLeaders].self,
                from: loadedSeasonsData
            )
            metadata = try await api.decode(
                LeadersMetadata.self,
                from: loadedMetadataData
            )
            if let newest = sortedYears.first {
                await loadComparison(year: newest)
            }
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            errorMessage = "We couldn't load the season leaders. Check your connection and try again."
        }
    }

    func comparison(year: String) -> LeagueLeadersPayload? { comparisons[year] }

    func loadComparison(year: String) async {
        guard comparisons[year] == nil, comparisonTasks[year] == nil else { return }
        let task = Task { @MainActor [weak self] in
            defer { self?.comparisonTasks[year] = nil }
            do {
                guard let self else { return }
                let data = try await fetch(AppBackend.sharedDataURL("leaderboards/\(year).json"))
                let payload = try await api.decode(LeagueLeadersPayload.self, from: data)
                guard payload.schemaVersion == 1, payload.season == Int(year) else { throw URLError(.cannotDecodeContentData) }
                self.comparisons[year] = payload
                self.comparisonErrors.removeValue(forKey: year)
            } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
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

    private func fetch(_ url: URL) async throws -> Data {
        try await api.data(.url(url))
    }
}


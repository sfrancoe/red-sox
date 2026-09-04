import Foundation
import Observation

@MainActor
@Observable
final class SeasonLeadersStore {
    private static let seasonsURL = TeamConfig.dataURL("seasons.json")
    private static let metadataURL = TeamConfig.dataURL("meta.json")

    var seasons: [String: SeasonLeaders] = [:]
    var metadata: LeadersMetadata?
    var isLoading = false
    var errorMessage: String?

    var sortedYears: [String] {
        seasons.keys.sorted(by: >)
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let seasonsData = FeedDataLoader.data(
                from: Self.seasonsURL,
                bundledResource: "yankees-seasons"
            )
            async let metadataData = FeedDataLoader.data(
                from: Self.metadataURL,
                bundledResource: "yankees-meta"
            )
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
        } catch {
            errorMessage = "We couldn't load the season leaders. Check your connection and try again."
        }
    }

}

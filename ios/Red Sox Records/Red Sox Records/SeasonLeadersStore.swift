import Foundation
import Observation

@MainActor
@Observable
final class SeasonLeadersStore {
    private static let seasonsURL = URL(
        string: "https://red-sox.netlify.app/data/seasons.json"
    )!
    private static let metadataURL = URL(
        string: "https://red-sox.netlify.app/data/meta.json"
    )!

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
            async let seasonsData = Self.fetch(Self.seasonsURL)
            async let metadataData = Self.fetch(Self.metadataURL)
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

import Foundation
import Observation

@MainActor
@Observable
final class StandingsStore {
    private static let endpoint = TeamConfig.dataURL("standings.json")

    var feed: StandingsFeed?
    var mode: StandingsMode = .divisions
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await FeedDataLoader.data(
                from: Self.endpoint,
                bundledResource: "yankees-standings"
            )
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feed = try decoder.decode(StandingsFeed.self, from: data)
        } catch {
            errorMessage = "We couldn't load the standings. Check your connection and try again."
        }
    }
}

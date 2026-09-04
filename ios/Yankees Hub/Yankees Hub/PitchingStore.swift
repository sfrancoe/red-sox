import Foundation
import Observation

@MainActor
@Observable
final class PitchingStore {
    private static let endpoint = TeamConfig.dataURL("pitching.json")

    var feed: PitchingFeed?
    var filter: PitcherFilter = .both
    var sort: PitcherSort = .impact
    var isLoading = false
    var errorMessage: String?

    var visiblePitchers: [PitcherReport] {
        guard let feed else { return [] }
        let filtered = feed.pitchers.filter { pitcher in
            switch filter {
            case .both: true
            case .starters: pitcher.isStarter
            case .relievers: !pitcher.isStarter
            }
        }
        return filtered.sorted { first, second in
            switch sort {
            case .impact:
                first.actual.war > second.actual.war
            case .surprise:
                first.warGap > second.warGap
            case .workload:
                first.actual.ipValue > second.actual.ipValue
            }
        }
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await FeedDataLoader.data(
                from: Self.endpoint,
                bundledResource: "yankees-pitching"
            )
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feed = try decoder.decode(PitchingFeed.self, from: data)
        } catch {
            errorMessage = "We couldn't load the pitching outlook. Check your connection and try again."
        }
    }
}

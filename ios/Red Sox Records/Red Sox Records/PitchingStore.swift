import Foundation
import Observation

@MainActor
@Observable
final class PitchingStore {
    private static let endpoint = URL(
        string: "https://red-sox.netlify.app/data/pitching.json"
    )!

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
            var request = URLRequest(url: Self.endpoint)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw PitchingError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feed = try decoder.decode(PitchingFeed.self, from: data)
        } catch {
            errorMessage = "We couldn't load the pitching outlook. Check your connection and try again."
        }
    }
}

private enum PitchingError: Error {
    case badResponse
}

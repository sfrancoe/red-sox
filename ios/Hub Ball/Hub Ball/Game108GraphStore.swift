import Foundation
import Observation

@MainActor
@Observable
final class Game108GraphStore {
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }
    private static let endpoint = AppBackend.dataURL("seasons.json")

    var series: [GraphSeries] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let decoded: [String: GraphSeasonData] = try await api.get(.url(Self.endpoint))

            series = Game108Story.stories.compactMap { story in
                guard let season = decoded[String(story.year)] else { return nil }
                return GraphSeries(year: story.year, data: season)
            }
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            errorMessage = "We couldn't load the Game 108 data. Check your connection and try again."
        }
    }
}


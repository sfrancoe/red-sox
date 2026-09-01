import Foundation
import Observation

@MainActor
@Observable
final class Game108GraphStore {
    private static let endpoint = URL(
        string: "https://red-sox.netlify.app/data/seasons.json"
    )!

    var series: [GraphSeries] = []
    var isLoading = false
    var errorMessage: String?

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
                throw Game108GraphError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(
                [String: GraphSeasonData].self,
                from: data
            )

            series = Game108Story.stories.compactMap { story in
                guard let season = decoded[String(story.year)] else { return nil }
                return GraphSeries(year: story.year, data: season)
            }
        } catch {
            errorMessage = "We couldn't load the Game 108 data. Check your connection and try again."
        }
    }
}

private enum Game108GraphError: Error {
    case badResponse
}

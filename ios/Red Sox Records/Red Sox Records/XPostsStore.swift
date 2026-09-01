import Foundation
import Observation

@MainActor
@Observable
final class XPostsStore {
    private static let endpoint = URL(
        string: "https://red-sox.netlify.app/api/x-posts"
    )!

    var feed: XFeed?
    var selectedMode: XFeedMode = .recent
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
                throw XPostsError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            feed = try decoder.decode(XFeed.self, from: data)
        } catch {
            errorMessage = "We couldn't load the X posts. Check your connection and try again."
        }
    }
}

private enum XPostsError: Error {
    case badResponse
}

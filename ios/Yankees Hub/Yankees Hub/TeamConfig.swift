import Foundation

enum TeamConfig {
    static let teamID = 147
    static let teamName = "New York Yankees"
    static let shortName = "Yankees"
    static let cityName = "New York"
    static let appName = "NY Baseball Hub"
    static let navigationTitle = "NY BASEBALL HUB"

    private static let dataRoot = URL(string: "https://red-sox.netlify.app/data/yankees/")!
    private static let apiRoot = URL(string: "https://red-sox.netlify.app/api/")!

    static func dataURL(_ fileName: String) -> URL {
        dataRoot.appending(path: fileName)
    }

    static func apiURL(_ endpoint: String, queryItems: [URLQueryItem] = []) -> URL {
        let url = apiRoot.appending(path: endpoint)
        guard !queryItems.isEmpty else { return url }
        return url.appending(queryItems: queryItems)
    }
}

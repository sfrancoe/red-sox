import Foundation

enum AppBackend {
    // Keep the provider-specific hostname in one place. Replace this with the
    // app's custom API domain before release without touching every store.
    nonisolated private static let origin = URL(string: "https://red-sox.netlify.app")!

    nonisolated static func dataURL(_ path: String, team: HubTeam = .boston) -> URL {
        var root = dataRoot
        if let teamPath = team.dataPathComponent {
            root = root.appending(path: teamPath)
        }
        return root.appending(path: path)
    }

    nonisolated private static var dataRoot: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_DATA_ROOT"],
           let override = URL(string: value) {
            return override
        }
        return origin.appending(path: "data")
        #else
        return origin
            .appending(path: "api")
            .appending(path: "data")
        #endif
    }

    nonisolated static func apiURL(_ endpoint: String, team: HubTeam = .boston) -> URL {
        let url = origin
            .appending(path: "api")
            .appending(path: endpoint)
        return url.appending(queryItems: [URLQueryItem(name: "team", value: team.apiKey)])
    }
}

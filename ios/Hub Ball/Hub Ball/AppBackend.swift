import Foundation

enum AppBackend {
    // Set HUB_API_ORIGIN after verifying the custom domain's DNS, TLS and routes.
    // Keep the previous hostname available to already installed binaries.
    nonisolated static let origin: URL = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "HubAPIOrigin") as? String
        if let configured, let url = URL.safeWeb(configured), url.scheme == "https" { return url }
        return URL(string: "https://red-sox.netlify.app")!
    }()

    nonisolated static func dataURL(_ path: String, team: HubTeam) -> URL {
        var root = dataRoot
        if let teamPath = team.dataPathComponent {
            root = root.appending(path: teamPath)
        }
        return root.appending(path: path)
    }

    /// A shared app-data artifact. Unlike `dataURL`, this intentionally omits a
    /// team directory so every club reads the same comparison snapshot.
    nonisolated static func sharedDataURL(_ path: String) -> URL {
        dataRoot.appending(path: path)
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

    nonisolated static func apiURL(_ endpoint: String, team: HubTeam) -> URL {
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_API_ROOT"],
           let override = URL(string: value) {
            return override
                .appending(path: "api")
                .appending(path: endpoint)
                .appending(queryItems: [URLQueryItem(name: "team", value: team.apiKey)])
        }
#endif
        let url = origin
            .appending(path: "api")
            .appending(path: endpoint)
        return url.appending(queryItems: [URLQueryItem(name: "team", value: team.apiKey)])
    }

    nonisolated static func sharedAPIURL(_ endpoint: String) -> URL {
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_API_ROOT"],
           let override = URL(string: value) {
            return override.appending(path: "api").appending(path: endpoint)
        }
#endif
        return origin.appending(path: "api").appending(path: endpoint)
    }
}

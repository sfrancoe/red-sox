import Foundation

extension URL {
    /// Accept only absolute web URLs from feeds before opening Safari or fetching images.
    nonisolated static func safeWeb(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

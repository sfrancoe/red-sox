import Foundation

/// Evictable feed snapshots belong in Caches, not preferences or user documents.
actor SnapshotFileCache {
    private let url: URL
    private let maxBytes = 2 * 1_024 * 1_024
    init(name: String, directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "HubBall", directoryHint: .isDirectory)
        url = directory.appending(path: name)
    }
    func read() -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }
    @discardableResult func write(_ data: Data) -> Bool {
        guard data.count <= maxBytes else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}

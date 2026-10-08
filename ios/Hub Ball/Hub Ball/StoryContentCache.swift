import Foundation

nonisolated struct CachedStory: Codable, Sendable {
    let entry: StoryEntry
    let data: Data
    func decoded() throws -> StoryDocument { try entry.validate(); return try StoryContract.decodeDocument(data, entry: entry) }
}

/// A bounded last-good slot per story keeps yesterday's valid revision on partial failure.
actor StoryContentCache {
    private let directory: URL
    private let maximumBytes: Int
    private let maximumStories: Int
    init(directory: URL? = nil, maximumBytes: Int = 8 * 1_024 * 1_024, maximumStories: Int = 40) {
        var name = "Stories"
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_STORY_CACHE_NAME"], StoryContract.slug(value) { name += "-" + value }
        #endif
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "HubBall/\(name)", directoryHint: .isDirectory)
        self.maximumBytes = maximumBytes
        self.maximumStories = maximumStories
    }
    func catalog() -> Data? { read("catalog.json", limit: StoryContract.catalogLimit) }
    func story(id: String) -> CachedStory? {
        guard StoryContract.slug(id), let data = read("\(id).json", limit: StoryContract.payloadLimit * 2),
              let cached = try? JSONDecoder().decode(CachedStory.self, from: data), cached.entry.id == id,
              (try? cached.decoded()) != nil else { return nil }
        return cached
    }
    func saveCatalog(_ data: Data) {
        guard (try? StoryContract.decodeCatalog(data)) != nil else { return }
        write(data, name: "catalog.json")
    }
    func saveStory(_ cached: CachedStory) {
        guard (try? cached.decoded()) != nil, let data = try? JSONEncoder().encode(cached), data.count <= maximumBytes else { return }
        write(data, name: "\(cached.entry.id).json")
        prune(keeping: cached.entry.id)
    }
    private func read(_ name: String, limit: Int) -> Data? {
        let url = directory.appending(path: name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }
    private func write(_ data: Data, name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: name), options: .atomic)
        } catch { /* Cache eviction or write failure does not discard usable in-memory content. */ }
    }
    private func prune(keeping id: String) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        var files = urls.filter { $0.lastPathComponent != "catalog.json" && $0.pathExtension == "json" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        while files.count > maximumStories || total > maximumBytes {
            guard let index = files.firstIndex(where: { $0.0.lastPathComponent != "\(id).json" }) else { break }
            let removed = files.remove(at: index)
            try? FileManager.default.removeItem(at: removed.0)
            total -= removed.1
        }
    }
}

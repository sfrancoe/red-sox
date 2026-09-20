import Foundation

struct RecentGameCacheRecord: Codable, Sendable {
    let game: RecentGame
    let lastCheckedAt: Date
    let lastFailureAt: Date?
}

struct RecentGameFreshness: Sendable {
    let lastCheckedAt: Date
    let lastFailureAt: Date?
    let isSavedSnapshot: Bool
}

actor RecentGameSnapshotCache {
    static let schemaVersion = 1
    static let maxGamesPerTeam = 4
    static let maxTeams = 8
    static let maxBytes = 10 * 1024 * 1024
    static let finalRetention: TimeInterval = 400 * 24 * 60 * 60
    static let liveRetention: TimeInterval = 24 * 60 * 60

    private let directory: URL?
    private let now: () -> Date

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? Self.defaultDirectory()
        self.now = now
    }

    func load(teamID: Int) -> [RecentGameCacheRecord]? {
        guard let fileURL = fileURL(teamID: teamID),
              let data = try? Data(contentsOf: fileURL),
              data.count <= Self.maxBytes,
              let envelope = decode(data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.teamID > 0,
              envelope.teamID == teamID,
              validTimestamp(envelope.savedAt, now: now()),
              age(of: envelope.savedAt, now: now()) <= Self.finalRetention,
              envelope.entries.count <= Self.maxGamesPerTeam,
              let entries = validEntries(envelope.entries, teamID: teamID),
              !entries.isEmpty else {
            return nil
        }
        return entries
    }

    @discardableResult
    func save(teamID: Int, records: [RecentGameCacheRecord]) -> Bool {
        guard let directory,
              let fileURL = fileURL(teamID: teamID),
              !records.isEmpty,
              records.count <= Self.maxGamesPerTeam,
              let entries = validEntries(records, teamID: teamID),
              !entries.isEmpty else {
            return false
        }

        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            teamID: teamID,
            savedAt: now(),
            entries: entries
        )
        guard let data = encode(envelope), data.count <= Self.maxBytes else { return false }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }

        enforceBounds(protectedURL: fileURL)
        return true
    }

    private func validEntries(
        _ entries: [RecentGameCacheRecord],
        teamID: Int
    ) -> [RecentGameCacheRecord]? {
        let currentDate = now()
        var gameIDs = Set<Int>()
        var valid: [RecentGameCacheRecord] = []

        for entry in entries {
            let game = entry.game
            guard game.gamePk > 0,
                  gameIDs.insert(game.gamePk).inserted,
                  game.away.id == teamID || game.home.id == teamID,
                  ISO8601DateFormatter().date(from: game.gameDate) != nil,
                  validTimestamp(entry.lastCheckedAt, now: currentDate),
                  age(of: entry.lastCheckedAt, now: currentDate)
                    <= (game.isLive ? Self.liveRetention : Self.finalRetention) else {
                continue
            }

            if let lastFailureAt = entry.lastFailureAt {
                guard validTimestamp(lastFailureAt, now: currentDate),
                      lastFailureAt >= entry.lastCheckedAt else {
                    continue
                }
            }
            valid.append(entry)
        }

        return valid
    }

    private func validTimestamp(_ date: Date, now: Date) -> Bool {
        let interval = date.timeIntervalSinceReferenceDate
        return interval.isFinite && date.timeIntervalSince(now) <= 5 * 60
    }

    private func age(of date: Date, now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(date))
    }

    private func enforceBounds(protectedURL: URL) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        var candidates = files.compactMap { url -> FileCandidate? in
            guard url.lastPathComponent.hasPrefix("recent-games-"),
                  url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            let envelope = decode(data)
            let date = envelope?.savedAt
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return FileCandidate(url: url, savedAt: date, byteCount: data.count)
        }

        var totalBytes = candidates.reduce(0) { $0 + $1.byteCount }
        while candidates.count > Self.maxTeams || totalBytes > Self.maxBytes {
            guard let victim = candidates
                .filter({ $0.url != protectedURL })
                .min(by: { $0.savedAt < $1.savedAt }) else {
                break
            }
            try? FileManager.default.removeItem(at: victim.url)
            candidates.removeAll { $0.url == victim.url }
            totalBytes -= victim.byteCount
        }
    }

    private func fileURL(teamID: Int) -> URL? {
        directory?.appendingPathComponent("recent-games-\(teamID).json")
    }

    private func encode(_ envelope: Envelope) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(envelope)
    }

    private func decode(_ data: Data) -> Envelope? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Envelope.self, from: data)
    }

    private static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RecentGames", isDirectory: true)
    }
}

private struct Envelope: Codable, Sendable {
    let schemaVersion: Int
    let teamID: Int
    let savedAt: Date
    let entries: [RecentGameCacheRecord]
}

private struct FileCandidate {
    let url: URL
    let savedAt: Date
    let byteCount: Int
}

import Foundation
import Observation

@MainActor
@Observable
final class PostseasonStore {
    private(set) var snapshot: PostseasonPayload?
    private(set) var isLoading = false
    private(set) var refreshFailed = false
    private(set) var calls: OctoberCallBook
    private(set) var selectedRootingTeamID: Int?

    let season: Int
    private let session: URLSession
    private let directory: URL

    init(season: Int = Calendar(identifier: .gregorian).component(.year, from: Date()),
         session: URLSession = .shared) {
        self.season = season
        self.session = session
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appending(path: "October", directoryHint: .isDirectory)
        calls = Self.readCalls(from: directory.appending(path: "calls-\(season).json"))
        selectedRootingTeamID = UserDefaults.standard.object(forKey: "october.rootingTeam.\(season)") as? Int
        snapshot = Self.readSnapshot(from: directory.appending(path: "snapshot-\(season).json"))
    }

    var snapshotAge: TimeInterval? {
        guard let checked = snapshot?.checkedDate else { return nil }
        return max(0, Date().timeIntervalSince(checked))
    }

    var isDelayed: Bool { snapshot?.isLive == true && (snapshotAge ?? .infinity) > 90 }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var components = URLComponents(url: AppBackend.sharedAPIURL("postseason"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "season", value: String(season))]
            var request = URLRequest(url: components.url!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let incoming = try JSONDecoder().decode(PostseasonPayload.self, from: data)
            guard incoming.schemaVersion == 1, incoming.season == season else { throw URLError(.cannotDecodeContentData) }
            snapshot = incoming
            refreshFailed = false
            persist(incoming, at: directory.appending(path: "snapshot-\(season).json"))
            updateObservedCutoffs(incoming)
            recalculateOutcomes(incoming)
        } catch is CancellationError {
            return
        } catch {
            refreshFailed = true
        }
    }

    func setRootingTeam(_ teamID: Int?) {
        selectedRootingTeamID = teamID
        if let teamID {
            UserDefaults.standard.set(teamID, forKey: "october.rootingTeam.\(season)")
        } else {
            UserDefaults.standard.removeObject(forKey: "october.rootingTeam.\(season)")
        }
    }

    func call(for series: PostseasonSeries) -> OctoberCall? { calls.calls[series.id] }

    func mayEdit(_ series: PostseasonSeries) -> Bool {
        let existing = call(for: series) != nil
        return PostseasonRules.canEdit(
            existingCall: existing,
            hasStarted: hasStarted(series),
            snapshotAge: snapshotAge
        )
    }

    func saveCall(series: PostseasonSeries, winner: Int, length: Int) {
        guard let requiredWins = series.requiredWins,
              length >= requiredWins, length <= requiredWins * 2 - 1,
              series.participants.contains(where: { $0.teamId == winner }),
              mayEdit(series) else { return }
        let previous = call(for: series)
        let firstGame = snapshot?.games.filter { $0.seriesId == series.id }
            .compactMap(\.startDate).min()
        let started = hasStarted(series)
        let timing = PostseasonRules.callTiming(
            checkedAt: snapshot?.checkedDate,
            scheduledStart: firstGame,
            hasStarted: started
        )
        let entry = OctoberCall(
            seriesID: series.id,
            winnerTeamID: winner,
            seriesLength: length,
            entryCategory: timing.category,
            createdAt: previous?.createdAt ?? Date(),
            revisedAt: Date(),
            cutoffAt: timing.cutoffAt,
            cutoffEvidence: timing.evidence,
            outcome: previous?.outcome
        )
        calls.calls[series.id] = entry
        persist(calls, at: directory.appending(path: "calls-\(season).json"))
    }

    func saveChampion(_ teamID: Int?) {
        calls.championTeamID = teamID
        persist(calls, at: directory.appending(path: "calls-\(season).json"))
    }

    func hasStarted(_ series: PostseasonSeries) -> Bool {
        snapshot?.games.contains(where: {
            $0.seriesId == series.id && ["Live", "Final"].contains($0.abstractState)
        }) ?? false
    }

    private func recalculateOutcomes(_ payload: PostseasonPayload) {
        for series in payload.series {
            guard let current = calls.calls[series.id] else { continue }
            var revised = current
            guard let winner = series.winnerTeamId else {
                revised.outcome = nil
                revised.exactLength = nil
                calls.calls[series.id] = revised
                continue
            }
            revised.outcome = current.winnerTeamID == winner ? "correct" : "missed"
            revised.exactLength = current.winnerTeamID == winner
                && current.seriesLength == series.completedGameCount
            calls.calls[series.id] = revised
        }
        persist(calls, at: directory.appending(path: "calls-\(season).json"))
    }

    private func updateObservedCutoffs(_ payload: PostseasonPayload) {
        guard let observedAt = payload.checkedDate else { return }
        for (seriesID, existing) in Array(calls.calls) where existing.entryCategory == "pre-series" {
            let hasStarted = payload.games.contains {
                $0.seriesId == seriesID && ["Live", "Final"].contains($0.abstractState)
            }
            guard hasStarted else { continue }
            var updated = existing
            updated.cutoffAt = min(existing.cutoffAt ?? observedAt, observedAt)
            updated.cutoffEvidence = "Earliest of scheduled start and first fresh source check showing the series started."
            calls.calls[seriesID] = updated
        }
        persist(calls, at: directory.appending(path: "calls-\(season).json"))
    }

    private func persist<T: Encodable>(_ value: T, at url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            // Local prediction storage can fail independently of browsing the race.
        }
    }

    private static func readSnapshot(from url: URL) -> PostseasonPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PostseasonPayload.self, from: data)
    }

    private static func readCalls(from url: URL) -> OctoberCallBook {
        guard let data = try? Data(contentsOf: url) else { return OctoberCallBook() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(OctoberCallBook.self, from: data)) ?? OctoberCallBook()
    }
}

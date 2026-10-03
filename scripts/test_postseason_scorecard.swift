import Foundation

final class ScorecardProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scheduleIsLive = false
    nonisolated(unsafe) private static var includeFinalGame = false
    nonisolated(unsafe) private static var gameVersion = 1
    nonisolated(unsafe) private static var gameRequests = 0
    nonisolated(unsafe) private static var gameRequestIDs: [Int] = []
    nonisolated(unsafe) private static var gameCachePolicies: [URLRequest.CachePolicy] = []
    nonisolated(unsafe) private static var failedGamePk: Int?
    nonisolated(unsafe) private static var failDiscovery = false
    nonisolated(unsafe) private static var emptyDiscovery = false
    nonisolated(unsafe) private static var stallRequests = false
    nonisolated(unsafe) private static var matchupOverride: [String: Any]?

    static func configure(
        live: Bool = false,
        includeFinal: Bool = false,
        scheduleGamePk: Int = 9001,
        version: Int = 1,
        failGamePk: Int? = nil,
        failDiscovery: Bool = false,
        emptyDiscovery: Bool = false,
        stall: Bool = false,
        matchup: [String: Any]? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        scheduleIsLive = live
        includeFinalGame = includeFinal
        scheduleGameID = scheduleGamePk
        gameVersion = version
        failedGamePk = failGamePk
        Self.failDiscovery = failDiscovery
        Self.emptyDiscovery = emptyDiscovery
        stallRequests = stall
        matchupOverride = matchup
    }

    nonisolated(unsafe) private static var scheduleGameID = 9001

    static var observedGameCachePolicies: [URLRequest.CachePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return gameCachePolicies
    }

    static var requestedGameIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return gameRequestIDs
    }

    static var gameRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return gameRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        let live = Self.scheduleIsLive
        let includeFinal = Self.includeFinalGame
        let scheduleGamePk = Self.scheduleGameID
        let version = Self.gameVersion
        let failedGamePk = Self.failedGamePk
        let failDiscovery = Self.failDiscovery
        let emptyDiscovery = Self.emptyDiscovery
        let stall = Self.stallRequests
        let matchup = Self.matchupOverride
        let gamePk = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "gamePk" })?.value ?? "")
        if url.path.contains("/api/mlb/game") {
            Self.gameRequests += 1
            if let gamePk {
                Self.gameRequestIDs.append(gamePk)
            }
            Self.gameCachePolicies.append(request.cachePolicy)
        }
        Self.lock.unlock()

        if stall {
            return
        }
        if url.path.contains("/api/mlb/schedule") && failDiscovery {
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if url.path.contains("/api/mlb/game") && failedGamePk == gamePk {
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let body: Data
        if url.path.contains("/api/mlb/schedule") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.first { $0.name == "gameTypes" }?.value == "R,F,D,L,W",
                         "live discovery must include every postseason round")
            let status: [String: String] = live
                ? ["abstractGameState": "Live", "codedGameState": "I"]
                : ["abstractGameState": "Final", "codedGameState": "F"]
            var games: [[String: Any]] = emptyDiscovery ? [] : [[
                "gamePk": scheduleGamePk,
                "gameType": "F",
                "gameDate": "2026-09-18T23:00:00Z",
                "status": status,
            ]]
            if includeFinal && !emptyDiscovery {
                games.append([
                    "gamePk": 9002,
                    "gameDate": "2026-09-17T23:00:00Z",
                    "status": [
                        "abstractGameState": "Final",
                        "codedGameState": "F",
                    ],
                ])
            }
            body = try! JSONSerialization.data(withJSONObject: [
                "dates": [["games": games]]
            ])
        } else if url.path.contains("/data/schedule.json") {
            body = Data(#"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#.utf8)
        } else {
            body = gamePayload(gamePk: gamePk ?? scheduleGamePk, live: live, version: version, matchup: matchup)
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func gamePayload(gamePk: Int, live: Bool, version: Int, matchup: [String: Any]?) -> Data {
        let gameIsLive = gamePk == 9001 && live
        let abstract = gameIsLive ? "Live" : "Final"
        let code = gameIsLive ? "I" : "F"
        let venue = gameIsLive
            ? "Fenway live \(version)"
            : gamePk == 9001 ? "Fenway final \(version)" : "Fenway final \(version) game \(gamePk)"
        let team = ["id": 111, "name": "Boston Red Sox", "abbreviation": "BOS", "record": [
            "leagueRecord": ["wins": 80, "losses": 70],
        ]] as [String: Any]
        let opponent = ["id": 147, "name": "New York Yankees", "abbreviation": "NYY", "record": [
            "leagueRecord": ["wins": 75, "losses": 75],
        ]] as [String: Any]
        let lineTeam = ["runs": 3, "hits": 5, "errors": 0, "leftOnBase": 4] as [String: Any]
        let lineOpponent = ["runs": 2, "hits": 4, "errors": 1, "leftOnBase": 5] as [String: Any]
        let emptyBox: [String: Any] = [
            "batters": [10, 11], "battingOrder": [10], "pitchers": [12, 13],
            "players": [
                "ID10": ["person": ["fullName": "Starting Hitter"], "position": ["abbreviation": "CF"],
                         "stats": ["batting": ["atBats": 4, "hits": 2, "rbi": 3, "homeRuns": 1]]],
                "ID11": ["person": ["fullName": "Pinch Hitter"], "position": ["abbreviation": "PH"],
                         "stats": ["batting": ["atBats": 1, "hits": 1]]],
                "ID12": ["person": ["fullName": "Starting Pitcher"],
                         "stats": ["pitching": ["inningsPitched": "5.2", "strikeOuts": 7, "numberOfPitches": 90]]],
                "ID13": ["person": ["fullName": "Relief Pitcher"],
                         "stats": ["pitching": ["inningsPitched": "0.1", "strikeOuts": 1, "numberOfPitches": 6]]]
            ]
        ]
        var linescore = matchup ?? [
            "inningState": "Top", "outs": version == 1 ? 0 : 2,
            "balls": version == 1 ? 0 : 1, "strikes": version == 1 ? 2 : 1,
            "offense": [
                "batter": ["id": 2, "fullName": version == 1 ? "Jarren Duran" : "Trevor Story"],
                "pitcher": ["fullName": "Wrong-team pitcher"],
            ],
            "defense": ["pitcher": ["id": 1, "fullName": version == 1 ? "Max Fried" : "Luke Weaver"]],
        ]
        linescore["teams"] = ["away": lineTeam, "home": lineOpponent]
        linescore["innings"] = [
            ["num": 1, "away": ["runs": 0], "home": ["runs": 2]],
            ["num": version == 2 ? 10 : 2, "away": ["runs": 3], "home": [:]]
        ]
        let payload: [String: Any] = [
            "gamePk": gamePk,
            "gameData": [
                "status": ["abstractGameState": abstract, "codedGameState": code],
                "datetime": ["dateTime": "2026-09-18T23:00:00Z"],
                "venue": ["name": venue],
                "gameInfo": ["gameDurationMinutes": 180, "attendance": 30000],
                "teams": ["away": team, "home": opponent],
                "players": [
                    "ID1": ["lastName": version == 1 ? "Fried" : "Weaver"],
                    "ID2": ["lastName": version == 1 ? "Duran" : "Story"],
                ],
            ],
            "liveData": [
                "linescore": linescore,
                "boxscore": ["teams": ["away": emptyBox, "home": emptyBox]],
                "plays": ["allPlays": [], "scoringPlays": []],
                "decisions": [:],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

@main
struct PostseasonScorecardTests {
    @MainActor
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScorecardProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let away = PostseasonClub(teamId: 111, name: "Boston", abbreviation: "BOS", slot: nil, resolved: true)
        let home = PostseasonClub(teamId: 147, name: "New York", abbreviation: "NYY", slot: nil, resolved: true)
        func selection(pk: Int = 9001, homeClub: PostseasonClub = home) -> PostseasonGame {
            PostseasonGame(gamePk: pk, seriesId: "test", gameNumber: 1, gameType: "F",
                gameDate: nil, officialDate: nil, timeTBD: false, status: "In Progress",
                abstractState: "Live", broadcasts: [], conditional: false, away: away, home: homeClub,
                awayScore: nil, homeScore: nil, winnerTeamId: nil)
        }
        let store = PostseasonScorecardStore(game: selection(), session: session)
        ScorecardProtocol.configure(live: true, failGamePk: 9001)
        await store.refresh()
        precondition(store.snapshot == nil && store.refreshFailed && !store.isLoading)
        ScorecardProtocol.configure(live: true)
        await store.refresh()
        let live = store.snapshot!
        precondition(live.isLive && !store.refreshFailed && store.checkedAt != nil)
        precondition(live.away.runs == 3 && live.away.hits == 5 && live.away.errors == 0 && live.away.leftOnBase == 4)
        precondition(live.home.runs == 2 && live.home.hits == 4 && live.home.errors == 1 && live.home.leftOnBase == 5)
        precondition(live.innings.count == 9)
        precondition(live.innings[0].away.runs == 0 && live.innings[0].home.runs == 2)
        precondition(live.innings[1].home.runs == nil && live.innings[8].away.runs == nil)
        for team in [live.away, live.home] {
            precondition(team.batting.map(\.name) == ["Starting Hitter", "Pinch Hitter"])
            precondition(team.batting[0].rbi == 3 && team.batting[1].hits == 1)
            precondition(team.pitching.map(\.name) == ["Starting Pitcher", "Relief Pitcher"])
            precondition(team.pitching[0].inningsPitched == "5.2" && team.pitching[0].strikeOuts == 7)
        }
        let checked = store.checkedAt
        ScorecardProtocol.configure(live: true, failGamePk: 9001)
        await store.refresh()
        precondition(store.refreshFailed && store.snapshot?.venue == live.venue && store.checkedAt == checked)
        ScorecardProtocol.configure(live: true, version: 2)
        await store.refresh()
        precondition(!store.refreshFailed && store.snapshot?.innings.count == 10)
        precondition(store.snapshot?.innings.last?.away.runs == 3)
        ScorecardProtocol.configure(live: false, version: 3)
        await store.refresh()
        precondition(store.snapshot?.isLive == false && !store.refreshFailed)
        precondition(ScorecardProtocol.observedGameCachePolicies.allSatisfy { $0 == .reloadIgnoringLocalCacheData })
        let wrongHome = PostseasonClub(teamId: 121, name: "Mets", abbreviation: "NYM", slot: nil, resolved: true)
        let wrong = PostseasonScorecardStore(game: selection(homeClub: wrongHome), session: session)
        await wrong.refresh()
        precondition(wrong.snapshot == nil && wrong.refreshFailed, "Reject mismatched teams")
        print("Postseason scorecard tests passed: line score, both rosters, extra innings, retry, stale data and final transition")
    }
}

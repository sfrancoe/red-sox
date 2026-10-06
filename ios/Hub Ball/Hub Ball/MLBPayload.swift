import Foundation

// Typed subset shared by both the original MLB feed and gateway schema 2.
// Optional fields represent source omissions, never invented observations.
nonisolated struct MLBSchedulePayload: Decodable, Sendable {
    var dates: [Day]?
    struct Day: Decodable, Sendable { var games: [Game]? }
    struct Game: Decodable, Sendable { var gamePk: Int?; var gameDate: String?; var status: MLBStatus? }
}
nonisolated struct MLBGamePayload: Decodable, Sendable {
    var gamePk: Int?
    var gameData: MLBGameData?
    var liveData: MLBLiveData?
    var officialRecap: OfficialRecap?
    var narratives: [String: Narrative]?
    struct Narrative: Decodable, Sendable { let summary: String; let facts: [String] }
}
nonisolated struct MLBStatus: Decodable, Sendable {
    var abstractGameState: String?
    var codedGameState: String?
}
nonisolated struct MLBPerson: Decodable, Sendable {
    var id: Int?
    var fullName: String?
    var lastName: String?
}
nonisolated struct MLBGameData: Decodable, Sendable {
    var status: MLBStatus?
    var teams: [String: MLBTeam]?
    var venue: Venue?
    var datetime: GameTime?
    var gameInfo: GameInfo?
    var players: [String: MLBPerson]?
    struct Venue: Decodable, Sendable { var name: String? }
    struct GameTime: Decodable, Sendable { var dateTime: String? }
    struct GameInfo: Decodable, Sendable { var gameDurationMinutes: Int?; var attendance: Int? }
}
nonisolated struct MLBTeam: Decodable, Sendable {
    var id: Int?
    var name: String?
    var abbreviation: String?
    var record: Record?
    struct Record: Decodable, Sendable { var leagueRecord: LeagueRecord? }
    struct LeagueRecord: Decodable, Sendable { var wins: Int?; var losses: Int? }
}
nonisolated struct MLBLiveData: Decodable, Sendable {
    var linescore: MLBLineScore?
    var boxscore: BoxScore?
    var decisions: Decisions?
    var plays: Plays?
    struct BoxScore: Decodable, Sendable { var teams: [String: MLBBox]? }
    struct Decisions: Decodable, Sendable { var winner: MLBPerson?; var loser: MLBPerson?; var save: MLBPerson? }
    struct Plays: Decodable, Sendable { var scoringPlays: [Int]?; var allPlays: [MLBPlay]? }
}
nonisolated struct MLBLineScore: Decodable, Sendable {
    var currentInning: Int?
    var currentInningOrdinal: String?
    var inningHalf: String?
    var inningState: String?
    var outs: Int?
    var balls: Int?
    var strikes: Int?
    var defense: Matchup?
    var offense: Matchup?
    var teams: [String: MLBInningSide]?
    var innings: [Inning]?
    struct Matchup: Decodable, Sendable { var pitcher: MLBPerson?; var batter: MLBPerson? }
    struct Inning: Decodable, Sendable {
        var num: Int?; var ordinalNum: String?; var home: MLBInningSide?; var away: MLBInningSide?
    }
}
nonisolated struct MLBInningSide: Decodable, Sendable {
    var runs: Int?; var hits: Int?; var errors: Int?; var leftOnBase: Int?
}
nonisolated struct MLBBox: Decodable, Sendable {
    var battingOrder: [Int]?
    var batters: [Int]?
    var pitchers: [Int]?
    var players: [String: MLBBoxPlayer]?
}
nonisolated struct MLBBoxPlayer: Decodable, Sendable {
    var person: MLBPerson?
    var position: Position?
    var stats: Stats?
    var seasonStats: Stats?
    struct Position: Decodable, Sendable { var abbreviation: String? }
    struct Stats: Decodable, Sendable { var batting: MLBStats?; var pitching: MLBStats? }
}
nonisolated struct MLBStats: Decodable, Sendable {
    var note: String?; var atBats: Int?; var runs: Int?; var hits: Int?; var rbi: Int?
    var baseOnBalls: Int?; var strikeOuts: Int?; var leftOnBase: Int?; var homeRuns: Int?
    var stolenBases: Int?; var avg: String?; var inningsPitched: String?; var earnedRuns: Int?
    var numberOfPitches: Int?
}
nonisolated struct MLBPlay: Decodable, Sendable {
    var about: About?
    var result: Result?
    var matchup: Matchup?
    struct About: Decodable, Sendable { var inning: Int?; var halfInning: String? }
    struct Result: Decodable, Sendable {
        var event: String?; var rbi: Int?; var description: String?; var awayScore: Int?; var homeScore: Int?
    }
    struct Matchup: Decodable, Sendable { var batter: MLBPerson? }
}

/// Share raw data (not team-relative prose) across Home, Recaps and playoff sheets.
actor MLBGameFeeds {
    private struct Cached: Sendable { let payload: MLBGamePayload; let checkedAt: Date }
    private var saved: [Int: Cached] = [:]
    private var pending: [Int: Task<MLBGamePayload, Error>] = [:]

    func get(_ gamePk: Int, force: Bool,
             load: @escaping @Sendable () async throws -> MLBGamePayload) async throws -> MLBGamePayload {
        if let task = pending[gamePk] { return try await task.value }
        if !force, let cached = saved[gamePk] {
            let status = cached.payload.gameData?.status
            let final = status?.abstractGameState == "Final" && ["F", "O"].contains(status?.codedGameState ?? "")
            if Date().timeIntervalSince(cached.checkedAt) < (final ? 300 : 20) { return cached.payload }
        }
        let task = Task { try await load() }
        pending[gamePk] = task
        defer { pending[gamePk] = nil }
        let payload = try await task.value
        guard payload.gamePk == gamePk else { throw URLError(.cannotDecodeContentData) }
        saved[gamePk] = Cached(payload: payload, checkedAt: Date())
        if saved.count > 16, let oldest = saved.min(by: { $0.value.checkedAt < $1.value.checkedAt })?.key {
            saved[oldest] = nil
        }
        return payload
    }
}

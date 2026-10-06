import Foundation

nonisolated struct PostseasonPayload: Codable, Sendable {
    let schemaVersion: Int
    let season: Int
    let phase: String
    let checkedAt: String
    let providerUpdatedAt: String?
    let source: String
    let sourceURL: String
    let teamsAndSlots: [PostseasonSlot]
    let series: [PostseasonSeries]
    var games: [PostseasonGame]

    var checkedDate: Date? { Self.parseDate(checkedAt) }
    var isLive: Bool { games.contains { $0.abstractState == "Live" } }

    func latestCompletedGame(for seriesID: String) -> PostseasonGame? {
        games.filter {
            $0.seriesId == seriesID && $0.abstractState == "Final" && $0.winnerTeamId != nil
        }.max {
            ($0.gameNumber ?? 0, $0.gameDate ?? "", $0.gamePk)
                < ($1.gameNumber ?? 0, $1.gameDate ?? "", $1.gamePk)
        }
    }

    func scorecardGame(for seriesID: String) -> PostseasonGame? {
        liveGame(for: seriesID) ?? latestCompletedGame(for: seriesID)
    }

    func liveGame(for seriesID: String) -> PostseasonGame? {
        games.first { $0.seriesId == seriesID && $0.abstractState == "Live" }
    }

    private static func parseDate(_ value: String) -> Date? {
        return FeedDate.date(from: value)
    }
}

nonisolated struct PostseasonSlot: Codable, Identifiable, Sendable {
    let id: String
    let teamId: Int?
    let name: String?
    let unresolved: Bool
    let qualification: String
}

nonisolated struct PostseasonClub: Codable, Identifiable, Sendable {
    let teamId: Int?
    let name: String?
    let abbreviation: String?
    let slot: String?
    let resolved: Bool

    var id: String { teamId.map(String.init) ?? "slot-\(slot ?? "unknown")" }
}

nonisolated struct PostseasonSeries: Codable, Identifiable, Sendable {
    let id: String
    let round: String
    let league: String?
    let bracketSlot: String
    let participants: [PostseasonClub]
    let unresolvedSlots: [String]
    let requiredWins: Int?
    let gameIds: [Int]
    let completedGameCount: Int
    let wins: [String: Int]?
    let winnerTeamId: Int?
    let state: String
    let nextSlots: [String]?

    func wins(for teamID: Int) -> Int? { wins?[String(teamID)] }

    var bracketSeriesStatus: String? {
        guard state != "unknown", participants.count == 2,
              let firstID = participants[0].teamId, let secondID = participants[1].teamId,
              let firstWins = wins(for: firstID), let secondWins = wins(for: secondID),
              firstWins + secondWins > 0 else { return nil }
        if firstWins == secondWins { return "Series tied \(firstWins)-\(secondWins)" }
        let leader = firstWins > secondWins ? participants[0] : participants[1]
        let name = leader.abbreviation ?? leader.name ?? "Team"
        let verb = winnerTeamId == leader.teamId ? "win" : "lead"
        return "\(name) \(verb) \(max(firstWins, secondWins))-\(min(firstWins, secondWins))"
    }
}

nonisolated struct PostseasonGame: Codable, Identifiable, Sendable {
    let gamePk: Int
    let seriesId: String?
    let gameNumber: Int?
    let gameType: String?
    let gameDate: String?
    let officialDate: String?
    let timeTBD: Bool
    let status: String
    let abstractState: String
    let broadcasts: [String]
    let conditional: Bool
    let away: PostseasonClub
    let home: PostseasonClub
    var awayScore: Int?
    var homeScore: Int?
    let winnerTeamId: Int?
    var liveInning: Int?
    var liveInningState: String?
    var liveOuts: Int?
    var livePitcher: String?
    var liveBatter: String?

    var id: Int { gamePk }

    func score(for teamID: Int) -> Int? {
        if away.teamId == teamID { return awayScore }
        if home.teamId == teamID { return homeScore }
        return nil
    }

    var liveInningDescription: String? {
        guard abstractState == "Live", let liveInning else { return nil }
        let suffix: String
        switch liveInning % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch liveInning % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        let half = liveInningState?.capitalized ?? ""
        return "\(half) \(liveInning)\(suffix)".trimmingCharacters(in: .whitespaces)
    }

    var liveMatchupDescription: String? {
        guard abstractState == "Live" else { return nil }
        let parts = [livePitcherDescription, liveBatterDescription].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    var livePitcherDescription: String? {
        guard abstractState == "Live" else { return nil }
        return livePitcher.map { "(P) \(Self.shortPlayerName($0))" }
    }

    var liveBatterDescription: String? {
        guard abstractState == "Live" else { return nil }
        return liveBatter.map { "(AB) \(Self.shortPlayerName($0))" }
    }

    private static func shortPlayerName(_ fullName: String) -> String {
        let words = fullName.split(separator: " ")
        guard let last = words.last else { return fullName }
        if ["Jr.", "Sr.", "II", "III", "IV"].contains(String(last)), words.count > 1 {
            return "\(words[words.count - 2]) \(last)"
        }
        return String(last)
    }
    var calendarDateKey: String? {
        if let officialDate, officialDate.count >= 10 {
            return String(officialDate.prefix(10))
        }
        guard let gameDate else { return nil }
        guard let date = FeedDate.date(from: gameDate) else {
            return String(gameDate.prefix(10))
        }
        let formatter = BaseballDateFormat.day
        return formatter.string(from: date)
    }

    var startDate: Date? {
        guard !timeTBD, let gameDate else { return nil }
        return FeedDate.date(from: gameDate)
    }
}

nonisolated struct OctoberCall: Codable, Identifiable, Sendable {
    let seriesID: String
    let winnerTeamID: Int
    let seriesLength: Int
    let entryCategory: String
    let createdAt: Date
    let revisedAt: Date
    var cutoffAt: Date?
    var cutoffEvidence: String
    var outcome: String?
    var exactLength: Bool?

    var id: String { seriesID }
}

nonisolated struct OctoberCallBook: Codable, Sendable {
    var championTeamID: Int?
    var calls: [String: OctoberCall] = [:]
}

/// Fixed tournament slots retain their identity as TBD opponents become real teams.
struct PlayoffBracketSlot: Identifiable {
    let league: String
    let round: String
    let slot: String
    let column: Int
    let row: Int

    var id: String { "\(league.lowercased())-\(round)-\(slot.lowercased())" }
    func seriesID(season: Int) -> String { "\(season)-\(id)" }

    static let all: [Self] = [
        .init(league: "AL", round: "wild-card", slot: "B", column: 0, row: 0),
        .init(league: "AL", round: "wild-card", slot: "A", column: 0, row: 1),
        .init(league: "AL", round: "division-series", slot: "A", column: 1, row: 0),
        .init(league: "AL", round: "division-series", slot: "B", column: 1, row: 1),
        .init(league: "AL", round: "league-championship", slot: "main", column: 2, row: 0),
        .init(league: "MLB", round: "world-series", slot: "main", column: 3, row: 0),
        .init(league: "NL", round: "league-championship", slot: "main", column: 4, row: 0),
        .init(league: "NL", round: "division-series", slot: "A", column: 5, row: 0),
        .init(league: "NL", round: "division-series", slot: "B", column: 5, row: 1),
        .init(league: "NL", round: "wild-card", slot: "B", column: 6, row: 0),
        .init(league: "NL", round: "wild-card", slot: "A", column: 6, row: 1),
    ]

    var destinationID: String? {
        switch round {
        case "wild-card": "\(league.lowercased())-division-series-\(slot == "B" ? "a" : "b")"
        case "division-series": "\(league.lowercased())-league-championship-main"
        case "league-championship": "mlb-world-series-main"
        default: nil
        }
    }
}

import Foundation

struct Schedule: Decodable, Sendable {
    let generatedAt: String
    let regularSeasonEnd: String
    let source: String
    let team: String
    let games: [ScheduledGame]
}

struct ScheduledGame: Decodable, Identifiable, Sendable {
    let gamePk: Int
    let gameDate: String
    let status: String
    let venue: String
    let location: String
    let opponent: String
    let opponentRecord: String
    let favoriteTeamRecord: String
    let favoriteTeamPitcher: String
    let opponentPitcher: String
    let favoriteTeamPitcherRecord: String?
    let opponentPitcherRecord: String?
    let showProbables: Bool
    let seriesDescription: String
    let doubleheader: Bool
    let gameNumber: Int
    let broadcasts: [GameBroadcast]

    private enum CodingKeys: String, CodingKey {
        case gamePk, gameDate, status, venue, location, opponent, opponentRecord
        case favoriteTeamRecord, favoriteTeamPitcher, favoriteTeamPitcherRecord
        case redSoxRecord, redSoxPitcher, redSoxPitcherRecord
        case opponentPitcher, opponentPitcherRecord, showProbables
        case seriesDescription, doubleheader, gameNumber, broadcasts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gamePk = try values.decode(Int.self, forKey: .gamePk)
        gameDate = try values.decode(String.self, forKey: .gameDate)
        status = try values.decode(String.self, forKey: .status)
        venue = try values.decode(String.self, forKey: .venue)
        location = try values.decode(String.self, forKey: .location)
        opponent = try values.decode(String.self, forKey: .opponent)
        opponentRecord = try values.decode(String.self, forKey: .opponentRecord)
        favoriteTeamRecord = try values.decodeIfPresent(String.self, forKey: .favoriteTeamRecord)
            ?? values.decode(String.self, forKey: .redSoxRecord)
        favoriteTeamPitcher = try values.decodeIfPresent(String.self, forKey: .favoriteTeamPitcher)
            ?? values.decode(String.self, forKey: .redSoxPitcher)
        opponentPitcher = try values.decode(String.self, forKey: .opponentPitcher)
        favoriteTeamPitcherRecord = try values.decodeIfPresent(String.self, forKey: .favoriteTeamPitcherRecord)
            ?? values.decodeIfPresent(String.self, forKey: .redSoxPitcherRecord)
        opponentPitcherRecord = try values.decodeIfPresent(String.self, forKey: .opponentPitcherRecord)
        showProbables = try values.decode(Bool.self, forKey: .showProbables)
        seriesDescription = try values.decode(String.self, forKey: .seriesDescription)
        doubleheader = try values.decode(Bool.self, forKey: .doubleheader)
        gameNumber = try values.decode(Int.self, forKey: .gameNumber)
        broadcasts = try values.decodeIfPresent([GameBroadcast].self, forKey: .broadcasts) ?? []
    }

    var id: Int { gamePk }

    var date: Date? {
        ISO8601DateFormatter().date(from: gameDate)
    }

    var formattedDay: String {
        guard let date else { return gameDate }
        return date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
    }

    var formattedTime: String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var fullFormattedDay: String {
        guard let date else { return gameDate }
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }

    var locationWord: String {
        location == "home" ? "vs" : "@"
    }

    var probableMatchup: String? {
        guard showProbables,
              !favoriteTeamPitcher.isEmpty,
              !opponentPitcher.isEmpty else {
            return nil
        }
        return "\(favoriteTeamPitcher) vs \(opponentPitcher)"
    }

    var watchOptions: [String] {
        let relevant = broadcasts.filter { $0.isNational || $0.homeAway == location }
        let candidates = relevant.isEmpty ? broadcasts : relevant
        var options: [String] = []
        var seen = Set<String>()

        for broadcast in candidates {
            let name = broadcast.displayName
            if seen.insert(name.lowercased()).inserted {
                options.append(name)
            }
        }

        let streamsOnMLBTV = candidates.contains {
            !$0.isNational && $0.availableForStreaming && $0.availability != "exclusive"
        }
        if streamsOnMLBTV, seen.insert("mlb.tv (out of market)").inserted {
            options.append("MLB.TV (out of market)")
        }
        return options
    }

    var watchSummary: String {
        watchOptions.isEmpty ? "TV TBD" : watchOptions.joined(separator: " · ")
    }
}

struct GameBroadcast: Decodable, Sendable {
    let name: String
    let isNational: Bool
    let homeAway: String
    let availability: String
    let availableForStreaming: Bool

    var displayName: String {
        switch name {
        case "MLBN": return "MLB Network"
        case "MLBN (out-of-market only)": return "MLB Network (out of market)"
        default: return name
        }
    }
}

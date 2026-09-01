import Foundation

struct Schedule: Codable, Sendable {
    let generatedAt: String
    let regularSeasonEnd: String
    let source: String
    let team: String
    let games: [ScheduledGame]
}

struct ScheduledGame: Codable, Identifiable, Sendable {
    let gamePk: Int
    let gameDate: String
    let status: String
    let venue: String
    let location: String
    let opponent: String
    let opponentRecord: String
    let redSoxRecord: String
    let redSoxPitcher: String
    let opponentPitcher: String
    let showProbables: Bool
    let seriesDescription: String
    let doubleheader: Bool
    let gameNumber: Int

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
              !redSoxPitcher.isEmpty,
              !opponentPitcher.isEmpty else {
            return nil
        }
        return "\(redSoxPitcher) vs \(opponentPitcher)"
    }
}

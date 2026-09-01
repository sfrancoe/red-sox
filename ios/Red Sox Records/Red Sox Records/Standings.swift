import Foundation

struct StandingsFeed: Decodable {
    let generatedAt: String
    let source: String
    let season: Int
    let league: String
    let divisions: [StandingsDivision]
    let wildCard: [StandingsTeam]

    var updatedText: String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: generatedAt)
            ?? ISO8601DateFormatter().date(from: generatedAt)
        guard let date else { return generatedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct StandingsDivision: Decodable, Identifiable {
    let id: Int
    let name: String
    let teams: [StandingsTeam]
}

struct StandingsTeam: Decodable, Identifiable {
    let id: Int
    let name: String
    let shortName: String
    let abbreviation: String
    let rank: String
    let wins: Int
    let losses: Int
    let pct: String
    let gamesBack: String
    let wildCardGamesBack: String
    let lastTen: String
    let streak: String
    let isRedSox: Bool
}

enum StandingsMode: String, CaseIterable, Identifiable {
    case divisions
    case wildCard

    var id: Self { self }

    var title: String {
        switch self {
        case .divisions: "AL Divisions"
        case .wildCard: "Wild Card"
        }
    }
}

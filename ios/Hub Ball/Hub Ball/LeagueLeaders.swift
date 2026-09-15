import Foundation

enum LeaderboardScope: String, CaseIterable, Identifiable, Sendable {
    case team
    case league
    case mlb

    var id: String { rawValue }

    func title(for team: HubTeam) -> String {
        switch self {
        case .team: "Team"
        case .league: team.definition.league
        case .mlb: "MLB"
        }
    }

    func accessibilityTitle(for team: HubTeam) -> String {
        switch self {
        case .team: "Team leaders"
        case .league: team.definition.league == "NL" ? "National League leaders" : "American League leaders"
        case .mlb: "Major League Baseball leaders"
        }
    }

    func payloadKey(for team: HubTeam) -> String? {
        switch self {
        case .team: nil
        case .league: team.definition.league.lowercased()
        case .mlb: "mlb"
        }
    }

    func heading(for team: HubTeam) -> String {
        switch self {
        case .team: ""
        case .league: team.definition.league == "NL" ? "National League" : "American League"
        case .mlb: "MLB"
        }
    }
}

struct LeagueLeadersPayload: Codable, Sendable {
    let schemaVersion: Int
    let season: Int
    let generatedAt: String
    let sources: [String: String]
    let scopes: [String: [String: ComparisonCategory]]
}

struct ComparisonCategory: Codable, Sendable {
    let availability: String
    let eligibility: String
    let message: String?
    let populationCount: Int
    let entries: [ComparisonLeader]

    var isAvailable: Bool { availability == "available" }
}

struct ComparisonLeader: Codable, Identifiable, Sendable {
    let playerID: Int
    let provider: String
    let name: String
    let value: Double
    let displayValue: String
    let teamID: Int?
    let teamAbbreviation: String?
    let rank: Int
    let tied: Bool

    // `convertFromSnakeCase` turns `player_id` into `playerId`, not the Swift
    // initialism spelling `playerID`. Keep the public Swift names and decode
    // these two stable API keys explicitly.
    private enum CodingKeys: String, CodingKey {
        case playerID = "playerId"
        case provider, name, value
        case displayValue
        case teamID = "teamId"
        case teamAbbreviation
        case rank, tied
    }

    var id: String { "\(provider)-\(playerID)" }
    var rankText: String { tied ? "T-\(rank)" : "\(rank)" }
}

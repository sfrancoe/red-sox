import Foundation

@main
struct LeagueLeadersDecodeTest {
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "data/leaderboards/2026.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(LeagueLeadersPayload.self, from: data)
        guard let leader = payload.scopes["al"]?["hr"]?.entries.first,
              leader.playerID > 0, leader.teamID != nil else {
            fatalError("Expected an AL home-run leader with stable IDs")
        }
        print("league leaderboard Swift decoding passed: \(leader.name) / \(leader.playerID)")
    }
}

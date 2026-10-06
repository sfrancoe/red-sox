import Foundation
import Testing
@testable import Hub_Ball

struct LeagueLeadersDecodeTest {
    @Test @MainActor static func scenarios() throws {
        let path = testFixture("leaders").path
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(LeagueLeadersPayload.self, from: data)
        guard let leader = payload.scopes["al"]?["hr"]?.entries.first,
              leader.playerID > 0, leader.teamID != nil else {
            Issue.record("Expected an AL home-run leader with stable IDs"); return
        }
        print("league leaderboard Swift decoding passed: \(leader.name) / \(leader.playerID)")
    }
}

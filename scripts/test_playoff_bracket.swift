import Foundation

@main
struct PlayoffBracketTest {
    static func main() throws {
        checkLatestGameScores()
        let slots = PlayoffBracketSlot.all
        precondition(slots.count == 11)
        precondition(Set(slots.map(\.id)).count == 11)
        for path in CommandLine.arguments.dropFirst() {
            let payload = try JSONDecoder().decode(PostseasonPayload.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            precondition(payload.series.count == 11, "Fixture must cover the entire tournament")
            for series in payload.series {
                guard let slot = slots.first(where: { $0.seriesID(season: payload.season) == series.id }) else {
                    fatalError("Real provider series missing from bracket: \(series.id)")
                }
                let expected = slot.destinationID.map { "\(payload.season)-\($0)" }
                precondition(series.nextSlots?.first == expected, "Advancement line must match provider normalization: \(series.id)")
                var current = slot
                var visited = Set<String>()
                while let next = current.destinationID {
                    precondition(visited.insert(current.id).inserted, "No cycles")
                    current = slots.first { $0.id == next }!
                }
                precondition(current.round == "world-series", "Every path must reach World Series")
            }
        }
        print("All 11 bracket slots and advancement paths agree with recorded postseasons")
    }

    static func checkLatestGameScores() {
        let boston = PostseasonClub(teamId: 111, name: "Red Sox", abbreviation: "BOS", slot: nil, resolved: true)
        let newYork = PostseasonClub(teamId: 147, name: "Yankees", abbreviation: "NYY", slot: nil, resolved: true)
        func series(_ bostonWins: Int, _ newYorkWins: Int, winner: Int? = nil, state: String = "scheduled") -> PostseasonSeries {
            PostseasonSeries(id: "test-series", round: "wild-card", league: "AL", bracketSlot: "A",
                             participants: [boston, newYork], unresolvedSlots: [], requiredWins: 2,
                             gameIds: [], completedGameCount: bostonWins + newYorkWins,
                             wins: ["111": bostonWins, "147": newYorkWins], winnerTeamId: winner,
                             state: state, nextSlots: nil)
        }
        func game(_ number: Int, state: String = "Final", winner: Int? = 147,
                  away: PostseasonClub = boston, home: PostseasonClub = newYork,
                  awayScore: Int? = 0, homeScore: Int? = 9, seriesID: String = "test-series") -> PostseasonGame {
            PostseasonGame(gamePk: number, seriesId: seriesID, gameNumber: number, gameType: "F",
                           gameDate: nil, officialDate: nil, timeTBD: false, status: state,
                           abstractState: state, broadcasts: [], conditional: false,
                           away: away, home: home, awayScore: awayScore, homeScore: homeScore,
                           winnerTeamId: winner, liveInning: nil, liveInningState: nil,
                           liveOuts: nil, livePitcher: nil, liveBatter: nil)
        }
        func payload(_ games: [PostseasonGame]) -> PostseasonPayload {
            PostseasonPayload(schemaVersion: 1, season: 2026, phase: "active", checkedAt: "",
                              providerUpdatedAt: nil, source: "test", sourceURL: "",
                              teamsAndSlots: [], series: [series(0, 1)], games: games)
        }

        let first = game(1)
        precondition(first.score(for: 111) == 0, "A shutout must display zero, not a missing score")
        precondition(first.score(for: 147) == 9)
        precondition(first.score(for: 999) == nil)
        precondition(series(0, 1).bracketSeriesStatus == "NYY lead 1-0")
        precondition(series(1, 0).bracketSeriesStatus == "BOS lead 1-0")
        precondition(series(1, 1).bracketSeriesStatus == "Series tied 1-1")
        precondition(series(0, 2, winner: 147, state: "complete").bracketSeriesStatus == "NYY win 2-0")
        precondition(series(0, 0).bracketSeriesStatus == nil)
        precondition(series(0, 1, state: "unknown").bracketSeriesStatus == nil)

        let second = game(2, winner: 111, away: newYork, home: boston, awayScore: 2, homeScore: 5)
        let games = [game(3, state: "Preview", winner: nil), second,
                     game(4, state: "Live", winner: nil), first,
                     game(5, winner: nil), game(6, seriesID: "other-series")]
        let latest = payload(games).latestCompletedGame(for: "test-series")
        precondition(latest?.gamePk == 2, "Ignore input order, future/live/cancelled games, and other series")
        precondition(latest?.score(for: 111) == 5, "Match scores by team ID when home and away switch")
        precondition(latest?.score(for: 147) == 2)
        precondition(payload([game(1, state: "Preview", winner: nil)]).latestCompletedGame(for: "test-series") == nil)
        precondition(payload(games).liveGame(for: "test-series")?.gamePk == 4)
        let liveGame = PostseasonGame(gamePk: 7, seriesId: "test-series", gameNumber: 2,
                                      gameType: "F", gameDate: nil, officialDate: nil,
                                      timeTBD: false, status: "In Progress", abstractState: "Live",
                                      broadcasts: [], conditional: false, away: boston, home: newYork,
                                      awayScore: 3, homeScore: 2, winnerTeamId: nil,
                                      liveInning: 9, liveInningState: "Top", liveOuts: 1,
                                      livePitcher: "Raisel Iglesias", liveBatter: "J.T. Realmuto")
        precondition(liveGame.liveInningDescription == "Top 9th")
        precondition(liveGame.liveMatchupDescription == "(P) Iglesias  (AB) Realmuto")
        precondition(game(2, awayScore: nil).score(for: 111) == nil, "Missing scores must not become zero")
        print("Latest-game bracket scores and series status passed")
    }
}

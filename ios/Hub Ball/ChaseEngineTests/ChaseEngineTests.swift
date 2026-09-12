import Foundation

@main
enum ChaseEngineTests {
    static func main() {
        assertTotal(ChaseData.bonds, equals: 762)
        assertTotal(ChaseData.aaron, equals: 755)
        assertTotal(ChaseData.ruth, equals: 714)
        assertTotal(ChaseData.mcGwire, equals: 583)

        expect(
            abs(ChaseEngine.hr(for: ChaseData.ruth, at: 4_326, axis: .atBats) - 347) < 1,
            "Ruth should have approximately 347 HR through 4,326 at-bats"
        )
        expect(
            ChaseEngine.hr(for: ChaseData.judge, at: 34, axis: .age) == 385,
            "Judge should have 385 HR through age 34"
        )
        expect(
            ChaseEngine.hr(for: ChaseData.judge, at: 10, axis: .age) == 0,
            "Values below the first season should return zero"
        )

        let gapPlayer = PlayerHRSeries(
            id: "gap",
            name: "Gap",
            seasons: [
                HRSeason(year: 2000, age: 20, hr: 10, ab: 100),
                HRSeason(year: 2002, age: 22, hr: 10, ab: 100)
            ],
            isSubject: false,
            careerHR: 20
        )
        expect(
            ChaseEngine.hr(for: gapPlayer, at: 21, axis: .age) == 15,
            "Age interpolation should bridge a missing season continuously"
        )
        expect(
            ChaseEngine.hr(for: gapPlayer, at: 150, axis: .atBats) == 15,
            "At-bat interpolation should contain no missing-season gap"
        )

        let ranking = ChaseEngine.allTimeRank(700)
        expect(ranking.rank == 5, "700 home runs should rank fifth")
        expect(
            ranking.passing == "Rodriguez",
            "700 passes Rodriguez; the supplied spec's Pujols expectation is factually reversed"
        )

        print("Home Run Chase engine tests passed")
    }

    private static func assertTotal(_ player: PlayerHRSeries, equals expected: Int) {
        let total = Int(ChaseEngine.cumulative(player).last?.hr ?? -1)
        expect(total == expected, "\(player.name) should finish with \(expected) HR, got \(total)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

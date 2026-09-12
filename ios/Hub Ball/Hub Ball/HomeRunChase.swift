import Foundation

enum ChaseAxis: Sendable {
    case age
    case atBats
}

struct HRSeason: Equatable, Sendable {
    let year: Int
    let age: Int
    let hr: Int
    let ab: Int
}

struct PlayerHRSeries: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var seasons: [HRSeason]
    let isSubject: Bool
    let careerHR: Int?
}

struct CumulativePoint: Equatable, Sendable {
    let age: Double
    let ab: Double
    let hr: Double
}

struct ChaseMilestone: Identifiable, Sendable {
    let label: String
    let total: Int
    let age: Int
    let year: Int

    var id: String { label }
}

struct ChaseConfig: Sendable {
    var subject: PlayerHRSeries
    let comparisons: [PlayerHRSeries]
    let leaderboard: [(name: String, total: Int)]
    let projectionBaseline: (age: Int, hr: Int)
    let contractEndAge: Int?

    var players: [PlayerHRSeries] { comparisons + [subject] }
}

enum ChaseEngine {
    static func cumulative(_ player: PlayerHRSeries) -> [CumulativePoint] {
        let seasons = player.seasons.sorted { $0.year < $1.year }
        guard let first = seasons.first else { return [] }

        var totalAB = 0
        var totalHR = 0
        var points = [CumulativePoint(age: Double(first.age - 1), ab: 0, hr: 0)]
        for season in seasons {
            totalAB += season.ab
            totalHR += season.hr
            points.append(CumulativePoint(
                age: Double(season.age),
                ab: Double(totalAB),
                hr: Double(totalHR)
            ))
        }
        return points
    }

    static func hr(for player: PlayerHRSeries, at x: Double, axis: ChaseAxis) -> Double {
        let points = cumulative(player)
        guard let first = points.first, let last = points.last else { return 0 }
        let value: (CumulativePoint) -> Double = axis == .age ? { $0.age } : { $0.ab }

        guard x >= value(first) else { return 0 }
        guard x < value(last) else { return last.hr }

        for pair in zip(points, points.dropFirst()) {
            let lower = value(pair.0)
            let upper = value(pair.1)
            guard x <= upper else { continue }
            guard upper > lower else { return pair.1.hr }
            let fraction = (x - lower) / (upper - lower)
            return pair.0.hr + (pair.1.hr - pair.0.hr) * fraction
        }
        return last.hr
    }

    static func careerRate(_ player: PlayerHRSeries) -> (abPerHR: Double, hrPerSeason: Double) {
        let totalAB = player.seasons.reduce(0) { $0 + $1.ab }
        let totalHR = player.seasons.reduce(0) { $0 + $1.hr }
        guard totalHR > 0 else { return (.infinity, 0) }
        let atBatsPerHomeRun = Double(totalAB) / Double(totalHR)
        return (atBatsPerHomeRun, 540 / atBatsPerHomeRun)
    }

    static func project(
        from baseline: (age: Int, hr: Int),
        rate: Double,
        throughAge: Int
    ) -> [CumulativePoint] {
        guard throughAge >= baseline.age else { return [] }
        return (baseline.age...throughAge).map { age in
            CumulativePoint(
                age: Double(age),
                ab: 0,
                hr: Double(baseline.hr) + Double(age - baseline.age) * rate
            )
        }
    }

    static func allTimeRank(
        _ total: Double,
        leaderboard: [(name: String, total: Int)] = ChaseData.leaderboard
    ) -> (rank: Int, passing: String?) {
        let rank = leaderboard.filter { Double($0.total) > total }.count + 1
        let passing = leaderboard.first { Double($0.total) < total }?.name
        return (rank, passing)
    }

    static func milestones(for config: ChaseConfig) -> [ChaseMilestone] {
        let rate = careerRate(config.subject).hrPerSeason
        let targets = [
            ("REACHES 500", 500), ("REACHES 600", 600), ("REACHES 700", 700),
            ("PASSES RUTH", 715), ("PASSES AARON", 756), ("PASSES BONDS", 763)
        ]
        return targets.map { label, total in
            let seasons = max(0, Int(ceil((Double(total - config.projectionBaseline.hr)) / rate)))
            return ChaseMilestone(
                label: label,
                total: total,
                age: config.projectionBaseline.age + seasons,
                year: ChaseData.projectionYear + seasons
            )
        }
    }
}

enum ChaseData {
    static let judgePlayerID = 592450
    static let projectionYear = 2026
    static let judge300thHomeRunAtBat = 3_431
    static let ruth300thHomeRunAtBat = 3_830

    static let leaderboard: [(name: String, total: Int)] = [
        ("Bonds", 762), ("Aaron", 755), ("Ruth", 714), ("Pujols", 703),
        ("Rodriguez", 696), ("Mays", 660), ("Griffey Jr.", 630), ("Thome", 612),
        ("Sosa", 609), ("F. Robinson", 586), ("McGwire", 583), ("Killebrew", 573),
        ("Palmeiro", 569), ("R. Jackson", 563), ("M. Ramírez", 555), ("Schmidt", 548),
        ("Ortiz", 541), ("Mantle", 536), ("Foxx", 534), ("F. Thomas", 521),
        ("McCovey", 521), ("T. Williams", 521), ("Banks", 512), ("Mathews", 512),
        ("Ott", 511), ("Cabrera", 511), ("Sheffield", 509), ("Murray", 504)
    ]

    static let judge = PlayerHRSeries(
        id: "judge", name: "Judge", seasons: seasons(
            firstYear: 2016, firstAge: 24,
            homeRuns: [4, 52, 27, 27, 9, 39, 62, 37, 58, 53, 17],
            atBats: [84, 542, 413, 378, 101, 550, 570, 367, 559, 541, 224]
        ), isSubject: true, careerHR: nil
    )

    static let bonds = PlayerHRSeries(
        id: "bonds", name: "Bonds", seasons: seasons(
            firstYear: 1986, firstAge: 21,
            homeRuns: [16, 25, 24, 19, 33, 25, 34, 46, 37, 33, 42, 40, 37, 34, 49, 73, 46, 45, 45, 5, 26, 28],
            atBats: [413, 551, 538, 580, 519, 510, 473, 539, 391, 506, 517, 532, 552, 355, 480, 476, 403, 390, 373, 42, 367, 340]
        ), isSubject: false, careerHR: 762
    )

    static let aaron = PlayerHRSeries(
        id: "aaron", name: "Aaron", seasons: seasons(
            firstYear: 1954, firstAge: 20,
            homeRuns: [13, 27, 26, 44, 30, 39, 40, 34, 45, 44, 24, 32, 44, 39, 29, 44, 38, 47, 34, 40, 20, 12, 10],
            atBats: [468, 602, 609, 615, 601, 629, 590, 603, 592, 631, 570, 570, 603, 600, 606, 547, 516, 495, 449, 392, 340, 465, 271]
        ), isSubject: false, careerHR: 755
    )

    static let ruth = PlayerHRSeries(
        id: "ruth", name: "Ruth", seasons: seasons(
            firstYear: 1914, firstAge: 19,
            homeRuns: [0, 4, 3, 2, 11, 29, 54, 59, 35, 41, 46, 25, 47, 60, 54, 46, 49, 46, 41, 34, 22, 6],
            atBats: [10, 92, 136, 123, 317, 432, 458, 540, 406, 522, 529, 359, 495, 540, 536, 499, 518, 534, 457, 459, 365, 72]
        ), isSubject: false, careerHR: 714
    )

    static let mcGwire = PlayerHRSeries(
        id: "mcgwire", name: "McGwire", seasons: seasons(
            firstYear: 1986, firstAge: 22,
            homeRuns: [3, 49, 32, 33, 39, 22, 42, 9, 9, 39, 52, 58, 70, 65, 32, 29],
            atBats: [53, 557, 550, 490, 523, 483, 467, 84, 135, 317, 423, 540, 509, 521, 236, 299]
        ), isSubject: false, careerHR: 583
    )

    static func config(subject: PlayerHRSeries = judge, projectionHR: Int = 388) -> ChaseConfig {
        ChaseConfig(
            subject: subject,
            comparisons: [bonds, aaron, ruth, mcGwire],
            leaderboard: leaderboard,
            projectionBaseline: (age: subject.seasons.last?.age ?? 34, hr: projectionHR),
            contractEndAge: 39
        )
    }

    private static func seasons(
        firstYear: Int,
        firstAge: Int,
        homeRuns: [Int],
        atBats: [Int]
    ) -> [HRSeason] {
        precondition(homeRuns.count == atBats.count)
        return homeRuns.indices.map { index in
            HRSeason(
                year: firstYear + index,
                age: firstAge + index,
                hr: homeRuns[index],
                ab: atBats[index]
            )
        }
    }
}

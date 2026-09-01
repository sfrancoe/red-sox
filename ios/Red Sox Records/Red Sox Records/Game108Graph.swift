import Foundation

struct GraphSeasonData: Codable, Sendable {
    let checkpointRecord: String
    let diff: [Int]
    let endGame: Int
    let inProgress: Bool
    let record: String
    let seq: String
}

struct GraphSeries: Identifiable, Sendable {
    let year: Int
    let record: String
    let endGame: Int
    let inProgress: Bool
    let results: [Character]
    let displayDiff: [Double]

    var id: Int { year }

    init(year: Int, data: GraphSeasonData) {
        self.year = year
        record = data.record
        endGame = data.endGame
        inProgress = data.inProgress
        results = Array(data.seq)

        let raw = [0.0] + data.diff.map(Double.init)
        displayDiff = raw.indices.map { game in
            if game == 108, raw.count > 108 {
                return 6
            }

            let radius = min(3, game, raw.count - 1 - game)
            let values = raw[(game - radius)...(game + radius)]
            return values.reduce(0, +) / Double(values.count)
        }
    }

    func record(through game: Int) -> String {
        let played = min(max(game, 0), results.count)
        let wins = results.prefix(played).filter { $0 == "W" }.count
        return "\(wins)–\(played - wins)"
    }
}

struct GraphBeat: Sendable {
    let game: Int
    let text: String
}

struct GraphStory: Sendable {
    let year: Int
    let label: String
    let colorHex: String
    let beats: [GraphBeat]
}

enum Game108Story {
    static let stories: [GraphStory] = [
        GraphStory(year: 2023, label: "The Grind", colorHex: "087EA4", beats: [
            GraphBeat(game: 0, text: "The steady climb begins."),
            GraphBeat(game: 13, text: "Two weeks in — three games under. A soft open."),
            GraphBeat(game: 35, text: "An eight-game winning streak lifts them to +7."),
            GraphBeat(game: 103, text: "Cresting at +9 — the season high."),
            GraphBeat(game: 108, text: "Checkpoint: 57–51. No drama — just a grind."),
            GraphBeat(game: 159, text: "The floor gives way: seven under, the season low."),
            GraphBeat(game: 162, text: "Fade to 78–84. Last place in the AL East.")
        ]),
        GraphStory(year: 2024, label: "The Flatline", colorHex: "9A6700", beats: [
            GraphBeat(game: 0, text: "Life on the .500 tightrope."),
            GraphBeat(game: 46, text: "The season low is just two games under."),
            GraphBeat(game: 96, text: "A late surge to +10 — the high-water mark."),
            GraphBeat(game: 108, text: "Checkpoint: 57–51. The exact same number, again."),
            GraphBeat(game: 140, text: "A five-game slide erases the cushion."),
            GraphBeat(game: 162, text: "Dead even: 81–81.")
        ]),
        GraphStory(year: 2025, label: "The Bounce-Back", colorHex: "7753C7", beats: [
            GraphBeat(game: 0, text: "The best of the four — it just hid it early."),
            GraphBeat(game: 63, text: "Season low: five games under, and sinking."),
            GraphBeat(game: 83, text: "A six-game skid — the worst stretch of the year."),
            GraphBeat(game: 98, text: "The answer: ten wins in a row."),
            GraphBeat(game: 108, text: "Checkpoint: 57–51 too."),
            GraphBeat(game: 140, text: "+16 — the season high, and clear of the pack."),
            GraphBeat(game: 162, text: "89–73. A Wild Card berth.")
        ]),
        GraphStory(year: 2026, label: "The Rollercoaster", colorHex: "D52C3A", beats: [
            GraphBeat(game: 0, text: "Buckle up."),
            GraphBeat(game: 6, text: "Five straight losses out of the gate."),
            GraphBeat(game: 72, text: "Rock bottom — fourteen games under .500."),
            GraphBeat(game: 95, text: "Then the turn: ten wins in a row."),
            GraphBeat(game: 108, text: "Checkpoint: 57–51 — the same number, a fourth straight year.")
        ])
    ]
}

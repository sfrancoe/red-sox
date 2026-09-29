import Foundation

let data = MLB300HitterData.seasons
precondition(data.count == 51)
precondition(data.map(\.year) == Array(1976...2026))
precondition(data.allSatisfy { $0.count >= 0 })
precondition(MLB300HitterData.peak == .init(year: 1999, count: 55))
precondition(MLB300HitterData.finish == .init(year: 2026, count: 7))
precondition(MLB300HitterData.decline == 87)
precondition(data.filter { $0.count == data.map(\.count).min() }.map(\.year) == [2024, 2025, 2026])
precondition(data.filter(\.isProvisional).isEmpty)
precondition(data.first { $0.year == 2025 } == .init(year: 2025, count: 7))
precondition(MLB300HitterData.finish.label == "2026")
// Completion is time-based, including skipped frames and replay's zero point.
precondition(MLB300HitterData.progress(elapsed: -1) == 0)
precondition(MLB300HitterData.progress(elapsed: 0) == 0)
precondition(MLB300HitterData.progress(elapsed: 2.5) == 0.5)
precondition(MLB300HitterData.progress(elapsed: 4.999) < 1)
precondition(MLB300HitterData.progress(elapsed: 5) == 1)
precondition(MLB300HitterData.progress(elapsed: 6) == 1)
print("PASS: 51 final seasons, endpoints, peak, decline, 5-second timing")

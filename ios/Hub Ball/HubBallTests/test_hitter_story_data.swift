import Foundation
import Testing
@testable import Hub_Ball

struct HitterStoryTests {
    @Test @MainActor static func scenarios() {
let data = MLB300HitterData.seasons
#expect(data.count == 51)
#expect(data.map(\.year) == Array(1976...2026))
#expect(data.allSatisfy { $0.count >= 0 })
#expect(MLB300HitterData.peak == .init(year: 1999, count: 55))
#expect(MLB300HitterData.finish == .init(year: 2026, count: 7))
#expect(MLB300HitterData.decline == 87)
#expect(data.filter { $0.count == data.map(\.count).min() }.map(\.year) == [2024, 2025, 2026])
#expect(data.filter(\.isProvisional).isEmpty)
#expect(data.first { $0.year == 2025 } == .init(year: 2025, count: 7))
#expect(MLB300HitterData.finish.label == "2026")
// Completion is time-based, including skipped frames and replay's zero point.
#expect(MLB300HitterData.progress(elapsed: -1) == 0)
#expect(MLB300HitterData.progress(elapsed: 0) == 0)
#expect(MLB300HitterData.progress(elapsed: 2.5) == 0.5)
#expect(MLB300HitterData.progress(elapsed: 4.999) < 1)
#expect(MLB300HitterData.progress(elapsed: 5) == 1)
#expect(MLB300HitterData.progress(elapsed: 6) == 1)
print("PASS: 51 final seasons, endpoints, peak, decline, 5-second timing")

    }
}

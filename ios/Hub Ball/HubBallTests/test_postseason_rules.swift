import Foundation
import Testing
@testable import Hub_Ball

enum PostseasonRulesTest {
    @Test @MainActor static func scenarios() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let freshCheck = now.addingTimeInterval(-20)
        let firstPitch = now.addingTimeInterval(3_600)

let preSeries = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: firstPitch,
    hasStarted: false,
    now: now
)
#expect(preSeries.category == "pre-series")
#expect(preSeries.cutoffAt == firstPitch)

let unknownTime = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: nil,
    hasStarted: false,
    now: now
)
#expect(unknownTime.category == "from-here")
#expect(unknownTime.cutoffAt == nil)

let stale = PostseasonRules.callTiming(
    checkedAt: now.addingTimeInterval(-120),
    scheduledStart: firstPitch,
    hasStarted: false,
    now: now
)
#expect(stale.category == "from-here")
#expect(stale.cutoffAt == nil)

let observedStarted = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: firstPitch,
    hasStarted: true,
    now: now
)
#expect(observedStarted.category == "from-here")
#expect(observedStarted.cutoffAt == freshCheck)

#expect(PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: 20))
#expect(!PostseasonRules.canEdit(existingCall: true, hasStarted: true))
#expect(PostseasonRules.canEdit(existingCall: false, hasStarted: true))
#expect(!PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: 120))
#expect(!PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: -2))

        print("postseason local-pick cutoff rules passed")
    }
}

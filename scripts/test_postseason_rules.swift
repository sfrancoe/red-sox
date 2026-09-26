import Foundation

@main
enum PostseasonRulesTest {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let freshCheck = now.addingTimeInterval(-20)
        let firstPitch = now.addingTimeInterval(3_600)

let preSeries = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: firstPitch,
    hasStarted: false,
    now: now
)
precondition(preSeries.category == "pre-series")
precondition(preSeries.cutoffAt == firstPitch)

let unknownTime = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: nil,
    hasStarted: false,
    now: now
)
precondition(unknownTime.category == "from-here")
precondition(unknownTime.cutoffAt == nil)

let stale = PostseasonRules.callTiming(
    checkedAt: now.addingTimeInterval(-120),
    scheduledStart: firstPitch,
    hasStarted: false,
    now: now
)
precondition(stale.category == "from-here")
precondition(stale.cutoffAt == nil)

let observedStarted = PostseasonRules.callTiming(
    checkedAt: freshCheck,
    scheduledStart: firstPitch,
    hasStarted: true,
    now: now
)
precondition(observedStarted.category == "from-here")
precondition(observedStarted.cutoffAt == freshCheck)

precondition(PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: 20))
precondition(!PostseasonRules.canEdit(existingCall: true, hasStarted: true))
precondition(PostseasonRules.canEdit(existingCall: false, hasStarted: true))
precondition(!PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: 120))
precondition(!PostseasonRules.canEdit(existingCall: true, hasStarted: false, snapshotAge: -2))

        print("postseason local-pick cutoff rules passed")
    }
}

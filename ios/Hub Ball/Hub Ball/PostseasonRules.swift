import Foundation

struct OctoberCallTiming: Equatable {
    let category: String
    let cutoffAt: Date?
    let evidence: String
}

enum PostseasonRules {
    static func callTiming(
        checkedAt: Date?,
        scheduledStart: Date?,
        hasStarted: Bool,
        now: Date = Date(),
        maximumFreshness: TimeInterval = 90
    ) -> OctoberCallTiming {
        let age = checkedAt.map { now.timeIntervalSince($0) } ?? .infinity
        let fresh = age >= 0 && age <= maximumFreshness
        let cutoff = [fresh ? scheduledStart : nil, hasStarted ? checkedAt : nil]
            .compactMap { $0 }
            .min()
        if fresh, let scheduledStart, scheduledStart > now, !hasStarted {
            return OctoberCallTiming(
                category: "pre-series",
                cutoffAt: scheduledStart,
                evidence: "Fresh schedule check; earliest known scheduled first game."
            )
        }
        if hasStarted {
            return OctoberCallTiming(
                category: "from-here",
                cutoffAt: cutoff,
                evidence: "First game observed live or final; the time is the source check."
            )
        }
        return OctoberCallTiming(
            category: "from-here",
            cutoffAt: cutoff,
            evidence: "Start time or fresh schedule evidence unavailable."
        )
    }

    static func canEdit(
        existingCall: Bool,
        hasStarted: Bool,
        snapshotAge: TimeInterval? = nil,
        maximumFreshness: TimeInterval = 90
    ) -> Bool {
        guard existingCall else { return true }
        guard !hasStarted, let snapshotAge else { return false }
        return snapshotAge >= 0 && snapshotAge <= maximumFreshness
    }
}

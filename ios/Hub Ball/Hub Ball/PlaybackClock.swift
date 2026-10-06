import SwiftUI

/// SwiftUI schedules these ticks with display refreshes and stops when paused.
struct PlaybackClock: View {
    let active: Bool
    let tick: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            Color.clear
                .onChange(of: context.date) { _, _ in
                    if active { tick(ProcessInfo.processInfo.systemUptime) }
                }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

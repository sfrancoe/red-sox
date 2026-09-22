//
//  HubBallApp.swift
//  Hub Ball
//
//  Created by Scott Francoeur on 8/31/26.
//

import SwiftUI

@main
struct HubBallApp: App {
    init() {
        #if DEBUG
        // Reset once, rather than pinning the preference through a launch-argument
        // override, so UI tests can exercise the real completion write.
        if ProcessInfo.processInfo.arguments.contains("-reset-team-onboarding") {
            UserDefaults.standard.set(false, forKey: HubPreferences.completedTeamOnboardingKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  HubBallApp.swift
//  Hub Ball
//
//  Created by Scott Francoeur on 8/31/26.
//

import SwiftUI

@main
struct HubBallApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel?
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
            Group {
                if let model { ContentView().environment(model) }
                else { ProgressView().task { model = AppModel() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model?.scheduler.setBackground(true) }
                if phase == .active { model?.scheduler.setBackground(false) }
            }
        }
    }
}

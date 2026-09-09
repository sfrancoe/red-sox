import SwiftUI

struct TeamSettingsView: View {
    @Binding var selectedTeamID: String
    let onSelect: (HubTeam) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(HubTeam.availableTeams) { team in
                                teamButton(team)
                                if team.id != HubTeam.availableTeams.last?.id {
                                    Divider().overlay(AppColor.border)
                                }
                            }
                        }
                        .padding(16)

                        Text(versionLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColor.ink.opacity(0.62))
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                            .accessibilityLabel("Hub Ball version \(versionLabel)")
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Hub Ball \(version) (\(build))"
    }

    private func teamButton(_ team: HubTeam) -> some View {
        Button {
            selectedTeamID = team.id
            onSelect(team)
        } label: {
            Text(team.fullName)
                .font(.headline)
                .foregroundStyle(AppColor.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(selectedTeamID == team.id ? AppColor.paleBlue : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTeamID == team.id ? .isSelected : [])
    }
}

struct TeamOnboardingView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTeamID: String
    let onContinue: () -> Void

    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            ScrollView {
                VStack(spacing: usesAccessibilityLayout ? 14 : 24) {
                    Spacer(minLength: usesAccessibilityLayout ? 8 : 34)

                    Image(systemName: "baseball.fill")
                        .font(.system(size: usesAccessibilityLayout ? 42 : 58, weight: .black))
                        .foregroundStyle(.black)

                    VStack(spacing: usesAccessibilityLayout ? 5 : 8) {
                        Text("WELCOME TO HUB BALL")
                            .font(.system(size: usesAccessibilityLayout ? 26 : 30, weight: .black))
                            .multilineTextAlignment(.center)
                        Text("Choose the team you want to follow first. You can switch anytime in Settings.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.black.opacity(0.86))
                    }
                    .foregroundStyle(.black)

                    VStack(spacing: usesAccessibilityLayout ? 8 : 12) {
                        ForEach(HubTeam.availableTeams) { team in
                            Button {
                                selectedTeamID = team.id
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "baseball.fill")
                                        .font(.title2)
                                        .foregroundStyle(AppColor.red)
                                    Text(team.pickerTitle)
                                        .font(.headline)
                                        .foregroundStyle(AppColor.navy)
                                    Spacer()
                                    Image(systemName: selectedTeamID == team.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedTeamID == team.id ? AppColor.green : AppColor.border)
                                }
                                .padding(usesAccessibilityLayout ? 12 : 17)
                                .background(AppColor.paper)
                                .clipShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: onContinue) {
                        Text("FOLLOW THIS TEAM")
                            .font(.headline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, usesAccessibilityLayout ? 12 : 15)
                            .background(AppColor.accentSoft)
                            .clipShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text("All 30 MLB teams are available.")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, usesAccessibilityLayout ? 12 : 28)
            }
        }
        .interactiveDismissDisabled()
        // Keep every first-run choice reachable on short phones while still
        // honoring the first two accessibility text sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

#Preview("Settings") {
    TeamSettingsView(selectedTeamID: .constant(HubTeam.boston.id)) { _ in }
}

#Preview("Onboarding") {
    TeamOnboardingView(selectedTeamID: .constant(HubTeam.newYork.id)) {}
}

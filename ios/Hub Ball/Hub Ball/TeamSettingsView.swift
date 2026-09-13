import SwiftUI

private enum TeamFavoritesStorage {
    static let key = "hubFavoriteTeamIDs"
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case teams
    case pageOrder

    var id: Self { self }

    var title: String {
        switch self {
        case .teams: "Teams"
        case .pageOrder: "Page Order"
        }
    }
}

struct TeamSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TeamFavoritesStorage.key) private var favoriteTeamIDs = ""
    @AppStorage(HubPreferences.pageOrderKey) private var storedPageOrder = MainTab.defaultOrderStorageValue
    @State private var selectedSettingsTab = SettingsTab.teams
    @State private var pageOrderHapticTick = UUID()
    @Binding var selectedTeamID: String
    let onSelect: (HubTeam) -> Void

    private var favoriteIDs: Set<String> {
        Set(favoriteTeamIDs.split(separator: ",").map(String.init))
    }

    private var favoriteTeams: [HubTeam] {
        favoriteTeamIDs
            .split(separator: ",")
            .compactMap { HubTeam(rawValue: String($0)) }
            .filter { $0.features.nativePicker }
    }

    private var orderedPages: [MainTab] {
        MainTab.ordered(from: storedPageOrder)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    settingsTabBar

                    switch selectedSettingsTab {
                    case .teams:
                        teamsTab
                    case .pageOrder:
                        pageOrderTab
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColor.nightRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedSettingsTab = tab
                } label: {
                    Text(tab.title)
                        .font(.headline.weight(selectedSettingsTab == tab ? .bold : .semibold))
                        .foregroundStyle(selectedSettingsTab == tab ? AppColor.ink : AppColor.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            if selectedSettingsTab == tab {
                                Rectangle()
                                    .fill(AppColor.accent)
                                    .frame(height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSettingsTab == tab ? .isSelected : [])
            }
        }
        .background(AppColor.paper)
        .overlay(alignment: .bottom) {
            Divider().overlay(AppColor.separator)
        }
    }

    private var teamsTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !favoriteTeams.isEmpty {
                        teamSection(title: "Favorites", teams: favoriteTeams, allowsReordering: true)
                            .padding(.bottom, 20)
                    }

                    teamSection(title: "All Teams", teams: HubTeam.availableTeams)
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

    private var pageOrderTab: some View {
        List {
            pageOrderSection
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .sensoryFeedback(.selection, trigger: pageOrderHapticTick)
    }

    private var pageOrderSection: some View {
        Section {
            ForEach(orderedPages, id: \.self) { page in
                pageOrderRow(page)
            }
            .onMove(perform: movePages)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("PAGE ORDER")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.inkMuted)

                Spacer()

                Button("Restore Default") {
                    storedPageOrder = MainTab.defaultOrderStorageValue
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.red)
                .disabled(storedPageOrder == MainTab.defaultOrderStorageValue)
            }
            .textCase(nil)
        } footer: {
            Text("Home stays first. This order is used for both the page bar and swiping.")
                .font(.caption)
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    private func pageOrderRow(_ page: MainTab) -> some View {
        HStack(spacing: 12) {
            Text(page.title)
                .font(.headline)
                .foregroundStyle(AppColor.navy)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: page == .home ? "lock.fill" : "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColor.inkMuted)
                .frame(width: 44, height: 52)
                .contentShape(Rectangle())
        }
        .moveDisabled(page == .home)
        .modifier(PageReorderAccessibilityModifier(page: page, onMove: movePage))
    }

    private func movePages(from offsets: IndexSet, to destination: Int) {
        var updatedPages = orderedPages
        guard !offsets.contains(0) else { return }

        updatedPages.move(fromOffsets: offsets, toOffset: max(destination, 1))
        guard updatedPages != orderedPages else { return }
        savePageOrder(updatedPages)
        pageOrderHapticTick = UUID()
    }

    private func movePage(_ page: MainTab, by offset: Int) {
        guard page != .home else { return }
        var updatedPages = orderedPages
        guard let sourceIndex = updatedPages.firstIndex(of: page) else { return }
        let targetIndex = sourceIndex + offset
        guard targetIndex > 0, updatedPages.indices.contains(targetIndex) else { return }

        updatedPages.swapAt(sourceIndex, targetIndex)
        savePageOrder(updatedPages)
        pageOrderHapticTick = UUID()
    }

    private func savePageOrder(_ pages: [MainTab]) {
        storedPageOrder = pages.map(\.rawValue).joined(separator: ",")
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Hub Ball \(version) (\(build))"
    }

    private func teamSection(
        title: String,
        teams: [HubTeam],
        allowsReordering: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(AppFont.label)
                .foregroundStyle(AppColor.inkMuted)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(teams) { team in
                    teamRow(team, allowsReordering: allowsReordering)
                    if team.id != teams.last?.id {
                        Divider().overlay(AppColor.separator)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func teamRow(_ team: HubTeam, allowsReordering: Bool) -> some View {
        if allowsReordering {
            teamRowContent(team, showsReorderHandle: true)
                .dropDestination(for: String.self) { draggedTeamIDs, _ in
                    guard let draggedTeamID = draggedTeamIDs.first else { return false }
                    return moveFavorite(draggedTeamID, to: team)
                }
        } else {
            teamRowContent(team, showsReorderHandle: false)
        }
    }

    private func teamRowContent(_ team: HubTeam, showsReorderHandle: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                selectedTeamID = team.id
                onSelect(team)
            } label: {
                Text(team.fullName)
                    .font(.headline)
                    .foregroundStyle(AppColor.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedTeamID == team.id ? .isSelected : [])

            Button {
                toggleFavorite(team)
            } label: {
                Image(systemName: isFavorite(team) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite(team) ? AppColor.amber : AppColor.inkMuted)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isFavorite(team)
                    ? "Remove \(team.fullName) from favorites"
                    : "Add \(team.fullName) to favorites"
            )

            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.inkMuted)
                    .frame(width: 44, height: 52)
                    .contentShape(Rectangle())
                    .draggable(team.id)
                    .accessibilityLabel("Reorder \(team.fullName)")
                    .accessibilityHint("Drag to change its position in favorites")
                    .accessibilityAction(named: "Move up") {
                        moveFavorite(team, by: -1)
                    }
                    .accessibilityAction(named: "Move down") {
                        moveFavorite(team, by: 1)
                    }
            }
        }
        .background(selectedTeamID == team.id ? AppColor.nightRaised : Color.clear)
    }

    private func isFavorite(_ team: HubTeam) -> Bool {
        favoriteIDs.contains(team.id)
    }

    private func toggleFavorite(_ team: HubTeam) {
        var updatedFavorites = favoriteTeams
        if let index = updatedFavorites.firstIndex(of: team) {
            updatedFavorites.remove(at: index)
        } else {
            updatedFavorites.append(team)
        }

        saveFavorites(updatedFavorites)
    }

    private func moveFavorite(_ draggedTeamID: String, to targetTeam: HubTeam) -> Bool {
        var updatedFavorites = favoriteTeams
        guard
            let sourceIndex = updatedFavorites.firstIndex(where: { $0.id == draggedTeamID }),
            let targetIndex = updatedFavorites.firstIndex(of: targetTeam),
            sourceIndex != targetIndex
        else {
            return false
        }

        let movedTeam = updatedFavorites.remove(at: sourceIndex)
        updatedFavorites.insert(movedTeam, at: targetIndex)
        saveFavorites(updatedFavorites)
        return true
    }

    private func moveFavorite(_ team: HubTeam, by offset: Int) {
        var updatedFavorites = favoriteTeams
        guard let sourceIndex = updatedFavorites.firstIndex(of: team) else { return }
        let targetIndex = sourceIndex + offset
        guard updatedFavorites.indices.contains(targetIndex) else { return }

        updatedFavorites.swapAt(sourceIndex, targetIndex)
        saveFavorites(updatedFavorites)
    }

    private func saveFavorites(_ teams: [HubTeam]) {
        favoriteTeamIDs = teams.map(\.id).joined(separator: ",")
    }
}

private struct PageReorderAccessibilityModifier: ViewModifier {
    let page: MainTab
    let onMove: (MainTab, Int) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if page == .home {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Home, fixed first")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(page.title)
                .accessibilityHint("Drag to change its position in the page order")
                .accessibilityAction(named: "Move up") {
                    onMove(page, -1)
                }
                .accessibilityAction(named: "Move down") {
                    onMove(page, 1)
                }
        }
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
                        .foregroundStyle(AppColor.ink)

                    VStack(spacing: usesAccessibilityLayout ? 5 : 8) {
                        Text("WELCOME TO HUB BALL")
                            .font(.system(size: usesAccessibilityLayout ? 26 : 30, weight: .black))
                            .multilineTextAlignment(.center)
                        Text("Choose the team you want to follow first. You can switch anytime in Settings.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColor.ink.opacity(0.86))
                    }
                    .foregroundStyle(AppColor.ink)

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
                                .overlay {
                                    Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth)
                                }
                                .panelElevation()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: onContinue) {
                        Text("FOLLOW THIS TEAM")
                            .font(.headline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .foregroundStyle(AppColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, usesAccessibilityLayout ? 12 : 15)
                            .background(AppColor.nightRaised)
                            .clipShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text("All 30 MLB teams are available.")
                        .font(.caption)
                        .foregroundStyle(AppColor.ink.opacity(0.78))
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

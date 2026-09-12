import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case recent
    case standings
    case schedule
    case headlines
    case xPosts
    case players
    case pitching
    case leaders
    case stories

    var title: String {
        switch self {
        case .home: "Home"
        case .recent: "Game Recaps"
        case .schedule: "Schedule"
        case .headlines: "Newspapers"
        case .xPosts: "X Posts"
        case .standings: "Standings"
        case .players: "Players"
        case .pitching: "Pitching"
        case .leaders: "Leaders"
        case .stories: "Stories"
        }
    }

    static var defaultOrderStorageValue: String {
        allCases.map(\.rawValue).joined(separator: ",")
    }

    static func ordered(from storedValue: String) -> [MainTab] {
        var seen = Set<MainTab>()
        let storedTabs = storedValue
            .split(separator: ",")
            .compactMap { MainTab(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        let completeOrder = storedTabs + allCases.filter { !seen.contains($0) }

        return [.home] + completeOrder.filter { $0 != .home }
    }
}

struct AppTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HubPreferences.selectedTeamKey) private var selectedTeamID = HubTeam.boston.id
    @AppStorage(HubPreferences.completedTeamOnboardingKey) private var completedTeamOnboarding = false
    @AppStorage(HubPreferences.pageOrderKey) private var storedPageOrder = MainTab.defaultOrderStorageValue
    @State private var selectedTab: MainTab = .home
    @State private var settingsPresented = false
    @State private var hasAppeared = false
    @State private var backgroundedAt: Date?
    @State private var selectedPlayerID: Int?

    private let newSessionInterval: TimeInterval = 15 * 60

    private var team: HubTeam {
        HubTeam(rawValue: selectedTeamID) ?? .boston
    }

    private var palette: HubTeamPalette {
        HubTeamPalette(team: team)
    }

    private var availableTabs: [MainTab] {
        MainTab.ordered(from: storedPageOrder).filter { tab in
            switch tab {
            case .home: team.supportsHome
            case .players: team.supportsPlayers
            default: true
            }
        }
    }

    var body: some View {
        GeometryReader { window in
            VStack(spacing: 0) {
                topNavigation
                selectedContent
                    .id(team.id)
                    .environment(\.hubContentWidth, window.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColor.cream)
        .foregroundStyle(AppColor.ink)
        .font(AppFont.body)
        .environment(\.hubTeamPalette, palette)
        .onAppear {
            guard !hasAppeared else { return }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-show-stories"), team.hasPublishedStories {
                selectedTab = .stories
            } else if team.supportsPlayers,
               let playerArgument = arguments.first(where: { $0.hasPrefix("-show-player=") }),
               let playerID = Int(playerArgument.replacingOccurrences(of: "-show-player=", with: "")) {
                selectedPlayerID = playerID
                selectedTab = .players
            } else if team.supportsPlayers, arguments.contains("-show-players") {
                selectedTab = .players
            } else {
                selectedTab = team.supportsHome ? .home : .recent
            }
            #else
            selectedTab = team.supportsHome ? .home : .recent
            #endif
            hasAppeared = true
        }
        .onChange(of: selectedTeamID) { _, _ in
            selectedPlayerID = nil
            if !availableTabs.contains(selectedTab) {
                selectedTab = team.supportsHome ? .home : .recent
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let backgroundedAt,
                   Date().timeIntervalSince(backgroundedAt) >= newSessionInterval {
                    selectedTab = team.supportsHome ? .home : .recent
                }
                backgroundedAt = nil
            default:
                break
            }
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            TeamOnboardingView(selectedTeamID: $selectedTeamID) {
                completedTeamOnboarding = true
                selectedTab = team.supportsHome ? .home : .recent
            }
        }
        .sheet(isPresented: $settingsPresented) {
            TeamSettingsView(selectedTeamID: $selectedTeamID) { selectedTeam in
                selectedPlayerID = nil
                selectedTab = selectedTeam.supportsHome ? .home : .recent
                settingsPresented = false
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !completedTeamOnboarding },
            set: { isPresented in
                if !isPresented { completedTeamOnboarding = true }
            }
        )
    }

    @ViewBuilder
    private var selectedContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-show-home-run-chase") {
            NavigationStack { HomeRunChaseView() }
        } else {
            selectedTabContent
        }
        #else
        selectedTabContent
        #endif
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
                HomeView(team: team) { destination in
                    switch destination {
                    case .games: selectedTab = .recent
                    case .schedule: selectedTab = .schedule
                    case .standings: selectedTab = .standings
                    }
                }
                .mainTabSwipe(selection: $selectedTab, current: .home, availableTabs: availableTabs)
        case .recent:
                RecentGameView(team: team, onSelectPlayer: showPlayer)
                    .mainTabSwipe(selection: $selectedTab, current: .recent, availableTabs: availableTabs)
        case .schedule:
                ScheduleView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .schedule, availableTabs: availableTabs)
        case .headlines:
                HeadlinesView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .headlines, availableTabs: availableTabs)
        case .xPosts:
                XPostsView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .xPosts, availableTabs: availableTabs)
        case .standings:
                StandingsView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .standings, availableTabs: availableTabs)
        case .players:
                PlayersView(team: team, requestedPlayerID: selectedPlayerID) {
                    selectedPlayerID = nil
                }
                .mainTabSwipe(selection: $selectedTab, current: .players, availableTabs: availableTabs)
        case .pitching:
                PitchingView(team: team, onSelectPlayer: showPlayer)
                    .mainTabSwipe(selection: $selectedTab, current: .pitching, availableTabs: availableTabs)
        case .leaders:
                SeasonLeadersView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .leaders, availableTabs: availableTabs)
        case .stories:
                StoriesView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .stories, availableTabs: availableTabs)
        }
    }

    private func showPlayer(_ playerID: Int) {
        guard team.supportsPlayers else { return }
        selectedPlayerID = playerID
        selectedTab = .players
    }

    private var topNavigation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    settingsPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "baseball.fill")
                            .font(.system(size: 18, weight: .bold))

                        Text(team.shortName)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColor.boneMuted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch team")
                .accessibilityValue(team.pickerTitle)
                .accessibilityHint("Opens the team picker")

                Spacer(minLength: 8)

                Button {
                    settingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 12)

            pageStrip
        }
        .foregroundStyle(AppColor.bone)
        .background(HubMastheadBackground(palette: palette))
    }

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 22) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(
                                    .system(
                                        size: selectedTab == tab ? 18 : 15,
                                        weight: selectedTab == tab ? .bold : .medium
                                    )
                                )
                                .foregroundStyle(
                                    selectedTab == tab ? AppColor.bone : AppColor.boneMuted
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) {
                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(AppColor.amber)
                                            .frame(height: 2)
                                            .offset(y: -3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(selectedTab, anchor: .center)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
            .onChange(of: availableTabs) { _, tabs in
                guard tabs.contains(selectedTab) else { return }
                proxy.scrollTo(selectedTab, anchor: .center)
            }
        }
    }

}

private struct MainTabSwipeModifier: ViewModifier {
    @Binding var selection: MainTab
    let current: MainTab
    let availableTabs: [MainTab]
    let edgeOnly: Bool

    @Environment(\.hubContentWidth) private var contentWidth

    private let minimumDistance: CGFloat = 64
    private let edgeWidth: CGFloat = 44

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded(handleSwipe)
        )
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height

        guard abs(horizontalDistance) >= minimumDistance,
              abs(horizontalDistance) > abs(verticalDistance) * 1.35 else {
            return
        }

        if edgeOnly {
            let screenWidth = contentWidth
            let beganAtRequiredEdge = horizontalDistance < 0
                ? value.startLocation.x >= screenWidth - edgeWidth
                : value.startLocation.x <= edgeWidth
            guard beganAtRequiredEdge else { return }
        }

        let direction = horizontalDistance < 0 ? 1 : -1
        let swipeTabs = availableTabs
        guard !swipeTabs.isEmpty,
              let currentIndex = swipeTabs.firstIndex(of: current) else { return }
        let destinationIndex = (currentIndex + direction + swipeTabs.count) % swipeTabs.count
        let destination = swipeTabs[destinationIndex]

        withAnimation(.easeOut(duration: 0.2)) {
            selection = destination
        }
    }
}

private extension View {
    func mainTabSwipe(
        selection: Binding<MainTab>,
        current: MainTab,
        availableTabs: [MainTab],
        edgeOnly: Bool = false
    ) -> some View {
        modifier(
            MainTabSwipeModifier(
                selection: selection,
                current: current,
                availableTabs: availableTabs,
                edgeOnly: edgeOnly
            )
        )
    }
}

#Preview {
    AppTabView()
}

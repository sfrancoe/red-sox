import SwiftUI

private enum MainTab: Int, CaseIterable {
    case home
    case recent
    case schedule
    case headlines
    case xPosts
    case standings
    case players
    case pitching
    case leaders
    case stories
    case settings

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
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .recent: "baseball.fill"
        case .schedule: "calendar"
        case .headlines: "newspaper.fill"
        case .xPosts: "bubble.left.and.bubble.right.fill"
        case .standings: "list.number"
        case .players: "person.3.fill"
        case .pitching: "figure.baseball"
        case .leaders: "crown.fill"
        case .stories: "book.pages.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct AppTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hubSidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage(HubPreferences.selectedTeamKey) private var selectedTeamID = HubTeam.boston.id
    @AppStorage(HubPreferences.completedTeamOnboardingKey) private var completedTeamOnboarding = false
    @State private var selectedTab: MainTab = .home
    @State private var hasAppeared = false
    @State private var backgroundedAt: Date?
    @State private var selectedPlayerID: Int?

    private let newSessionInterval: TimeInterval = 15 * 60

    private var team: HubTeam {
        HubTeam(rawValue: selectedTeamID) ?? .boston
    }

    private var availableTabs: [MainTab] {
        MainTab.allCases.filter { tab in
            switch tab {
            case .home: team.supportsHome
            case .players: team.supportsPlayers
            default: true
            }
        }
    }

    var body: some View {
        GeometryReader { window in
            let usesPersistentSidebar = window.size.width >= 1000
            let showsSidebar = !sidebarCollapsed
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if usesPersistentSidebar && showsSidebar {
                        sidebar(isCompact: false)
                            .frame(width: 210)
                    }
                    VStack(spacing: 0) {
                        sidebarControls
                        selectedContent(usesPersistentSidebar: usesPersistentSidebar)
                            .id(team.id)
                            .environment(
                                \.hubContentWidth,
                                window.size.width - (usesPersistentSidebar && showsSidebar ? 210 : 0)
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !usesPersistentSidebar && showsSidebar {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                sidebarCollapsed = true
                            }
                        }

                    sidebar(isCompact: true)
                        .frame(width: min(280, window.size.width * 0.78))
                        .transition(.move(edge: .leading))
                        .shadow(color: AppColor.navy.opacity(0.22), radius: 16, x: 5)
                }
            }
        }
        .background(AppColor.paper)
        .onAppear {
            guard !hasAppeared else { return }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if team.supportsPlayers,
               let playerArgument = arguments.first(where: { $0.hasPrefix("-show-player=") }),
               let playerID = Int(playerArgument.replacingOccurrences(of: "-show-player=", with: "")) {
                selectedPlayerID = playerID
                selectedTab = .players
                sidebarCollapsed = true
            } else if team.supportsPlayers, arguments.contains("-show-players") {
                selectedTab = .players
                sidebarCollapsed = true
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
                sidebarCollapsed = true
                selectedTab = team.supportsHome ? .home : .recent
            }
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
    private func selectedContent(usesPersistentSidebar: Bool) -> some View {
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
                    .mainTabSwipe(selection: $selectedTab, current: .xPosts, availableTabs: availableTabs, edgeOnly: true)
        case .standings:
                StandingsView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .standings, availableTabs: availableTabs)
        case .players:
                PlayersView(requestedPlayerID: selectedPlayerID) {
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
        case .settings:
                TeamSettingsView(selectedTeamID: $selectedTeamID) { selectedTeam in
                    selectedPlayerID = nil
                    selectedTab = selectedTeam.supportsHome ? .home : .recent
                    sidebarCollapsed = !usesPersistentSidebar
                }
        }
    }

    private func showPlayer(_ playerID: Int) {
        guard team.supportsPlayers else { return }
        selectedPlayerID = playerID
        selectedTab = .players
        sidebarCollapsed = true
    }

    private var sidebarControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
            .accessibilityHint("Toggle the Hub Ball navigation menu")

            Text(selectedTab.title)
                .font(.headline)
            Spacer()

            Button {
                selectedTab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(AppColor.hunterGreen)
        .padding(.horizontal, 8)
        .background(AppColor.paper)
        .overlay(alignment: .bottom) {
            Divider().overlay(AppColor.border)
        }
    }

    private func sidebar(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 20) {
            Label("HUB BALL", systemImage: "baseball.fill")
                .font(isCompact ? .subheadline.weight(.black) : .title2.weight(.black))
                .foregroundStyle(AppColor.hunterGreen)
                .padding(.horizontal, isCompact ? 16 : 20)
                .padding(.top, isCompact ? 18 : 24)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .settings
                    if isCompact {
                        sidebarCollapsed = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(team.pickerTitle.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(0.5)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(AppColor.ink.opacity(0.62))
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, isCompact ? 16 : 20)
            .accessibilityLabel("Switch team")
            .accessibilityValue(team.pickerTitle)
            .accessibilityHint("Opens the team picker")
            List(availableTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                        if isCompact {
                            sidebarCollapsed = true
                        }
                    }
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(isCompact ? .caption.weight(.semibold) : .headline)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: isCompact ? 28 : 34,
                            alignment: .leading
                        )
                        .foregroundStyle(selectedTab == tab ? Color.white : AppColor.hunterGreen)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedTab == tab ? AppColor.hunterGreen : Color.clear)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(AppColor.cream)
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
        // Wide layouts use explicit navigation; horizontal drags belong to charts/pages.
        guard contentWidth < 650 else { return }
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
        guard let currentIndex = availableTabs.firstIndex(of: current) else { return }
        let destinationIndex = currentIndex + direction
        guard availableTabs.indices.contains(destinationIndex) else { return }
        let destination = availableTabs[destinationIndex]

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

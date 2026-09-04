import SwiftUI

private enum MainTab: Int, CaseIterable {
    case recent
    case schedule
    case headlines
    case xPosts
    case standings
    case pitching
    case leaders
    case game108

    var title: String {
        switch self {
        case .recent: "Games"
        case .schedule: "Schedule"
        case .headlines: "Newspapers"
        case .xPosts: "X Posts"
        case .standings: "Standings"
        case .pitching: "Pitching"
        case .leaders: "Leaders"
        case .game108: "Game 108"
        }
    }

    var icon: String {
        switch self {
        case .recent: "baseball.fill"
        case .schedule: "calendar"
        case .headlines: "newspaper.fill"
        case .xPosts: "bubble.left.and.bubble.right.fill"
        case .standings: "list.number"
        case .pitching: "figure.baseball"
        case .leaders: "crown.fill"
        case .game108: "chart.xyaxis.line"
        }
    }
}

struct AppTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hubSidebarCollapsed") private var sidebarCollapsed = false
    @State private var selectedTab: MainTab = .recent
    @State private var hasAppeared = false
    @State private var backgroundedAt: Date?

    private let newSessionInterval: TimeInterval = 15 * 60

    var body: some View {
        GeometryReader { window in
            let usesSidebar = window.size.width >= 1000
            let showsSidebar = usesSidebar && !sidebarCollapsed
            HStack(spacing: 0) {
                if showsSidebar {
                    sidebar
                        .frame(width: 210)
                }
                VStack(spacing: 0) {
                    if usesSidebar {
                        sidebarControls
                    } else {
                        topNavigation(columns: window.size.width >= 650 ? 8 : 4)
                    }
                    selectedContent
                        .environment(\.hubContentWidth, window.size.width - (showsSidebar ? 210 : 0))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColor.paper)
        .onAppear {
            guard !hasAppeared else { return }
            selectedTab = .recent
            hasAppeared = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let backgroundedAt,
                   Date().timeIntervalSince(backgroundedAt) >= newSessionInterval {
                    selectedTab = .recent
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .recent:
                RecentGameView()
                    .mainTabSwipe(selection: $selectedTab, current: .recent)
        case .schedule:
                ScheduleView()
                    .mainTabSwipe(selection: $selectedTab, current: .schedule)
        case .headlines:
                HeadlinesView()
                    .mainTabSwipe(selection: $selectedTab, current: .headlines)
        case .xPosts:
                XPostsView()
                    .mainTabSwipe(selection: $selectedTab, current: .xPosts, edgeOnly: true)
        case .standings:
                StandingsView()
                    .mainTabSwipe(selection: $selectedTab, current: .standings)
        case .pitching:
                PitchingView()
                    .mainTabSwipe(selection: $selectedTab, current: .pitching)
        case .leaders:
                SeasonLeadersView()
                    .mainTabSwipe(selection: $selectedTab, current: .leaders)
        case .game108:
                Game108GraphView()
                    .mainTabSwipe(selection: $selectedTab, current: .game108)
        }
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
        }
        .foregroundStyle(AppColor.hunterGreen)
        .padding(.horizontal, 8)
        .background(AppColor.paper)
        .overlay(alignment: .bottom) {
            Divider().overlay(AppColor.border)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("HUB BALL", systemImage: "baseball.fill")
                .font(.title2.weight(.black))
                .foregroundStyle(AppColor.hunterGreen)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            List(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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

    private func topNavigation(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: columns == 8 ? 17 : 14, weight: .bold))
                        Text(tab.title.uppercased())
                            .font(.system(size: columns == 8 ? 12 : 10, weight: .black))
                            .tracking(0.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: columns == 8 ? 54 : 42)
                    .background(selectedTab == tab ? AppColor.green : AppColor.hunterGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                selectedTab == tab ? Color.white : Color.white.opacity(0.2),
                                lineWidth: selectedTab == tab ? 2 : 0.8
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(AppColor.paper)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(AppColor.border)
        }
        .shadow(color: AppColor.navy.opacity(0.08), radius: 7, y: 3)
        .zIndex(1)
    }
}

private struct MainTabSwipeModifier: ViewModifier {
    @Binding var selection: MainTab
    let current: MainTab
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
        guard let destination = MainTab(rawValue: current.rawValue + direction) else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            selection = destination
        }
    }
}

private extension View {
    func mainTabSwipe(
        selection: Binding<MainTab>,
        current: MainTab,
        edgeOnly: Bool = false
    ) -> some View {
        modifier(
            MainTabSwipeModifier(
                selection: selection,
                current: current,
                edgeOnly: edgeOnly
            )
        )
    }
}

#Preview {
    AppTabView()
}

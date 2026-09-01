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
        case .recent: "Game"
        case .schedule: "Schedule"
        case .headlines: "Headlines"
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
    @State private var selectedTab: MainTab = .recent

    private let navigationColumns = Array(
        repeating: GridItem(.flexible(), spacing: 5),
        count: 4
    )

    var body: some View {
        VStack(spacing: 0) {
            topNavigation

            selectedContent
        }
        .background(AppColor.paper)
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

    private var topNavigation: some View {
        LazyVGrid(columns: navigationColumns, spacing: 5) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(tab.title.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : AppColor.navy)
                    .frame(maxWidth: .infinity)
                    .frame(height: 39)
                    .background(
                        selectedTab == tab
                            ? AppColor.red
                            : AppColor.paleBlue.opacity(0.58)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                selectedTab == tab ? AppColor.red : AppColor.border.opacity(0.8),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
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

    private let minimumDistance: CGFloat = 64
    private let edgeWidth: CGFloat = 44

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
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
            let screenWidth = UIScreen.main.bounds.width
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

import SwiftUI
import UIKit

private enum MainTab: Int, CaseIterable {
    case recent
    case schedule
    case headlines
    case xPosts
    case more
}

struct AppTabView: View {
    @State private var selectedTab: MainTab = .recent

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(AppColor.paper).withAlphaComponent(0.96)

        let inactiveColor = UIColor(AppColor.navy).withAlphaComponent(0.68)
        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]

        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = inactiveColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: inactiveColor
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecentGameView()
                .tabItem {
                    Label("Recent", systemImage: "baseball.fill")
                }
                .tag(MainTab.recent)
                .mainTabSwipe(selection: $selectedTab, current: .recent)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(MainTab.schedule)
                .mainTabSwipe(selection: $selectedTab, current: .schedule)

            HeadlinesView()
                .tabItem {
                    Label("Headlines", systemImage: "newspaper.fill")
                }
                .tag(MainTab.headlines)
                .mainTabSwipe(selection: $selectedTab, current: .headlines)

            XPostsView()
                .tabItem {
                    Label("X Posts", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(MainTab.xPosts)
                .mainTabSwipe(selection: $selectedTab, current: .xPosts, edgeOnly: true)

            MoreView(selectedTab: $selectedTab)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(MainTab.more)
        }
        .tint(AppColor.red)
        .toolbarBackground(AppColor.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct MoreView: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    StandingsView()
                } label: {
                    Label("Standings", systemImage: "list.number")
                }

                NavigationLink {
                    PitchingView()
                } label: {
                    Label("Pitching", systemImage: "figure.baseball")
                }

                NavigationLink {
                    SeasonLeadersView()
                } label: {
                    Label("Season Leaders", systemImage: "crown.fill")
                }

                NavigationLink {
                    Game108GraphView()
                } label: {
                    Label("Game 108 Graph", systemImage: "chart.xyaxis.line")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.cream)
            .navigationTitle("More")
            .mainTabSwipe(selection: $selectedTab, current: .more)
        }
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

private struct ComingSoonView: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.cream.ignoresSafeArea()
                ContentUnavailableView {
                    Label(title, systemImage: icon)
                } description: {
                    Text(message)
                }
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    AppTabView()
}

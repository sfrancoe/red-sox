import SwiftUI
import UIKit

struct AppTabView: View {
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
        TabView {
            RecentGameView()
                .tabItem {
                    Label("Recent", systemImage: "baseball.fill")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            HeadlinesView()
                .tabItem {
                    Label("Headlines", systemImage: "newspaper.fill")
                }

            XPostsView()
                .tabItem {
                    Label("X Posts", systemImage: "bubble.left.and.bubble.right.fill")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .tint(AppColor.red)
        .toolbarBackground(AppColor.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct MoreView: View {
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
        }
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

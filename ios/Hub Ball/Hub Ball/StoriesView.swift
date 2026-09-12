import SwiftUI

struct StoriesView: View {
    let team: HubTeam

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                if team.hasPublishedStories {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("STORIES")
                                    .font(.title2.weight(.black))
                                Text("The numbers that explain a season—and the roads they took to get there.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppColor.ink.opacity(0.72))
                            }
                            .foregroundStyle(AppColor.navy)

                            if team == .boston {
                                storyLink(
                                    title: "FOUR ROADS, ONE RECORD",
                                    summary: "Four Boston seasons reached 57–51 after 108 games—then went four different ways.",
                                    systemImage: "chart.xyaxis.line"
                                ) {
                                    Game108GraphView()
                                }
                            }

                            if team == .newYork {
                                storyLink(
                                    title: "THE HOME RUN CHASE",
                                    summary: "By age, Aaron Judge trails the legends. Count at-bats instead, and the picture flips.",
                                    systemImage: "baseball.diamond.bases"
                                ) {
                                    HomeRunChaseView()
                                }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView(
                        "\(team.shortName) stories coming soon",
                        systemImage: "book.pages",
                        description: Text("This section will appear when the first \(team.shortName) visual story is ready.")
                    )
                    .foregroundStyle(AppColor.ink)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func storyLink<Destination: View>(
        title: String,
        summary: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColor.ink)
                    .frame(width: 62, height: 62)
                    .background(AppColor.nightRaised)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(AppColor.navy)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.ink.opacity(0.76))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColor.hunterGreen)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StoriesView(team: .boston)
}

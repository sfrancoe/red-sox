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

                            NavigationLink {
                                Game108GraphView()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(AppColor.ink)
                                        .frame(width: 62, height: 62)
                                        .background(AppColor.accentSoft)
                                        .clipShape(Rectangle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("FOUR ROADS, ONE RECORD")
                                            .font(.headline.weight(.black))
                                            .foregroundStyle(AppColor.navy)
                                        Text("Four Boston seasons reached 57–51 after 108 games—then went four different ways.")
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
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView(
                        "New York stories are coming",
                        systemImage: "book.pages",
                        description: Text("This section will appear when the first New York visual story is ready.")
                    )
                    .foregroundStyle(AppColor.ink)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    StoriesView(team: .boston)
}

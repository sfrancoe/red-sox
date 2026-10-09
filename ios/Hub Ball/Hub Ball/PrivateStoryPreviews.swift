import Foundation
import SwiftUI

nonisolated struct PrivateStoryPreview: Identifiable, Sendable {
    let entry: StoryEntry
    let story: TrajectoryStory
    var id: String { entry.id }
}

/// Bundled comparison candidates never enter the remote catalog, network loader or cache.
nonisolated enum PrivateStoryPreviews {
    static let items: [PrivateStoryPreview] = {
        guard let url = Bundle.main.url(forResource: "story-private-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? StoryContract.decodeCatalog(data),
              catalog.revision == "private-october9-2026" else { return [] }
        var result: [PrivateStoryPreview] = []
        for entry in catalog.stories {
            guard let url = Bundle.main.url(forResource: "story-private-\(entry.id)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  case .trajectory(let story) = try? StoryContract.decodeDocument(data, entry: entry) else { return [] }
            result.append(PrivateStoryPreview(entry: entry, story: story))
        }
        return result
    }()
}

struct PrivateStoryComparisonView: View {
    var closeLibrary: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("THREE PITCHES · OCTOBER 9").font(AppFont.label).foregroundStyle(AppColor.amber)
                Text("Watch all three. Pick your favorite.")
                    .font(.system(.title2, design: .serif).weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text("Private previews for Scott. All three are saved in this build for offline comparison.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(PrivateStoryPreviews.items) { item in
                    NavigationLink {
                        TrajectoryStoryView(story: item.story, note: "Private preview · October 9", refresh: {})
                            .navigationTitle("Hub Ball / Stories").navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                            .toolbarBackground(AppColor.bone, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    } label: {
                        StoryPreviewCard(title: item.entry.title, summary: item.entry.summary, action: "WATCH THE CHART")
                    }.buttonStyle(.plain).accessibilityIdentifier("stories.private.\(item.id)")
                }
            }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(AppColor.paleRed.ignoresSafeArea())
            .foregroundStyle(AppColor.navy).preferredColorScheme(.light)
            .navigationTitle("October 9 previews").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if let closeLibrary {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: closeLibrary).accessibilityIdentifier("stories.private.close")
                    }
                }
            }
    }
}

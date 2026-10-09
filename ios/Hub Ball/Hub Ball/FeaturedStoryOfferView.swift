import SwiftUI

/// Owned by the app model, so rebuilding a tab or returning from background cannot reoffer it.
struct FeaturedStoryLaunch {
    private(set) var consumed = false
    mutating func offer(completedOnboarding: Bool, busy: Bool, entry: StoryEntry?) -> StoryEntry? {
        guard completedOnboarding && !busy && !consumed else { return nil }
        consumed = true
        return entry?.isSupported == true ? entry : nil
    }
}

struct FeaturedStoryOfferView: View {
    let entry: StoryEntry
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var watching = false
    @State private var detent = PresentationDetent.height(400)
    var body: some View {
        NavigationStack {
            ScrollView {
                StoryPreviewCard(title: entry.title, summary: entry.summary, action: entry.actionLabel,
                                 watch: { detent = .large; watching = true }, dismiss: close)
                    .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(AppColor.paleRed.ignoresSafeArea())
                .navigationTitle("Featured story").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $watching) {
                    RemoteStoryView(entry: entry)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button("Done", action: close).accessibilityIdentifier("featured.close")
                        } }
                }
        }.preferredColorScheme(.light)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(400), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .onAppear { if typeSize.isAccessibilitySize { detent = .large } }
            .onChange(of: typeSize) { _, value in if value.isAccessibilitySize { detent = .large } }
    }
}

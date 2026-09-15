import SwiftUI

private enum WatchShelf: String, CaseIterable, Identifiable {
    case team, league, saved
    var id: Self { self }
}

struct WatchView: View {
    let team: HubTeam
    @State private var store: WatchStore
    @State private var shelf: WatchShelf = .team
    @State private var query = ""
    @State private var selectedVideo: WatchVideo?

    init(team: HubTeam) {
        self.team = team
        _store = State(initialValue: WatchStore(team: team))
    }

    private var videos: [WatchVideo] {
        let source: [WatchVideo]
        switch shelf {
        case .team: source = store.teamVideos
        case .league: source = store.leagueVideos
        case .saved: source = store.saved
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? source : source.filter {
            $0.title.localizedCaseInsensitiveContains(term) || $0.channel.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                Picker("Video collection", selection: $shelf) {
                    Text(team.shortName).tag(WatchShelf.team)
                    Text("Around MLB").tag(WatchShelf.league)
                    Text("Saved").tag(WatchShelf.saved)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("watch.shelves")

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppColor.inkMuted)
                    TextField("Search these videos", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("watch.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(12)
                .background(AppColor.nightRaised)

                if let notice = store.notice {
                    Text(notice).font(.subheadline).foregroundStyle(AppColor.amber)
                }
                if videos.isEmpty {
                    emptyState
                } else if let featured = videos.first {
                    videoCard(featured, featured: true)
                    if videos.count > 1 {
                        Text(query.isEmpty ? "KEEP WATCHING" : "MORE RESULTS")
                            .font(AppFont.displayMedium)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 20)], spacing: 24) {
                            ForEach(videos.dropFirst()) { video in videoCard(video, featured: false) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Team and MLB videos. Playback provided by YouTube.")
                    if let date = store.updatedAt {
                        Text("Listings checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppColor.inkMuted)
            }
            .padding(18)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.night)
        .foregroundStyle(AppColor.ink)
        .task { await store.load() }
        .refreshable { await store.load() }
        .fullScreenCover(item: $selectedVideo) { video in
            WatchPlayerSheet(video: video, queue: videos, store: store)
        }
    }

    private var masthead: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WATCH").font(.custom("BarlowCondensed-SemiBold", size: 44, relativeTo: .largeTitle))
                Text("\(team.shortName) baseball. Press play.")
                    .font(.subheadline).foregroundStyle(AppColor.boneDim)
            }
            Spacer()
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 38)).foregroundStyle(AppColor.amber)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isLoading && shelf != .saved {
            ProgressView("Finding videos…").frame(maxWidth: .infinity, minHeight: 160)
        } else if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if shelf == .saved {
            ContentUnavailableView("Your next watch starts here", systemImage: "bookmark",
                                   description: Text("Save a video to find it here later. Saved on this device; playback needs an internet connection."))
        } else {
            ContentUnavailableView {
                Label("Videos aren’t available right now", systemImage: "play.slash")
            } description: {
                Text("Try refreshing, or explore the latest from around MLB.")
            } actions: {
                Button("Try again") { Task { await store.load() } }
                if shelf == .team { Button("Around MLB") { shelf = .league } }
            }
        }
    }

    private func videoCard(_ video: WatchVideo, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { selectedVideo = video } label: {
                VStack(alignment: .leading, spacing: 12) {
                    WatchThumbnail(video: video)
                        .overlay(alignment: .bottomLeading) {
                            Label(featured ? "FEATURED · WATCH NOW" : "WATCH", systemImage: "play.fill")
                                .font(.caption.weight(.bold))
                                .padding(10).background(.black.opacity(0.85)).padding(12)
                        }
                    Text(video.title)
                        .font(featured ? .title2.weight(.bold) : .headline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watch \(video.title)")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.channel).font(.subheadline.weight(.semibold))
                    Text(video.published, style: .date).font(.caption).foregroundStyle(AppColor.boneDim)
                }
                Spacer(minLength: 8)
                Button { store.toggleSaved(video) } label: {
                    Image(systemName: store.isSaved(video) ? "bookmark.fill" : "bookmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(store.isSaved(video) ? "Remove saved video" : "Save video")
                ShareLink(item: video.shareText) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share \(video.title)")
            }
        }
        .padding(14)
        .background(AppColor.nightRaised)
    }
}

private struct WatchThumbnail: View {
    let video: WatchVideo
    var body: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: video.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(AppColor.boneDim)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct WatchPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var video: WatchVideo
    let queue: [WatchVideo]
    let store: WatchStore

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 800 {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView { player }.frame(maxWidth: .infinity)
                        ScrollView { upNext }.frame(width: 280)
                    }.padding(20)
                } else {
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                player.id("watch-player")
                                upNext
                            }.padding(16)
                        }
                        .onChange(of: video.id) { _, _ in
                            scroll.scrollTo("watch-player", anchor: .top)
                        }
                    }
                }
            }
            .background(AppColor.night)
            .foregroundStyle(AppColor.ink)
            .navigationTitle("Hub Ball Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColor.nightRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var player: some View {
        VStack(alignment: .leading, spacing: 16) {
            YouTubePlayer(video: video)
                .frame(minHeight: 200)
                .aspectRatio(16 / 9, contentMode: .fit)
                .id(video.id)
            Text(video.title).font(.title2.weight(.bold))
            Text("\(video.channel) · \(video.published.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline).foregroundStyle(AppColor.boneDim)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { actions }
                VStack(alignment: .leading, spacing: 20) { actions }
            }
            Text("If playback is unavailable here, open this video on YouTube.")
                .font(.footnote).foregroundStyle(AppColor.boneDim)
            Link("Open on YouTube ↗", destination: video.url).font(.headline)
        }
        .tint(AppColor.amber)
    }

    @ViewBuilder
    private var actions: some View {
        Button { store.toggleSaved(video) } label: {
            Label(store.isSaved(video) ? "Saved" : "Save for later",
                  systemImage: store.isSaved(video) ? "bookmark.fill" : "bookmark")
        }
        ShareLink(item: video.shareText) { Label("Share video", systemImage: "square.and.arrow.up") }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 18) {
            if queue.contains(where: { $0.id != video.id }) {
                Text("UP NEXT").font(AppFont.displayMedium)
                ForEach(queue.filter { $0.id != video.id }) { next in
                    Button { video = next } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            WatchThumbnail(video: next)
                            Text(next.title).font(.headline).multilineTextAlignment(.leading)
                            Text(next.channel).font(.caption).foregroundStyle(AppColor.boneDim)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

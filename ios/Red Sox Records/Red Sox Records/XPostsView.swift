import SwiftUI

struct XPostsView: View {
    @State private var store = XPostsStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.cream.ignoresSafeArea()

                Group {
                    if let feed = store.feed {
                        feedContent(feed)
                    } else if store.isLoading {
                        ProgressView("Loading X posts…")
                            .tint(AppColor.red)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await store.load()
        }
    }

    private func feedContent(_ feed: XFeed) -> some View {
        VStack(spacing: 0) {
            modePicker

            TabView(selection: $store.selectedMode) {
                postsPage(feed.recent, feed: feed, mode: .recent)
                    .tag(XFeedMode.recent)

                postsPage(feed.popular, feed: feed, mode: .liked)
                    .tag(XFeedMode.liked)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var modePicker: some View {
        Picker("X post order", selection: $store.selectedMode) {
            ForEach(XFeedMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.paper)
    }

    private func postsPage(
        _ posts: [XPost],
        feed: XFeed,
        mode: XFeedMode
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                feedHeader(feed, mode: mode)

                ForEach(posts) { post in
                    postCard(post)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private func feedHeader(_ feed: XFeed, mode: XFeedMode) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(mode.title)
                .font(.title2.weight(.black))
                .foregroundStyle(AppColor.navy)

            Spacer()

            Text("Checked \(feed.checkedText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func postCard(_ post: XPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow(post)

            Text(post.text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !post.quotedText.isEmpty {
                quotedPost(post)
            }

            if let mediaURL = URL(string: post.media), !post.media.isEmpty {
                AsyncImage(url: mediaURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ZStack {
                        AppColor.paleBlue
                        ProgressView()
                            .tint(AppColor.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipped()
            }

            HStack {
                Label("\(post.likes.formatted())", systemImage: "heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.red)

                Spacer()

                if let url = URL(string: post.url) {
                    Link(destination: url) {
                        Label("Open on X", systemImage: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColor.navy)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func authorRow(_ post: XPost) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: post.avatar)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    AppColor.paleBlue
                    Image(systemName: "person.fill")
                        .foregroundStyle(AppColor.navy.opacity(0.55))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(post.author)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.navy)
                Text("@\(post.handle) · \(post.publishedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func quotedPost(_ post: XPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !post.quotedAuthor.isEmpty {
                Text("\(post.quotedAuthor)  @\(post.quotedHandle)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.navy)
            }

            Text(post.quotedText)
                .font(.subheadline)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.paleBlue.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("X Posts Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The X posts could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.red)
        }
    }
}

#Preview {
    XPostsView()
}

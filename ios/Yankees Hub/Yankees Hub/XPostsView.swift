import SwiftUI

struct XPostsView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = XPostsStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let feed = store.feed {
                        feedContent(feed)
                    } else if store.isLoading {
                        ProgressView("Loading X posts…")
                            .tint(.white)
                            .foregroundStyle(.white)
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

    @ViewBuilder
    private func feedContent(_ feed: XFeed) -> some View {
        if contentWidth >= 720 {
            HStack(spacing: 0) {
                postsPage(feed.popular, feed: feed, mode: .liked, pinnedHeader: true)
                Divider().overlay(Color.white.opacity(0.3))
                postsPage(feed.recent, feed: feed, mode: .recent, pinnedHeader: true)
            }
        } else {
            VStack(spacing: 0) {
                modePicker

                TabView(selection: $store.selectedMode) {
                    postsPage(feed.popular, feed: feed, mode: .liked)
                        .tag(XFeedMode.liked)

                    postsPage(feed.recent, feed: feed, mode: .recent)
                        .tag(XFeedMode.recent)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(XFeedMode.allCases) { mode in
                Button {
                    store.selectedMode = mode
                } label: {
                    Text(mode.title)
                        .font(
                            .system(
                                size: store.selectedMode == mode ? 16 : 13,
                                weight: store.selectedMode == mode ? .black : .semibold
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColor.navy.opacity(0.28), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func postsPage(
        _ posts: [XPost],
        feed: XFeed,
        mode: XFeedMode,
        pinnedHeader: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            if pinnedHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.headline.weight(.black))
                    Text("Checked \(feed.checkedText)")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            ScrollView {
                LazyVStack(spacing: contentWidth >= 650 ? 12 : 0) {
                    if !pinnedHeader {
                        feedHeader(feed, mode: mode)
                    }
                    ForEach(posts) { post in
                        postCard(post)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .foregroundStyle(AppColor.ink)
            }
            .refreshable {
                await store.load()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(contentWidth >= 650 ? .large : .xSmall)
    }

    private func feedHeader(_ feed: XFeed, mode: XFeedMode) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(mode.title)
                .font(.system(size: contentWidth >= 650 ? 18 : 16, weight: .black))
                .foregroundStyle(.white)

            Spacer()

            Text("Checked \(feed.checkedText)")
                .font(.system(size: contentWidth >= 650 ? 12 : 9))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.trailing)
        }
        .padding(.bottom, 8)
    }

    private func postCard(_ post: XPost) -> some View {
        HStack(alignment: .top, spacing: 8) {
            authorAvatar(post)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(post.author)
                        .font(.system(size: contentWidth >= 650 ? 15 : 13, weight: .bold))
                        .foregroundStyle(AppColor.navy)
                        .lineLimit(1)

                    Text("@\(post.handle)")
                        .font(.system(size: contentWidth >= 650 ? 12 : 10))
                        .foregroundStyle(AppColor.ink.opacity(0.58))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if contentWidth < 650 {
                        Text(post.publishedText)
                            .font(.system(size: 9))
                            .foregroundStyle(AppColor.ink.opacity(0.58))
                            .lineLimit(1)
                    }
                }

                if contentWidth >= 650 {
                    Text(post.publishedText)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.ink.opacity(0.58))
                }

                Text(post.displayText)
                    .font(.system(size: contentWidth >= 650 ? 15 : 13))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.quotedText.isEmpty {
                    quotedPost(post)
                }

                if let mediaURL = URL(string: post.media), !post.media.isEmpty {
                    GeometryReader { media in
                        AsyncImage(url: mediaURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                AppColor.paleBlue
                                ProgressView().tint(AppColor.red)
                            }
                        }
                        .frame(width: media.size.width, height: media.size.height)
                        .clipped()
                    }
                    .frame(height: contentWidth >= 650 ? 210 : 125)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack {
                    Label("\(post.likes.formatted())", systemImage: "heart.fill")
                        .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .bold))
                        .foregroundStyle(AppColor.red)

                    Spacer()

                    if let url = URL(string: post.url) {
                        Link(destination: url) {
                            Label("Open on X", systemImage: "arrow.up.right")
                                .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .bold))
                                .foregroundStyle(AppColor.navy)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(AppColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: contentWidth >= 650 ? 16 : 0))
        .overlay(alignment: .bottom) {
            if contentWidth < 650 {
                Rectangle()
                    .fill(AppColor.border.opacity(0.8))
                    .frame(height: 1)
            }
        }
    }

    private func authorAvatar(_ post: XPost) -> some View {
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
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private func quotedPost(_ post: XPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !post.quotedAuthor.isEmpty {
                Text("\(post.quotedAuthor)  @\(post.quotedHandle)")
                    .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .bold))
                    .foregroundStyle(AppColor.navy)
            }

            Text(post.displayQuotedText)
                .font(.system(size: contentWidth >= 650 ? 13 : 11))
                .lineSpacing(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.paleBlue.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

import SwiftUI

struct XPostsView: View {
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
        HStack(spacing: 4) {
            ForEach(XFeedMode.allCases) { mode in
                Button {
                    store.selectedMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.white)
                        .background(AppColor.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    store.selectedMode == mode
                                        ? AppColor.red
                                        : Color.white.opacity(0.18),
                                    lineWidth: store.selectedMode == mode ? 2.5 : 0.8
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(AppColor.navy)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func postsPage(
        _ posts: [XPost],
        feed: XFeed,
        mode: XFeedMode
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedHeader(feed, mode: mode)

                ForEach(posts) { post in
                    postCard(post)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .foregroundStyle(AppColor.ink)
        }
        .dynamicTypeSize(.xSmall)
        .refreshable {
            await store.load()
        }
    }

    private func feedHeader(_ feed: XFeed, mode: XFeedMode) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(mode.title)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)

            Spacer()

            Text("Checked \(feed.checkedText)")
                .font(.system(size: 9))
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.navy)
                        .lineLimit(1)

                    Text("@\(post.handle)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.ink.opacity(0.58))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Text(post.publishedText)
                        .font(.system(size: 9))
                        .foregroundStyle(AppColor.ink.opacity(0.58))
                        .lineLimit(1)
                }

                Text(post.text)
                    .font(.system(size: 13))
                    .lineSpacing(1)
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
                    .frame(height: 125)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .clipped()
                }

                HStack {
                    Label("\(post.likes.formatted())", systemImage: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColor.red)

                    Spacer()

                    if let url = URL(string: post.url) {
                        Link(destination: url) {
                            Label("Open on X", systemImage: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppColor.navy)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(AppColor.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.border.opacity(0.8))
                .frame(height: 1)
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.navy)
            }

            Text(post.quotedText)
                .font(.system(size: 11))
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

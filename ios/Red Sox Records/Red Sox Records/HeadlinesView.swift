import SwiftUI

struct HeadlinesView: View {
    @State private var store = HeadlinesStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let feed = store.selectedFeed {
                        feedContent(feed)
                    } else if store.isLoading {
                        ProgressView("Loading headlines…")
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

    private func feedContent(_ feed: NewsFeed) -> some View {
        VStack(spacing: 0) {
            sourcePicker

            ScrollView {
                LazyVStack(spacing: 8) {
                    feedHeader(feed)

                    ForEach(feed.articles) { article in
                        articleCard(article)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .foregroundStyle(AppColor.ink)
            }
            .id(store.selectedSource)
            .refreshable {
                await store.load()
            }
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 0) {
            ForEach(NewsSource.allCases) { source in
                Button {
                    store.selectedSource = source
                } label: {
                    Text(source.shortName)
                        .font(
                            .system(
                                size: store.selectedSource == source ? 16 : 13,
                                weight: store.selectedSource == source ? .black : .semibold
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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

    private func feedHeader(_ feed: NewsFeed) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feed.source)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)

            Spacer()

            Text("Updated \(feed.refreshedText)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .multilineTextAlignment(.trailing)
        }
    }

    private func articleCard(_ article: NewsArticle) -> some View {
        Group {
            if let url = URL(string: article.url) {
                Link(destination: url) {
                    articleContent(article)
                }
                .buttonStyle(.plain)
            } else {
                articleContent(article)
            }
        }
        .frame(minHeight: 142, alignment: .topLeading)
        .cardStyle(padding: 14)
    }

    private func articleContent(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(article.category.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(AppColor.red)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(Color.black)

                Text(article.publishedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.red)
            }

            Text(article.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black)
                    .lineSpacing(2)
                    .lineLimit(4)
            }
        }
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Headlines Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The headlines could not be loaded.")
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
    HeadlinesView()
}

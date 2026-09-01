import SwiftUI

struct HeadlinesView: View {
    @State private var store = HeadlinesStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.cream.ignoresSafeArea()

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
                LazyVStack(spacing: 12) {
                    feedHeader(feed)

                    ForEach(feed.articles) { article in
                        articleCard(article)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .foregroundStyle(AppColor.ink)
            }
            .id(store.selectedSource)
            .refreshable {
                await store.load()
            }
        }
    }

    private var sourcePicker: some View {
        Picker("News source", selection: $store.selectedSource) {
            ForEach(NewsSource.allCases) { source in
                Text(source.shortName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.paper)
    }

    private func feedHeader(_ feed: NewsFeed) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feed.source)
                .font(.title2.weight(.black))
                .foregroundStyle(AppColor.navy)

            Spacer()

            Text("Updated \(feed.refreshedText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        .cardStyle()
    }

    private func articleContent(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(article.category.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(AppColor.red)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(article.publishedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.red)
            }

            Text(article.title)
                .font(.headline)
                .foregroundStyle(AppColor.navy)
                .fixedSize(horizontal: false, vertical: true)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.ink.opacity(0.82))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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

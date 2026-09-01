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
            .dynamicTypeSize(.xSmall)
            .id(store.selectedSource)
            .refreshable {
                await store.load()
            }
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(NewsSource.allCases) { source in
                Button {
                    store.selectedSource = source
                } label: {
                    Text(source.shortName)
                        .font(.system(size: 12, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(
                            store.selectedSource == source ? AppColor.hunterGreen : Color.white
                        )
                        .background(
                            store.selectedSource == source ? Color.white : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(AppColor.hunterGreen)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func feedHeader(_ feed: NewsFeed) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feed.source)
                .font(.title2.weight(.black))
                .foregroundStyle(.white)

            Spacer()

            Text("Updated \(feed.refreshedText)")
                .font(.caption2)
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
        .cardStyle(padding: 12)
    }

    private func articleContent(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(article.category.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(AppColor.red)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(AppColor.ink.opacity(0.55))

                Text(article.publishedText)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.ink)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.red)
            }

            Text(article.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColor.navy)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.ink.opacity(0.82))
                    .lineSpacing(1)
                    .lineLimit(2)
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

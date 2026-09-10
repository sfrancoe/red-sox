import SwiftUI
import SafariServices

struct HeadlinesView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store: HeadlinesStore
    @State private var secondarySource: NewsSource
    @State private var presentedArticle: PresentedArticle?
    let team: HubTeam

    init(team: HubTeam = .boston) {
        self.team = team
        _store = State(initialValue: HeadlinesStore(team: team))
        _secondarySource = State(initialValue: team.newsSources.dropFirst().first ?? team.newsSources[0])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if !store.feeds.isEmpty {
                        GeometryReader { space in
                            if contentWidth >= 720 && space.size.height > space.size.width {
                                let rows = team.newsSources.chunked(into: 2)
                                VStack(spacing: 12) {
                                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                        HStack(spacing: 12) {
                                            ForEach(row) { source in
                                                newspaperQuadrant(source)
                                            }
                                            if row.count == 1 {
                                                Color.clear.frame(maxWidth: .infinity)
                                            }
                                        }
                                        .frame(height: max(1, (space.size.height - 12 * CGFloat(rows.count + 1)) / CGFloat(rows.count)))
                                    }
                                }
                                .padding(12)
                            } else {
                                HStack(spacing: 0) {
                                    newspaperColumn(selection: $store.selectedSource)
                                    if contentWidth >= 720 {
                                        Divider().overlay(AppColor.rule)
                                        newspaperColumn(selection: $secondarySource)
                                    }
                                }
                            }
                        }
                    } else if store.isLoading {
                        ProgressView("Loading headlines…")
                            .tint(AppColor.ink)
                            .foregroundStyle(AppColor.ink)
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
        .sheet(item: $presentedArticle) { article in
            SafariView(url: article.url)
                .ignoresSafeArea()
        }
    }

    private func newspaperQuadrant(_ source: NewsSource) -> some View {
        VStack(spacing: 0) {
            Text(store.feeds[source]?.source ?? source.shortName)
                .font(AppFont.displaySmall)
                .foregroundStyle(AppColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColor.nightRaised)
                .accessibilityAddTraits(.isHeader)

            Divider().overlay(AppColor.separator)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let feed = store.feeds[source] {
                        ForEach(Array(feed.articles.enumerated()), id: \.element.id) { index, article in
                            newspaperStory(article)
                            if index < feed.articles.count - 1 {
                                Divider().overlay(AppColor.separator)
                            }
                        }
                    } else {
                        errorView
                    }
                }
                .padding(.horizontal, 14)
            }
            .refreshable { await store.load() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }

    private func newspaperStory(_ article: NewsArticle) -> some View {
        Group {
            if let url = URL(string: article.url) {
                Button {
                    presentedArticle = PresentedArticle(url: url)
                } label: {
                    newspaperStoryText(article)
                }
                .buttonStyle(SwipeSafeLinkStyle())
                .accessibilityAddTraits(.isLink)
            } else {
                newspaperStoryText(article)
            }
        }
    }

    private func newspaperStoryText(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            articleHeadline(article, fontSize: 17)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.ink.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(article.publishedText)
                .font(AppFont.label)
                .foregroundStyle(AppColor.hunterGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func newspaperColumn(selection: Binding<NewsSource>) -> some View {
        VStack(spacing: 0) {
            sourcePicker(selection: selection)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if let feed = store.feeds[selection.wrappedValue] {
                        feedHeader(feed)

                        ForEach(feed.articles) { article in
                            articleCard(article)
                        }
                    } else {
                        errorView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .foregroundStyle(AppColor.ink)
            }
            .id(selection.wrappedValue)
            .refreshable {
                await store.load()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourcePicker(selection: Binding<NewsSource>) -> some View {
        HStack(spacing: 0) {
            ForEach(team.newsSources) { source in
                Button {
                    selection.wrappedValue = source
                } label: {
                    Text(source.shortName)
                        .font(
                            .system(
                                size: selection.wrappedValue == source ? 16 : 13,
                                weight: selection.wrappedValue == source ? .black : .semibold
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selection.wrappedValue == source ? AppColor.ink : AppColor.inkMuted)
                        .overlay(alignment: .bottom) {
                            if selection.wrappedValue == source {
                                Rectangle().fill(AppColor.accent).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == source ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func feedHeader(_ feed: NewsFeed) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(feed.source)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(AppColor.ink)

            Spacer()

            Text("Updated \(feed.refreshedText)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppColor.ink.opacity(0.78))
                .multilineTextAlignment(.trailing)
        }
    }

    private func articleCard(_ article: NewsArticle) -> some View {
        Group {
            if let url = URL(string: article.url) {
                Button {
                    presentedArticle = PresentedArticle(url: url)
                } label: {
                    articleContent(article)
                }
                .buttonStyle(SwipeSafeLinkStyle())
                .accessibilityAddTraits(.isLink)
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
                    .foregroundStyle(AppColor.ink)

                Text(article.publishedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.ink)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.red)
            }

            articleHeadline(article, fontSize: contentWidth >= 650 ? 21 : 16,
                            lineLimit: contentWidth >= 650 ? 5 : 3)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.ink)
                    .lineSpacing(2)
                    .lineLimit(4)
            }
        }
    }

    private func articleHeadline(_ article: NewsArticle, fontSize: CGFloat, lineLimit: Int? = nil) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let isNew = article.isNew(asOf: timeline.date)
            let badge = Text(isNew ? "  ⚡ NEW" : "")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(AppColor.red)
            Text("\(Text(article.title))\(badge)")
                .font(AppFont.displaySmall)
                .foregroundStyle(AppColor.ink)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(isNew ? "New in the last six hours. \(article.title)" : article.title)
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
            .buttonStyle(HubProminentButtonStyle())
            .tint(AppColor.red)
        }
    }
}

private struct PresentedArticle: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// A primitive button's built-in press can complete alongside the parent page-swipe
// gesture. A real tap opens the article, while a drag fails this tap gesture.
private struct SwipeSafeLinkStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onTapGesture {
                configuration.trigger()
            }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    HeadlinesView()
}

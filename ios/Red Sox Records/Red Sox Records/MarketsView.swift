import SwiftUI
import Charts
import Observation

private struct SoxMarket: Decodable, Identifiable {
    let id: String
    let provider: String
    let title: String
    let question: String
    let outcome: String
    let category: String
    let probability: Double?
    let bid: Double?
    let ask: Double?
    let volume: Double?
    let volumeUnit: String
    let date: String?
    let timeLabel: String
    let matchKey: String?
    let historyId: String
    let rules: String
    let url: String
    var key: String { provider + id }
    var tint: Color { provider == "Kalshi" ? AppColor.green : Color(red: 0.24, green: 0.40, blue: 0.85) }
    var percent: String { probability.map { String(format: "%.1f%%", $0 * 100) } ?? "—" }
    var dayLabel: String {
        guard let date else { return "Season outlook" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
        guard let d = f.date(from: date) else { return date }
        f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
private struct MarketSnapshot: Decodable {
    struct Source: Decodable { let name: String; let available: Bool }
    let generatedAt: String
    let markets: [SoxMarket]
    let sources: [Source]
    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: generatedAt) ?? ISO8601DateFormatter().date(from: generatedAt)
    }
}
private struct MarketPoint: Decodable, Identifiable {
    let t: Double
    let p: Double
    var id: Double { t }
    var date: Date { Date(timeIntervalSince1970: t) }
}
private struct MarketHistory: Decodable { let points: [MarketPoint] }

@MainActor @Observable
private final class MarketsStore {
    var snapshot: MarketSnapshot?
    var loading = false
    var error: String?
    var histories: [String: [MarketPoint]] = [:]
    var historyErrors: Set<String> = []
    var pending: Set<String> = []
    private var base: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-local-markets") {
            return URL(string: "http://localhost:8768/api/redsox-markets")!
        }
        #endif
        return URL(string: "https://red-sox.netlify.app/api/redsox-markets")!
    }
    private let cacheKey = "redsox.marketSnapshot.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            snapshot = try? JSONDecoder().decode(MarketSnapshot.self, from: data)
        }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let data = try await get(base)
            let next = try JSONDecoder().decode(MarketSnapshot.self, from: data)
            snapshot = next; error = nil
            histories.removeAll(); historyErrors.removeAll()
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            self.error = snapshot == nil ? "The market feeds are unavailable. Please try again." : "Refresh unavailable. Showing the last saved snapshot."
        }
    }
    func historyKey(_ market: SoxMarket, days: Int) -> String { "\(market.key):\(days)" }
    func loadHistory(_ market: SoxMarket, days: Int) async {
        let key = historyKey(market, days: days)
        guard histories[key] == nil, !pending.contains(key) else { return }
        pending.insert(key); historyErrors.remove(key)
        defer { pending.remove(key) }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "history", value: market.historyId), URLQueryItem(name: "provider", value: market.provider), URLQueryItem(name: "days", value: String(days))]
        do { histories[key] = try JSONDecoder().decode(MarketHistory.self, from: await get(components.url!)).points }
        catch { historyErrors.insert(key) }
    }
    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

struct MarketsView: View {
    @Environment(\.hubContentWidth) private var width
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = MarketsStore()
    @State private var provider = "Both"
    @State private var category = "All"
    @State private var selectedGame: String?
    @State private var detail: SoxMarket?
    private var markets: [SoxMarket] { store.snapshot?.markets ?? [] }
    private var games: [SoxMarket] {
        var seen: Set<String> = []
        return markets.filter { $0.category == "Winner" && $0.matchKey != nil && seen.insert($0.matchKey!).inserted }
    }
    private var featured: [SoxMarket] {
        guard let key = games.first(where: { $0.matchKey == selectedGame })?.matchKey ?? games.first?.matchKey else { return [] }
        let candidates = markets.filter { $0.category == "Winner" && $0.matchKey == key }
        // Do not compare ambiguous doubleheaders as if they were the same game.
        return candidates.filter { market in candidates.filter { $0.provider == market.provider }.count == 1 }
    }
    private var filtered: [SoxMarket] {
        markets.filter { (provider == "Both" || $0.provider == provider) && (category == "All" || $0.category == category) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                masthead
                if let snapshot = store.snapshot {
                    freshness(snapshot)
                    if !featured.isEmpty { feature }
                    octoberWatch
                    marketBoard
                } else if store.loading {
                    ProgressView("Finding Red Sox markets…").frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ContentUnavailableView("Markets unavailable", systemImage: "chart.line.downtrend.xyaxis", description: Text(store.error ?? "Refresh to load the latest markets."))
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(AppColor.red)
                }
                methodology
            }
            .padding(width >= 650 ? 24 : 16)
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.cream)
        .preferredColorScheme(.light)
        .refreshable { await store.refresh() }
        .task {
            await store.refresh()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-market-detail") { detail = markets.first(where: { $0.provider == "Kalshi" && $0.category == "Winner" }) }
            if ProcessInfo.processInfo.arguments.contains("-market-season") { category = "Season" }
            #endif
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(120)) } catch { break }
                if scenePhase == .active { await store.refresh() }
            }
        }
        .sheet(item: $detail) { market in MarketDetail(market: market, store: store) }
    }
    private var masthead: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("KALSHI + POLYMARKET").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(AppColor.green)
                Text("Fenway Forecast").font(.system(size: width >= 650 ? 42 : 32, weight: .black, design: .serif)).foregroundStyle(AppColor.hunterGreen)
                Text("The market’s view of what comes next.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.title3).frame(width: 44, height: 44)
            }.disabled(store.loading).accessibilityLabel("Refresh markets")
        }
    }
    private func freshness(_ snapshot: MarketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(snapshot.sources, id: \.name) { source in
                    Label(source.available ? source.name : "\(source.name) unavailable", systemImage: source.available ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(source.available ? AppColor.green : AppColor.red)
                }
            }.font(.caption.weight(.semibold))
            if let date = snapshot.date {
                HStack(spacing: 4) {
                    Text("Snapshot"); Text(date, style: .relative); Text("ago")
                    if Date().timeIntervalSince(date) > 600 { Text("• Older prices").foregroundStyle(AppColor.red) }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var feature: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("GAME SPOTLIGHT", systemImage: "baseball.fill").font(.caption.weight(.black)).tracking(1.5)
                Spacer()
                Text("RED SOX TO WIN").font(.caption2.weight(.bold))
            }.foregroundStyle(AppColor.hunterGreen)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(games, id: \.key) { game in
                        Button { selectedGame = game.matchKey } label: {
                            Text("\(game.dayLabel) · \(game.matchKey?.components(separatedBy: ":").last ?? "")")
                                .font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 9)
                                .background(featured.first?.matchKey == game.matchKey ? AppColor.hunterGreen : AppColor.cream)
                                .foregroundStyle(featured.first?.matchKey == game.matchKey ? .white : AppColor.ink)
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text(featured.first(where: { $0.provider == "Polymarket" })?.title ?? featured.first?.title ?? "Red Sox")
                .font(.title2.weight(.bold)).foregroundStyle(AppColor.ink)
            HStack(alignment: .top, spacing: 24) {
                ForEach(featured, id: \.key) { market in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(market.provider).font(.subheadline.weight(.bold)).foregroundStyle(market.tint)
                        Text(market.percent).font(.system(size: width >= 650 ? 54 : 40, weight: .black, design: .rounded)).monospacedDigit()
                        Text("Implied probability").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            MarketTrend(markets: featured, store: store, tall: true)
            if featured.count == 2, let a = featured[0].probability, let b = featured[1].probability {
                Label(String(format: "The markets are %.1f percentage points apart.", abs(a-b)*100), systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.medium)).foregroundStyle(AppColor.hunterGreen)
            }
            Text("Prices reflect market sentiment. Each provider’s settlement rules and fees can differ.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(width >= 650 ? 26 : 18).background(.white).clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private var octoberWatch: some View {
        let picks = markets.filter { $0.provider == "Polymarket" && $0.category == "Season" && ($0.question.contains("World Series") || $0.question.contains("clinch a spot") || $0.question.contains("AL East title")) }
        return VStack(alignment: .leading, spacing: 14) {
            if !picks.isEmpty {
                HStack {
                    Text("Eyes on October").font(.title2.bold())
                    Spacer()
                    Text("POLYMARKET").font(.caption2.bold()).tracking(1)
                }.foregroundStyle(.white)
                ForEach(picks, id: \.key) { market in
                    Button { detail = market } label: {
                        HStack {
                            Text(market.question.contains("World Series") ? "Win the World Series" : market.question.contains("AL East") ? "Win the AL East" : "Reach the postseason")
                                .font(.headline)
                            Spacer()
                            Text(market.percent).font(.title2.bold()).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(.white).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                    Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                }
            }
        }.padding(picks.isEmpty ? 0 : 22).background(AppColor.hunterGreen).clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private var marketBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("The market board").font(.title2.bold()).foregroundStyle(AppColor.hunterGreen)
                Spacer()
                Text("\(filtered.count) markets").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Provider", selection: $provider) {
                ForEach(["Both", "Kalshi", "Polymarket"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(["All", "Winner", "Totals", "Spread", "Game props", "Season"], id: \.self) { name in
                        Button { category = name } label: {
                            Text(name).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                                .foregroundStyle(category == name ? .white : AppColor.hunterGreen)
                                .background(category == name ? AppColor.hunterGreen : .white).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if filtered.isEmpty {
                ContentUnavailableView("No open markets here", systemImage: "baseball", description: Text("Try another category or provider. New markets appear as they are listed."))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: width >= 950 ? 3 : width >= 650 ? 2 : 1), spacing: 14) {
                ForEach(filtered, id: \.key) { market in
                    Button { detail = market } label: { marketCard(market) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func marketCard(_ market: SoxMarket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(market.provider.uppercased()).tracking(1).foregroundStyle(market.tint)
                Spacer()
                Text(market.category).foregroundStyle(.secondary)
            }.font(.caption2.weight(.heavy))
            Text(market.question).font(.headline).foregroundStyle(AppColor.ink).fixedSize(horizontal: false, vertical: true)
            if market.category != "Season" {
                Text("\(market.title) · \(market.dayLabel) · \(market.timeLabel)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(market.percent).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(AppColor.hunterGreen)
                Text(market.outcome).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if market.probability == nil { Text("No two-sided quote available").font(.caption).foregroundStyle(.secondary) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.cream)
                    Capsule().fill(market.tint).frame(width: g.size.width * (market.probability ?? 0))
                }
            }.frame(height: 5).accessibilityHidden(true)
            HStack {
                if let volume = market.volume {
                    Text(volume.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))) + Text(" \(market.volumeUnit)")
                } else { Text("Volume unavailable") }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                Image(systemName: "chevron.right")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens price history and market rules")
    }
    private var methodology: some View {
        DisclosureGroup("How to read these markets") {
            Text("A 60% price means the market prices that outcome at roughly 60 cents per dollar of potential payout; it is not a guarantee. Kalshi probabilities use the midpoint of a two-sided bid/ask quote. Polymarket probabilities use its published outcome prices. Charts show hourly observations, and movement is measured in percentage points across the available history. Volume is shown in each provider’s own units and should not be added together. Quotes refresh about every two minutes while this page is open. This is an informational market-data view.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
        }.font(.subheadline.weight(.semibold)).tint(AppColor.hunterGreen)
    }
}

private struct MarketTrend: View {
    let markets: [SoxMarket]
    let store: MarketsStore
    var tall = false
    @State private var days = 1
    @State private var selectedDate: Date?
    private var chartDomain: ClosedRange<Double> {
        let values = markets.flatMap { points($0).map { $0.p * 100 } }
        let lower = max(0, floor(((values.min() ?? 0) - 5) / 5) * 5)
        let upper = min(100, ceil(((values.max() ?? 100) + 5) / 5) * 5)
        return lower...max(lower + 1, upper)
    }
    private var identity: String { markets.map(\.key).joined() + String(days) + (store.snapshot?.generatedAt ?? "") }
    private func points(_ m: SoxMarket) -> [MarketPoint] { store.histories[store.historyKey(m, days: days)] ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Probability trail").font(.subheadline.bold())
                Spacer()
                Picker("History range", selection: $days) { Text("24H").tag(1); Text("7D").tag(7) }.pickerStyle(.segmented).frame(width: 130)
            }
            if markets.contains(where: { points($0).count >= 2 }) {
                Chart {
                    if chartDomain.contains(50) {
                        RuleMark(y: .value("Even chance", 50)).foregroundStyle(.gray.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    ForEach(markets, id: \.key) { m in
                        ForEach(points(m)) { p in
                            LineMark(x: .value("Time", p.date), y: .value("Probability", p.p * 100), series: .value("Provider", m.provider))
                                .foregroundStyle(by: .value("Provider", m.provider)).interpolationMethod(.linear)
                        }
                    }
                    if let selectedDate {
                        RuleMark(x: .value("Selected", selectedDate)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
                .chartForegroundStyleScale(domain: markets.map(\.provider), range: markets.map(\.tint))
                .chartYScale(domain: chartDomain)
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Double.self) { Text("\(Int(n))%") } } } }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: days == 1 ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: tall ? 240 : 200)
                ForEach(markets, id: \.key) { market in
                    let history = points(market)
                    if let selectedDate, let nearest = history.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) {
                        Text("\(market.provider) · \(nearest.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f%%", nearest.p * 100))").font(.caption).foregroundStyle(market.tint)
                    } else if let first = history.first, let last = history.last, history.count >= 2 {
                        Text(String(format: "%@  %+.1f pts across available history", market.provider, (last.p-first.p)*100)).font(.caption.weight(.semibold)).foregroundStyle(market.tint)
                    }
                }
            } else if markets.contains(where: { store.pending.contains(store.historyKey($0, days: days)) }) {
                ProgressView("Loading price history…").frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Label("Not enough price history yet", systemImage: "chart.xyaxis.line").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 130)
            }
            ForEach(markets.filter { points($0).count < 2 && store.histories[store.historyKey($0, days: days)] != nil }, id: \.key) { m in
                Text("\(m.provider): insufficient history in this window").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(markets.filter { store.historyErrors.contains(store.historyKey($0, days: days)) }, id: \.key) { m in
                Button("Retry \(m.provider) history") { Task { await store.loadHistory(m, days: days) } }.font(.caption)
            }
        }
        .task(id: identity) { selectedDate = nil; for market in markets { await store.loadHistory(market, days: days) } }
    }
}
private struct MarketDetail: View {
    let market: SoxMarket
    let store: MarketsStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(market.provider.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(market.tint)
                    Text(market.question).font(.title.bold())
                    HStack(alignment: .firstTextBaseline) {
                        Text(market.percent).font(.system(size: 52, weight: .black, design: .rounded))
                        Text(market.outcome).font(.headline).foregroundStyle(.secondary)
                    }.foregroundStyle(AppColor.hunterGreen)
                    Text("Snapshot price · \(market.dayLabel)").font(.caption).foregroundStyle(.secondary)
                    if let date = store.snapshot?.date { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    MarketTrend(markets: [market], store: store)
                    if let bid = market.bid, let ask = market.ask {
                        HStack {
                            quote("Bid", bid); Spacer(); quote("Ask", ask); Spacer(); quote("Spread", max(0, ask-bid))
                        }.padding().background(AppColor.cream).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text("What resolves this market?").font(.headline)
                    Text(market.rules).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    if let url = URL(string: market.url) { Link("Source & full market rules ↗", destination: url).font(.headline).tint(market.tint) }
                }.padding(24)
            }.navigationTitle("Market detail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func quote(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption).foregroundStyle(.secondary); Text(String(format: "%.1f¢", value*100)).font(.headline).monospacedDigit() }
    }
}

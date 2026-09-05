import SwiftUI
import Charts
import Observation

private struct YankeesMarket: Decodable, Identifiable {
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
    let markets: [YankeesMarket]
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
            return URL(string: "http://localhost:8768/api/yankees-markets")!
        }
        #endif
        return URL(string: "https://red-sox.netlify.app/api/yankees-markets")!
    }
    private let cacheKey = "yankees.marketSnapshot.v1"
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
    func historyKey(_ market: YankeesMarket, days: Int) -> String { "\(market.key):\(days)" }
    func loadHistory(_ market: YankeesMarket, days: Int) async {
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
    @State private var detail: YankeesMarket?
    private var markets: [YankeesMarket] { store.snapshot?.markets ?? [] }
    private var filtered: [YankeesMarket] {
        markets.filter { (provider == "Both" || $0.provider == provider) && (category == "All" || $0.category == category) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let snapshot = store.snapshot {
                    octoberWatch
                    freshness(snapshot)
                    marketBoard
                } else if store.loading {
                    ProgressView("Finding Yankees markets…").tint(.white).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ContentUnavailableView("Markets unavailable", systemImage: "chart.line.downtrend.xyaxis", description: Text(store.error ?? "Refresh to load the latest markets.")).foregroundStyle(.white)
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.white)
                }
                methodology
            }
            .padding(width >= 650 ? 24 : 16)
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.paleRed.ignoresSafeArea())
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
    private func freshness(_ snapshot: MarketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.sources.filter { !$0.available }, id: \.name) { source in
                Label("\(source.name) unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.white)
            }
            if let date = snapshot.date {
                HStack(spacing: 4) {
                    Text("Snapshot"); Text(date, style: .relative); Text("ago")
                    if Date().timeIntervalSince(date) > 600 { Text("• Older prices").foregroundStyle(.white) }
                }.font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
    private var octoberWatch: some View {
        let picks = markets.filter { $0.provider == "Polymarket" && $0.category == "Season" && ($0.question.contains("World Series") || $0.question.contains("clinch a spot") || $0.question.contains("AL East title")) }
        return VStack(spacing: 0) {
            if !picks.isEmpty {
                HStack {
                    Text("EYES ON OCTOBER").font(.caption2.bold())
                    Spacer()
                    Text("POLYMARKET").font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(AppColor.hunterGreen)
                ForEach(Array(picks.enumerated()), id: \.element.key) { index, market in
                    Button { detail = market } label: {
                        HStack(spacing: 0) {
                            Text(market.question.contains("World Series") ? "Win the World Series" : market.question.contains("AL East") ? "Win the AL East" : "Reach the postseason")
                                .foregroundStyle(AppColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                            Text(market.percent).monospacedDigit()
                                .foregroundStyle(AppColor.hunterGreen)
                                .frame(width: 72, alignment: .trailing)
                                .padding(.horizontal, 8)
                                .frame(maxHeight: .infinity)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(AppColor.border).frame(width: 0.5)
                                }
                        }
                        .font(.caption)
                        .frame(minHeight: 40)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(index.isMultiple(of: 2) ? AppColor.paper : AppColor.cream)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AppColor.border).frame(height: 0.5)
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Opens price history and market rules")
                }
            }
        }
        .overlay {
            if !picks.isEmpty { Rectangle().stroke(AppColor.border, lineWidth: 1) }
        }
    }
    private var marketBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The market board").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(filtered.count) markets").font(.caption.weight(.semibold)).foregroundStyle(AppColor.hunterGreen)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(AppColor.paper).clipShape(Capsule())
            }
            Picker("Provider", selection: $provider) {
                ForEach(["Both", "Kalshi", "Polymarket"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
                .background(AppColor.paper, in: RoundedRectangle(cornerRadius: 8))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(["All", "Winner", "Totals", "Spread", "Game props", "Season"], id: \.self) { name in
                        Button { category = name } label: {
                            Text(name).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
                                .foregroundStyle(category == name ? .white : AppColor.hunterGreen)
                                .background(category == name ? AppColor.hunterGreen : .white).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if filtered.isEmpty {
                ContentUnavailableView("No open markets here", systemImage: "baseball", description: Text("Try another category or provider. New markets appear as they are listed.")).foregroundStyle(.white)
            }
            if !filtered.isEmpty {
                Text("Tap a row for details · Swipe sideways for more columns")
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
                marketTable
            }
        }
    }
    // One shared column layout keeps headers and values aligned at every width.
    private var marketColumnWidths: [CGFloat] {
        [190, 72, 100, 90, 150, 120, 100, 130]
    }
    private func tableCell(_ text: String, column: Int, header: Bool = false,
                           color: Color = AppColor.ink) -> some View {
        Text(text)
            .font(header ? .caption2.weight(.bold) : .caption)
            .monospacedDigit()
            .foregroundStyle(header ? .white : color)
            .lineLimit(column == 0 && !header ? 2 : 1)
            .frame(width: marketColumnWidths[column] - 16,
                   alignment: column == 1 || column == 7 ? .trailing : .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, header ? 0 : 6)
            .frame(minHeight: header ? 30 : 48)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(header ? .white.opacity(0.18) : AppColor.border)
                    .frame(width: 0.5)
            }
    }
    private var marketTable: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(["MARKET", "CHANCE", "SOURCE", "TYPE", "GAME", "DATE", "TIME (ET)", "VOLUME"].enumerated()), id: \.offset) { column, title in
                        tableCell(title, column: column, header: true)
                    }
                }.fixedSize(horizontal: false, vertical: true)
                    .background(AppColor.hunterGreen)
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.key) { index, market in
                        Button { detail = market } label: {
                            HStack(spacing: 0) {
                                tableCell(market.question, column: 0)
                                tableCell(market.percent, column: 1, color: AppColor.hunterGreen)
                                tableCell(market.provider, column: 2, color: market.tint)
                                tableCell(market.category, column: 3)
                                tableCell(market.category == "Season" ? "—" : market.title, column: 4)
                                tableCell(market.date == nil ? "Season" : market.dayLabel, column: 5)
                                tableCell(market.date == nil ? "—" : market.timeLabel.replacingOccurrences(of: " ET", with: ""), column: 6)
                                tableCell(market.volume.map {
                                    $0.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) + " " + market.volumeUnit
                                } ?? "—", column: 7)
                            }.fixedSize(horizontal: false, vertical: true)
                                .background(index.isMultiple(of: 2) ? AppColor.paper : AppColor.cream)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(AppColor.border).frame(height: 0.5)
                                }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(market.question), \(market.provider), \(market.percent), \(market.category), \(market.dayLabel)")
                            .accessibilityHint("Opens the full question, price history, and market rules")
                    }
                }
            }
        }
        .background(AppColor.paper)
        .overlay(Rectangle().stroke(AppColor.border, lineWidth: 1))
    }
    private var methodology: some View {
        DisclosureGroup("How to read these markets") {
            Text("A 60% price means the market prices that outcome at roughly 60 cents per dollar of potential payout; it is not a guarantee. Kalshi probabilities use the midpoint of a two-sided bid/ask quote. Polymarket probabilities use its published outcome prices. Charts show hourly observations, and movement is measured in percentage points across the available history. Volume is shown in each provider’s own units and should not be added together. Quotes refresh about every two minutes while this page is open. This is an informational market-data view.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
        }.font(.subheadline.weight(.semibold)).tint(AppColor.hunterGreen)
            .padding(16).background(AppColor.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MarketTrend: View {
    let markets: [YankeesMarket]
    let store: MarketsStore
    @State private var days = 1
    @State private var selectedDate: Date?
    private var chartDomain: ClosedRange<Double> {
        let values = markets.flatMap { points($0).map { $0.p * 100 } }
        let lower = max(0, floor(((values.min() ?? 0) - 5) / 5) * 5)
        let upper = min(100, ceil(((values.max() ?? 100) + 5) / 5) * 5)
        return lower...max(lower + 1, upper)
    }
    private var identity: String { markets.map(\.key).joined() + String(days) + (store.snapshot?.generatedAt ?? "") }
    private func points(_ m: YankeesMarket) -> [MarketPoint] { store.histories[store.historyKey(m, days: days)] ?? [] }
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
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
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
                .frame(height: 200)
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
    let market: YankeesMarket
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

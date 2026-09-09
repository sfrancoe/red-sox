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
    var tint: Color { provider == "Kalshi" ? AppColor.positive : AppColor.accent }
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

private enum ResolveWindow: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month
    case seasonEnd

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Any time"
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        case .seasonEnd: "By season end"
        }
    }
}

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
        return AppBackend.apiURL("redsox-markets")
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
    @State private var resolveWindow: ResolveWindow = .today
    @State private var volumeOnly = true
    @State private var detail: SoxMarket?
    private var markets: [SoxMarket] { store.snapshot?.markets ?? [] }
    private var filtered: [SoxMarket] {
        markets.filter { market in
            matchesResolveWindow(market) && (!volumeOnly || (market.volume ?? 0) > 10_000)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let snapshot = store.snapshot {
                    sourceWarnings(snapshot)
                    octoberWatch
                        .padding(.top, width >= 650 ? 28 : 20)
                    marketBoard
                } else if store.loading {
                    ProgressView("Finding Red Sox markets…").tint(AppColor.ink).foregroundStyle(AppColor.ink).frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ContentUnavailableView("Markets unavailable", systemImage: "chart.line.downtrend.xyaxis", description: Text(store.error ?? "Refresh to load the latest markets.")).foregroundStyle(AppColor.ink)
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(AppColor.ink)
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
            if ProcessInfo.processInfo.arguments.contains("-market-season") { resolveWindow = .seasonEnd }
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

    private func sourceWarnings(_ snapshot: MarketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(snapshot.sources.filter { !$0.available }, id: \.name) { source in
                Label("\(source.name) unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(AppColor.ink)
            }
        }
    }

    private var octoberWatch: some View {
        let picks = markets.filter { $0.provider == "Polymarket" && $0.category == "Season" && ($0.question.contains("World Series") || $0.question.contains("clinch a spot") || $0.question.contains("AL East title")) }
        return VStack(spacing: 0) {
            if !picks.isEmpty {
                HStack(spacing: 0) {
                    Text("MARKET")
                    Spacer()
                    Text("CHANCE")
                        .frame(width: 72, alignment: .trailing)
                    Text("7D Chg")
                        .frame(width: 96, alignment: .trailing)
                }
                .font(.caption2.bold())
                .foregroundStyle(AppColor.ink)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(AppColor.accentSoft)
                ForEach(Array(picks.enumerated()), id: \.element.key) { index, market in
                    Button { detail = market } label: {
                        HStack(spacing: 0) {
                            Text(market.question.contains("World Series") ? "Win the World Series" : market.question.contains("AL East") ? "Win the AL East" : "Reach the postseason")
                                .foregroundStyle(AppColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                            Text(market.percent).monospacedDigit()
                                .foregroundStyle(AppColor.hunterGreen)
                                .padding(.horizontal, 8)
                                .frame(width: 72, alignment: .trailing)
                                .frame(maxHeight: .infinity)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(AppColor.separator).frame(width: 0.5)
                                }
                            sevenDayChange(for: market)
                                .padding(.horizontal, 8)
                                .frame(width: 96, alignment: .trailing)
                                .frame(maxHeight: .infinity)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(AppColor.separator).frame(width: 0.5)
                                }
                        }
                        .font(.caption)
                        .frame(minHeight: 40)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(index.isMultiple(of: 2) ? AppColor.paper : AppColor.cream)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AppColor.separator).frame(height: 0.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens price history and market rules")
                }
            }
        }
        .overlay {
            if !picks.isEmpty { Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth) }
        }
        .task(id: store.snapshot?.generatedAt) {
            for market in picks { await store.loadHistory(market, days: 7) }
        }
    }

    @ViewBuilder
    private func sevenDayChange(for market: SoxMarket) -> some View {
        let key = store.historyKey(market, days: 7)
        let history = store.histories[key] ?? []
        if let first = history.first, let last = history.last, history.count >= 2 {
            let change = (last.p - first.p) * 100
            let symbol = change > 0 ? "arrow.up" : change < 0 ? "arrow.down" : "minus"
            let color: Color = change > 0 ? .green : change < 0 ? .red : .secondary
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(String(format: "%.1f", abs(change))).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "7-day change %@ %.1f percentage points", change > 0 ? "up" : change < 0 ? "down" : "unchanged at", abs(change)))
        } else if store.pending.contains(key) {
            ProgressView().controlSize(.mini)
                .accessibilityLabel("Loading 7-day change")
        } else {
            Text("—").foregroundStyle(AppColor.ink)
                .accessibilityLabel("7-day change unavailable")
        }
    }

    private var marketBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Resolves")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.navy)
                Spacer()
                Picker("Resolves", selection: $resolveWindow) {
                    ForEach(ResolveWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.hunterGreen)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(AppColor.paper)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth))
            .panelElevation()

            Toggle("Volume over 10K", isOn: $volumeOnly)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppColor.navy)
                .tint(AppColor.hunterGreen)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(AppColor.paper)
                .clipShape(Rectangle())
                .overlay(Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth))
                .panelElevation()

            if filtered.isEmpty {
                ContentUnavailableView("No markets resolve then", systemImage: "calendar", description: Text("Try another resolve window. New markets appear as they are listed.")).foregroundStyle(AppColor.ink)
            }
            if !filtered.isEmpty {
                Text("Tap for details · Swipe for more")
                    .font(.caption2)
                    .foregroundStyle(AppColor.ink.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                marketTable
            }
        }
    }
    // One shared column layout keeps headers and values aligned at every width.
    private var marketColumnWidths: [CGFloat] {
        [190, 72, 100, 150, 120, 100, 130]
    }
    private func tableCell(_ text: String, column: Int, header: Bool = false,
                           color: Color = AppColor.ink) -> some View {
        Text(text)
            .font(header ? .caption2.weight(.bold) : .caption)
            .monospacedDigit()
            .foregroundStyle(AppColor.ink)
            .lineLimit(column == 0 && !header ? 2 : 1)
            .frame(width: marketColumnWidths[column] - 16,
                   alignment: column == 1 || column == 6 ? .trailing : .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, header ? 0 : 6)
            .frame(minHeight: header ? 30 : 48)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppColor.separator)
                    .frame(width: 0.5)
            }
    }
    private var marketTable: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(["MARKET", "CHANCE", "SOURCE", "GAME", "DATE", "TIME (ET)", "VOLUME"].enumerated()), id: \.offset) { column, title in
                        tableCell(title, column: column, header: true)
                    }
                }.fixedSize(horizontal: false, vertical: true)
                    .background(AppColor.accentSoft)
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.key) { index, market in
                        Button { detail = market } label: {
                            HStack(spacing: 0) {
                                tableCell(market.question, column: 0)
                                tableCell(market.percent, column: 1, color: AppColor.hunterGreen)
                                tableCell(market.provider, column: 2, color: market.tint)
                                tableCell(market.category == "Season" ? "—" : market.title, column: 3)
                                tableCell(market.date == nil ? "Season" : market.dayLabel, column: 4)
                                tableCell(market.date == nil ? "—" : market.timeLabel.replacingOccurrences(of: " ET", with: ""), column: 5)
                                tableCell(market.volume.map {
                                    $0.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) + " " + market.volumeUnit
                                } ?? "—", column: 6)
                            }.fixedSize(horizontal: false, vertical: true)
                                .background(index.isMultiple(of: 2) ? AppColor.paper : AppColor.cream)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(AppColor.separator).frame(height: 0.5)
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
        .overlay(Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth))
        .panelElevation()
    }

    private func matchesResolveWindow(_ market: SoxMarket) -> Bool {
        guard resolveWindow != .all else { return true }
        guard let date = market.date.flatMap(marketDate) else {
            return resolveWindow == .seasonEnd
        }

        let calendar = marketCalendar
        let now = Date()
        switch resolveWindow {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return interval.contains(date)
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .seasonEnd:
            let year = calendar.component(.year, from: now)
            let seasonEnd = calendar.date(from: DateComponents(year: year, month: 10, day: 31)) ?? .distantFuture
            return date <= seasonEnd
        }
    }

    private func marketDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = marketCalendar
        formatter.timeZone = marketCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private var marketCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private var methodology: some View {
        DisclosureGroup("How to read these markets") {
            Text("A 60% price means the market prices that outcome at roughly 60 cents per dollar of potential payout; it is not a guarantee. Kalshi probabilities use the midpoint of a two-sided bid/ask quote. Polymarket probabilities use its published outcome prices. Charts show hourly observations, and movement is measured in percentage points across the available history. Volume is shown in each provider’s own units and should not be added together. Quotes refresh about every two minutes while this page is open. This is an informational market-data view.")
                .font(.footnote).foregroundStyle(AppColor.ink).padding(.top, 8)
        }.font(.subheadline.weight(.semibold)).tint(AppColor.hunterGreen)
            .padding(16).background(AppColor.paper)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth))
            .panelElevation()
    }
}

private struct MarketTrend: View {
    let markets: [SoxMarket]
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
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if let selectedDate {
                        RuleMark(x: .value("Selected", selectedDate)).foregroundStyle(AppColor.ink).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
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
                        Text("\(market.provider) · \(nearest.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f%%", nearest.p * 100))").font(.caption).foregroundStyle(AppColor.ink)
                    } else if let first = history.first, let last = history.last, history.count >= 2 {
                        Text(String(format: "%@  %+.1f pts across available history", market.provider, (last.p-first.p)*100)).font(.caption.weight(.semibold)).foregroundStyle(AppColor.ink)
                    }
                }
            } else if markets.contains(where: { store.pending.contains(store.historyKey($0, days: days)) }) {
                ProgressView("Loading price history…").frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Label("Not enough price history yet", systemImage: "chart.xyaxis.line").foregroundStyle(AppColor.ink).frame(maxWidth: .infinity, minHeight: 130)
            }
            ForEach(markets.filter { points($0).count < 2 && store.histories[store.historyKey($0, days: days)] != nil }, id: \.key) { m in
                Text("\(m.provider): insufficient history in this window").font(.caption).foregroundStyle(AppColor.ink)
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
                    Text(market.provider.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(AppColor.ink)
                    Text(market.question).font(.title.bold())
                    HStack(alignment: .firstTextBaseline) {
                        Text(market.percent).font(.system(size: 52, weight: .black, design: .rounded))
                        Text(market.outcome).font(.headline).foregroundStyle(AppColor.ink)
                    }.foregroundStyle(AppColor.hunterGreen)
                    Text("Snapshot price · \(market.dayLabel)").font(.caption).foregroundStyle(AppColor.ink)
                    if let date = store.snapshot?.date { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(AppColor.ink) }
                    MarketTrend(markets: [market], store: store)
                    if let bid = market.bid, let ask = market.ask {
                        HStack {
                            quote("Bid", bid); Spacer(); quote("Ask", ask); Spacer(); quote("Spread", max(0, ask-bid))
                        }.padding().background(AppColor.cream).clipShape(Rectangle())
                    }
                    Text("What resolves this market?").font(.headline)
                    Text(market.rules).font(.subheadline).foregroundStyle(AppColor.ink).textSelection(.enabled)
                    if let url = URL(string: market.url) { Link("Source & full market rules ↗", destination: url).font(.headline).tint(market.tint) }
                }.padding(24)
            }.navigationTitle("Market detail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func quote(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption).foregroundStyle(AppColor.ink); Text(String(format: "%.1f¢", value*100)).font(.headline).monospacedDigit() }
    }
}

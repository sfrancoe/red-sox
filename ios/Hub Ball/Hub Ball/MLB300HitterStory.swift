import SwiftUI

private enum HitterStyle {
    static let paper = AppColor.bone
    static let navy = AppColor.night
    static let coral = Color(hubHex: "#BC6259")
    static let gold = Color(hubHex: "#B47B20")
    static let coralInk = Color(hubHex: "#933E38")
    static let goldInk = Color(hubHex: "#775014")
}

struct MLB300HitterStory: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var launched = false
    @State private var building = false
    @State private var startedAt: TimeInterval = 0
    @State private var playbackID = UUID()
    @State private var cardFlashTrigger = 0
    @State private var selectedIndex = MLB300HitterData.seasons.count - 1
    @State private var showMethodology = false

    private var finish: MLB300HitterData.Season { MLB300HitterData.finish }
    private var peak: MLB300HitterData.Season { MLB300HitterData.peak }

    var body: some View {
        GeometryReader { window in
            let compact = window.size.height < 720 && !typeSize.usesExpandedReadingLayout
            ZStack {
                HitterStyle.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 12 : 22) {
                        Text("The vanishing .300 hitter")
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("Seven qualified hitters finished at .300 or higher in 2026.")
                            .font(compact ? .subheadline : .title3).foregroundStyle(HitterStyle.navy.opacity(0.72))
                        StoryStatCards(expanded: typeSize.usesExpandedReadingLayout, compact: compact, flashTrigger: cardFlashTrigger)
                        Text("QUALIFIED HITTERS · .300 OR HIGHER")
                            .font(.caption.weight(.bold)).tracking(1)
                        ZStack(alignment: .bottom) {
                            TimelineView(.animation(paused: !building)) { _ in
                                let elapsed = building ? ProcessInfo.processInfo.systemUptime - startedAt : (launched ? MLB300HitterData.duration : 0)
                                Animated300LineChart(elapsed: elapsed, selectedIndex: $selectedIndex)
                            }
                            if launched && !building {
                                Button(action: launch) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(HitterStyle.coral, in: Circle())
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Replay chart animation")
                                .accessibilityIdentifier("hitter.replay")
                                .padding(.bottom, compact ? 22 : 26)
                            }
                        }
                        .frame(height: compact ? 220 : 280)
                        Text("In \(String(peak.year)), \(peak.count) qualified hitters finished at .300 or higher. In 2026, only \(finish.count) did—matching 2024 and 2025.")
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                        Button("How we count · methodology") { showMethodology = true }
                            .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("hitter.methodology")
                    }
                    .padding(compact ? 16 : 22)
                    .frame(maxWidth: 740, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                masthead.padding(.horizontal, 22).background(HitterStyle.paper)
            }
            .foregroundStyle(HitterStyle.navy)
            .tint(HitterStyle.coral)
            .preferredColorScheme(.light)
            .onAppear {
                if !launched { launch() }
            }
            .task(id: playbackID) {
                guard building else { return }
                let remaining = max(0, MLB300HitterData.duration - (ProcessInfo.processInfo.systemUptime - startedAt))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled else { return }
                building = false
                cardFlashTrigger += 1
            }
            .onDisappear { building = false }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { building = false }
            }
            .sheet(isPresented: $showMethodology) { methodology }
        }
    }

    private var masthead: some View {
        HStack {
            Text("HUB BALL / STORIES")
                .font(.caption.monospaced().weight(.bold)).tracking(1.5)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close story").accessibilityIdentifier("hitter.close")
        }
    }

    private func launch() {
        cardFlashTrigger = 0
        selectedIndex = MLB300HitterData.seasons.count - 1
        startedAt = ProcessInfo.processInfo.systemUptime
        launched = true
        building = !reduceMotion
        playbackID = UUID()
    }

    private var methodology: some View {
        NavigationStack {
            List {
                Section(".300 or higher—including exactly .300") {
                    Text("Hitters whose official, three-decimal batting average is .300 or higher are counted. A player displayed at exactly .300 is included. We use MLB’s displayed average rather than comparing an unrounded fraction.")
                }
                Section("Qualification") {
                    Text("We use MLB’s qualified-hitter leaderboard for each season. The normal batting-title threshold is 3.1 plate appearances per team game. MLB determines qualification for shortened seasons and any batting-title exceptions.")
                    Text("Each player is counted once using his full MLB season totals, including combined totals when he changes teams. The cutoff is applied to MLB’s officially displayed batting average.")
                }
                Section("The series") {
                    Text("Source: MLB Stats API qualified-hitter season totals, recalculated for every final regular season from 1976 through 2026 using the inclusive .300 cutoff.")
                    Text("The decline is rounded to the nearest whole percent: (\(peak.count) − \(finish.count)) ÷ \(peak.count) = \(MLB300HitterData.decline)%. The chart shows player counts, not the share of qualified hitters; MLB’s number of teams has changed over this period.")
                    Text("MLB’s final 2026 qualified-hitter totals were verified on September 29, 2026. Seven players finished with a displayed average of .300 or higher. The data in this story does not update automatically.")
                    Link("MLB 2026 batting-average leaderboard", destination: URL(string: "https://www.mlb.com/stats/batting-average/2026")!)
                }
                Section("Every season") {
                    ForEach(MLB300HitterData.seasons) { season in
                        LabeledContent(season.label, value: "\(season.count) players")
                    }
                }
            }
            .navigationTitle("How we count")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMethodology = false } } }
        }
    }
}

private enum StoryRoster: String, Identifiable {
    case peak, latest
    var id: String { rawValue }
}

private struct StoryStatCards: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let expanded: Bool
    var compact = false
    let flashTrigger: Int
    @State private var selectedRoster: StoryRoster?
    @State private var flashingRoster: StoryRoster?

    var body: some View {
        let layout = expanded ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            Button { selectedRoster = .peak } label: {
                card("Peak · \(String(MLB300HitterData.peak.year))", value: "\(MLB300HitterData.peak.count)", color: HitterStyle.coralInk, flashColor: HitterStyle.coral, highlighted: flashingRoster == .peak, tappable: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Peak \(MLB300HitterData.peak.count) hitters in \(MLB300HitterData.peak.year). Tap to see who")
            .accessibilityIdentifier("hitter.card.peak")
            Button { selectedRoster = .latest } label: {
                card(MLB300HitterData.finish.label, value: "\(MLB300HitterData.finish.count)", color: HitterStyle.goldInk, flashColor: HitterStyle.gold, highlighted: flashingRoster == .latest, tappable: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(MLB300HitterData.finish.count) hitters in \(MLB300HitterData.finish.label). Tap to see who")
            .accessibilityIdentifier("hitter.card.latest")
            card("vs Peak", value: "−\(MLB300HitterData.decline)%", color: HitterStyle.navy, flashColor: HitterStyle.navy, highlighted: false, tappable: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Down \(MLB300HitterData.decline) percent from the peak")
        }
        .sheet(item: $selectedRoster) { roster in
            StoryRosterSheet(roster: roster)
                .presentationDetents([.large])
        }
        .task(id: flashTrigger) {
            flashingRoster = nil
            guard flashTrigger > 0, !reduceMotion else { return }
            do {
                for roster in [StoryRoster.peak, .latest] {
                    for _ in 0..<3 {
                        withAnimation(.easeInOut(duration: 0.2)) { flashingRoster = roster }
                        try await Task.sleep(for: .milliseconds(500))
                        withAnimation(.easeInOut(duration: 0.2)) { flashingRoster = nil }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                }
            } catch {
                flashingRoster = nil
            }
        }
    }

    private func card(_ title: String, value: String, color: Color, flashColor: Color, highlighted: Bool, tappable: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2.weight(.semibold))
            Text(value).font(.system(.title2, design: .serif).weight(.bold)).foregroundStyle(color)
            Text("Tap to see who").font(.caption2).foregroundStyle(HitterStyle.navy.opacity(0.85))
                .opacity(tappable ? 1 : 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 7 : 9)
        .background(highlighted ? flashColor.opacity(0.23) : .white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(highlighted ? flashColor.opacity(0.8) : .clear, lineWidth: 2))
    }
}

private struct StoryRosterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let roster: StoryRoster

    private var players: [MLB300HitterPlayers.Player] {
        roster == .peak ? MLB300HitterPlayers.peak : MLB300HitterPlayers.latest
    }
    private var title: String {
        roster == .peak
            ? "\(MLB300HitterPlayers.peakYear) · \(players.count) hitters"
            : "\(MLB300HitterPlayers.latestYear) · \(players.count) hitters"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").foregroundStyle(HitterStyle.navy.opacity(0.5))
                                .frame(width: 26, alignment: .leading)
                            HStack(spacing: 6) {
                                Text(player.name).lineLimit(1).minimumScaleFactor(0.8)
                                Text(player.team)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HitterStyle.navy.opacity(0.55))
                            }
                            Spacer(minLength: 8)
                            Text(player.average).monospacedDigit().fontWeight(.semibold)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(index + 1). \(player.name), \(player.team), batting average \(player.average)")
                        .accessibilityIdentifier("hitter.roster.row.\(index + 1)")
                    }
                } header: {
                    Text("Qualified hitters · AVG highest first")
                } footer: {
                    Text(roster == .latest ? MLB300HitterData.finalSeasonLabel : "Final 1999 regular season")
                }
            }
            .scrollContentBackground(.hidden)
            .background(HitterStyle.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct Animated300LineChart: View {
    let elapsed: TimeInterval
    @Binding var selectedIndex: Int
    private let seasons = MLB300HitterData.seasons

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(x: 27, y: 42, width: max(1, geometry.size.width - 43), height: geometry.size.height - 76)
            let points = seasons.enumerated().map { index, season in
                CGPoint(x: rect.minX + CGFloat(index) / CGFloat(seasons.count - 1) * rect.width,
                        y: rect.maxY - CGFloat(season.count) / 60 * rect.height)
            }
            let progress = MLB300HitterData.progress(elapsed: elapsed)
            ZStack(alignment: .topLeading) {
                ForEach([0, 20, 40, 60], id: \.self) { count in
                    let y = rect.maxY - CGFloat(count) / 60 * rect.height
                    Path { p in p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)) }
                        .stroke(HitterStyle.navy.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Text("\(count)").font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(HitterStyle.navy).position(x: 10, y: y)
                }
                Path { path in path.addLines(points) }
                    .trim(from: 0, to: progress)
                    .stroke(HitterStyle.coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if progress >= 1 {
                    ForEach(seasons.indices.filter { $0 == MLB300HitterData.peakIndex || $0 == seasons.count - 1 || $0 == selectedIndex }, id: \.self) { index in
                        Circle()
                            .fill(index == seasons.count - 1 ? HitterStyle.gold : HitterStyle.coral)
                            .frame(width: index == selectedIndex ? 10 : 5, height: index == selectedIndex ? 10 : 5)
                            .position(points[index])
                    }
                }
                if elapsed >= MLB300HitterData.duration / 2 {
                    callout("\(String(MLB300HitterData.peak.year)) · \(MLB300HitterData.peak.count) players", color: HitterStyle.coral)
                        .position(x: points[MLB300HitterData.peakIndex].x, y: points[MLB300HitterData.peakIndex].y - 23)
                }
                if progress >= 1 {
                    Path { path in
                        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 47))
                        path.addLine(to: points.last!)
                    }
                    .stroke(HitterStyle.gold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    callout("\(MLB300HitterData.finish.label) · \(MLB300HitterData.finish.count) players", color: HitterStyle.gold)
                        .position(x: rect.maxX - 65, y: rect.minY + 32)
                }
                if selectedIndex != MLB300HitterData.peakIndex && selectedIndex != seasons.count - 1 {
                    let selected = seasons[selectedIndex]
                    callout("\(selected.label) · \(selected.count) players", color: HitterStyle.navy)
                        .position(x: min(rect.maxX - 53, max(rect.minX + 53, points[selectedIndex].x)),
                                  y: min(rect.maxY - 12, points[selectedIndex].y + 25))
                }
                ForEach([0, 14, 24, 34, seasons.count - 1], id: \.self) { index in
                    Text(seasons[index].label).font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(HitterStyle.navy).position(x: points[index].x, y: rect.maxY + 20)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in select(value.location.x, rect: rect) })
            .onContinuousHover { phase in
                if case let .active(location) = phase { select(location.x, rect: rect) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Qualified hitters at .300 or higher, 1976 through \(MLB300HitterData.finish.label). Peak \(MLB300HitterData.peak.count) in \(String(MLB300HitterData.peak.year)); seven in 2025 and seven in the final 2026 regular season.")
            .accessibilityValue("\(seasons[selectedIndex].label): \(seasons[selectedIndex].count) qualified hitters")
            .accessibilityHint("Tap the chart to select a year, or swipe up and down with VoiceOver.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selectedIndex = min(seasons.count - 1, selectedIndex + 1)
                case .decrement: selectedIndex = max(0, selectedIndex - 1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("hitter.chart")
        }
    }

    private func select(_ x: CGFloat, rect: CGRect) {
        selectedIndex = min(seasons.count - 1, max(0, Int(((x - rect.minX) / rect.width * CGFloat(seasons.count - 1)).rounded())))
    }

    private func callout(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            .padding(5).background(HitterStyle.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
    }
}

import SwiftUI

struct PitchingView: View {
    @State private var store = PitchingStore()

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if let feed = store.feed {
                    pitchingContent(feed)
                } else if store.isLoading {
                    ProgressView("Loading pitching…")
                        .tint(AppColor.red)
                } else {
                    errorView
                }
            }
        }
        .navigationTitle("Pitching")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
        }
    }

    private func pitchingContent(_ feed: PitchingFeed) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                rolePicker

                impactCard

                HStack(alignment: .center) {
                    Text("\(store.filter == .starters ? "Starter" : "Reliever") Reports")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)

                    Spacer()

                    Picker("Report order", selection: $store.sort) {
                        ForEach(PitcherSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.white)
                }

                ForEach(Array(store.visiblePitchers.enumerated()), id: \.element.id) { index, pitcher in
                    pitcherCard(pitcher, rank: index + 1)
                }

                sourcesNote(feed)
            }
            .padding(16)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private var rolePicker: some View {
        HStack(spacing: 5) {
            ForEach(PitcherFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        store.filter = filter
                    }
                } label: {
                    Text(filter.title.uppercased())
                        .font(.system(size: 13, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(store.filter == filter ? AppColor.green : AppColor.hunterGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    store.filter == filter ? Color.white : Color.white.opacity(0.2),
                                    lineWidth: store.filter == filter ? 2 : 0.8
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(AppColor.hunterGreen)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO MOVED THE SEASON?")
                .font(.caption.weight(.black))
                .tracking(0.8)
                .foregroundStyle(AppColor.green)
            Text("Actual fWAR ↑  ·  Forecast by now →")
                .font(.caption)
                .foregroundStyle(.secondary)

            PitchingImpactChart(pitchers: store.visiblePitchers)
                .frame(height: 270)

            HStack(spacing: 14) {
                Label("Above forecast", systemImage: "circle.fill")
                    .foregroundStyle(AppColor.red)
                Label("Below forecast", systemImage: "circle.fill")
                    .foregroundStyle(AppColor.green.opacity(0.75))
            }
            .font(.caption2.weight(.bold))
        }
        .cardStyle()
    }

    private func pitcherCard(_ pitcher: PitcherReport, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(store.sort.title.uppercased()) RANK \(rank)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(AppColor.red)
                    Text(pitcher.name)
                        .font(.headline)
                        .foregroundStyle(AppColor.navy)
                    Text("\(pitcher.handedness) · \(pitcher.role) · \(pitcher.games) G\(pitcher.starts > 0 ? " · \(pitcher.starts) GS" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(pitcher.warGap.signedText) fWAR")
                    .font(.subheadline.monospacedDigit().weight(.black))
                    .foregroundStyle(pitcher.warGap >= 0 ? AppColor.green : AppColor.red)
            }

            Text(pitcher.story)
                .font(.subheadline)
                .lineSpacing(2)

            forecastTrack(actual: pitcher.actual.war, forecast: pitcher.forecastToDate.war)

            comparisonTable(pitcher)
        }
        .cardStyle()
    }

    private func forecastTrack(actual: Double, forecast: Double) -> some View {
        GeometryReader { geometry in
            let maximum = max(actual, forecast, 0.35) * 1.12
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.paleBlue)
                Capsule()
                    .fill(AppColor.red)
                    .frame(width: geometry.size.width * max(actual, 0) / maximum)
                Rectangle()
                    .fill(AppColor.navy)
                    .frame(width: 2, height: 15)
                    .offset(x: geometry.size.width * max(forecast, 0) / maximum)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func comparisonTable(_ pitcher: PitcherReport) -> some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("ACTUAL")
                Text("FORECAST")
            }
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)

            comparisonRow("fWAR", pitcher.actual.war.twoPlaces, pitcher.forecastToDate.war.twoPlaces)
            comparisonRow("Innings", pitcher.actual.ip, pitcher.forecastToDate.ip.onePlace)
            comparisonRow("ERA", pitcher.actual.era.twoPlaces, pitcher.forecast?.era.twoPlaces ?? "—")
            comparisonRow("FIP", pitcher.actual.fip.twoPlaces, pitcher.forecast?.fip.twoPlaces ?? "—")
            comparisonRow("K−BB%", "\(pitcher.actual.kMinusBbPct.onePlace)%", pitcher.forecast.map { "\($0.kMinusBbPct.onePlace)%" } ?? "—")
        }
        .font(.caption.monospacedDigit())
    }

    private func comparisonRow(_ label: String, _ actual: String, _ forecast: String) -> some View {
        GridRow {
            Text(label)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(actual)
            Text(forecast)
                .foregroundStyle(.secondary)
        }
    }

    private func sourcesNote(_ feed: PitchingFeed) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Forecast by now prorates each pitcher’s preseason Steamer projection to Boston’s games played. Actual value is FanGraphs fWAR.")
            Text("Updated \(feed.updatedText) · FanGraphs + MLB")
        }
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.82))
        .padding(.vertical, 8)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Pitching Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The pitching outlook could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.red)
        }
    }
}

private struct PitchingImpactChart: View {
    let pitchers: [PitcherReport]

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 28, y: 16, width: max(size.width - 38, 1), height: max(size.height - 40, 1))
            let minimum = -0.2
            let xMaximum = max(1, pitchers.map(\.forecastToDate.war).max() ?? 1) * 1.1
            let yMaximum = max(1, pitchers.map(\.actual.war).max() ?? 1) * 1.1

            func x(_ value: Double) -> CGFloat {
                plot.minX + CGFloat((value - minimum) / (xMaximum - minimum)) * plot.width
            }
            func y(_ value: Double) -> CGFloat {
                plot.maxY - CGFloat((value - minimum) / (yMaximum - minimum)) * plot.height
            }

            for tick in 0...Int(ceil(max(xMaximum, yMaximum))) {
                let value = Double(tick)
                if value <= yMaximum {
                    var horizontal = Path()
                    horizontal.move(to: CGPoint(x: plot.minX, y: y(value)))
                    horizontal.addLine(to: CGPoint(x: plot.maxX, y: y(value)))
                    context.stroke(horizontal, with: .color(AppColor.border), lineWidth: 0.8)
                    context.draw(
                        Text("\(tick)").font(.system(size: 8)).foregroundStyle(.secondary),
                        at: CGPoint(x: plot.minX - 7, y: y(value)),
                        anchor: .trailing
                    )
                }
            }

            var parity = Path()
            parity.move(to: CGPoint(x: x(minimum), y: y(minimum)))
            let parityMax = min(xMaximum, yMaximum)
            parity.addLine(to: CGPoint(x: x(parityMax), y: y(parityMax)))
            context.stroke(
                parity,
                with: .color(AppColor.navy.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])
            )

            let labels = Set(
                pitchers.sorted {
                    ($0.actual.war + abs($0.warGap)) > ($1.actual.war + abs($1.warGap))
                }.prefix(8).map(\.id)
            )

            for pitcher in pitchers.sorted(by: { $0.actual.ipValue > $1.actual.ipValue }) {
                let point = CGPoint(x: x(pitcher.forecastToDate.war), y: y(pitcher.actual.war))
                let radius = min(10, 3.5 + sqrt(pitcher.actual.ipValue) * 0.42)
                let pointColor = pitcher.warGap >= 0 ? AppColor.red : AppColor.green.opacity(0.75)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(pointColor)
                )

                if labels.contains(pitcher.id) {
                    context.draw(
                        Text(pitcher.name.split(separator: " ").last.map(String.init) ?? pitcher.name)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppColor.navy),
                        at: CGPoint(x: point.x + radius + 3, y: point.y),
                        anchor: .leading
                    )
                }
            }
        }
        .accessibilityLabel("Actual pitching fWAR compared with forecast fWAR")
    }
}

private extension Double {
    var signedText: String {
        let value = onePlace
        return self >= 0 ? "+\(value)" : value
    }

    var onePlace: String {
        formatted(.number.precision(.fractionLength(1)))
    }

    var twoPlaces: String {
        formatted(.number.precision(.fractionLength(2)))
    }
}

#Preview {
    NavigationStack {
        PitchingView()
    }
}

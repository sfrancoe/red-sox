import SwiftUI

struct PitchingView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = PitchingStore()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let feed = store.feed {
                        pitchingContent(feed, chartHeight: contentWidth >= 650 ? max(380, geometry.size.height * 0.55) : 270)
                    } else if store.isLoading {
                        ProgressView("Loading pitching…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    } else {
                        errorView
                    }
                }
            }
        }
        .navigationTitle("Pitching")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
        }
    }

    private func pitchingContent(_ feed: PitchingFeed, chartHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                rolePicker

                impactCard(chartHeight: chartHeight)

                HStack(alignment: .center) {
                    Text(store.filter.reportsTitle)
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

                HubCardGrid {
                    ForEach(Array(store.visiblePitchers.enumerated()), id: \.element.id) { index, pitcher in
                        pitcherCard(pitcher, rank: index + 1)
                    }
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
        HStack(spacing: 0) {
            ForEach(PitcherFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        store.filter = filter
                    }
                } label: {
                    Text(filter.title.uppercased())
                        .font(
                            .system(
                                size: store.filter == filter ? 16 : 13,
                                weight: store.filter == filter ? .black : .semibold
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.filter == filter ? .isSelected : [])
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
    }

    private func impactCard(chartHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label("Above forecast", systemImage: "circle.fill")
                    .foregroundStyle(AppColor.green)
                Label("Below forecast", systemImage: "circle.fill")
                    .foregroundStyle(AppColor.red)
            }
            .font(.system(size: 12, weight: .black))
            .frame(maxWidth: .infinity, alignment: .center)

            PitchingImpactChart(pitchers: store.visiblePitchers)
                .frame(height: chartHeight)
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
            Text("Forecast by now prorates each pitcher’s preseason Steamer projection to New York’s games played. Actual value is FanGraphs fWAR.")
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
    @Environment(\.hubContentWidth) private var contentWidth
    let pitchers: [PitcherReport]

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 40, y: 12, width: max(size.width - 50, 1), height: max(size.height - 42, 1))
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
                }.prefix(contentWidth >= 650 ? 10 : 8).map(\.id)
            )

            let dotFrames = pitchers.map { pitcher in
                let radius = min(10, 3.5 + sqrt(pitcher.actual.ipValue) * 0.42)
                return CGRect(x: x(pitcher.forecastToDate.war) - radius - 2,
                              y: y(pitcher.actual.war) - radius - 2,
                              width: radius * 2 + 4, height: radius * 2 + 4)
            }
            var occupiedLabelFrames: [CGRect] = []
            let maximumGap = max(pitchers.map { abs($0.warGap) }.max() ?? 0, 0.25)
            for pitcher in pitchers.sorted(by: { $0.actual.ipValue > $1.actual.ipValue }) {
                let point = CGPoint(x: x(pitcher.forecastToDate.war), y: y(pitcher.actual.war))
                let radius = min(10, 3.5 + sqrt(pitcher.actual.ipValue) * 0.42)
                let gapStrength = min(abs(pitcher.warGap) / maximumGap, 1)
                let pointColor = performanceColor(gap: pitcher.warGap, strength: gapStrength)
                let pointPath = Path(
                    ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                context.fill(pointPath, with: .color(pointColor))
                context.stroke(
                    pointPath,
                    with: .color(
                        (pitcher.warGap >= 0 ? AppColor.hunterGreen : AppColor.red).opacity(0.42)
                    ),
                    lineWidth: 0.8
                )

                if labels.contains(pitcher.id) {
                    let label = pitcher.name.split(separator: " ").last.map(String.init) ?? pitcher.name
                    let estimatedWidth = max(30, CGFloat(label.count) * 6.2)
                    var placement: (frame: CGRect, drawsLeft: Bool)?
                    for drawsLeft in [false, true] {
                        for offset: CGFloat in [0, -10, 10] {
                            let frame = CGRect(
                                x: drawsLeft ? point.x - radius - 5 - estimatedWidth : point.x + radius + 5,
                                y: point.y + offset - 6,
                                width: estimatedWidth, height: 12
                            )
                            guard plot.contains(frame),
                                  !dotFrames.contains(where: { $0.intersects(frame) }),
                                  !occupiedLabelFrames.contains(where: { $0.intersects(frame.insetBy(dx: -3, dy: -2)) }) else { continue }
                            placement = (frame, drawsLeft)
                            break
                        }
                        if placement != nil { break }
                    }
                    guard let placement else { continue }
                    occupiedLabelFrames.append(placement.frame)
                    let drawsLeft = placement.drawsLeft
                    let labelX = drawsLeft ? placement.frame.maxX : placement.frame.minX
                    let labelY = placement.frame.midY
                    context.draw(
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColor.navy),
                        at: CGPoint(x: labelX, y: labelY),
                        anchor: drawsLeft ? .trailing : .leading
                    )
                }
            }

            context.drawLayer { axisContext in
                axisContext.translateBy(x: 9, y: plot.midY)
                axisContext.rotate(by: .degrees(-90))
                axisContext.draw(
                    Text("ACTUAL fWAR")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(AppColor.navy),
                    at: .zero,
                    anchor: .center
                )
            }

            context.draw(
                Text("FORECAST BY NOW")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(AppColor.navy),
                at: CGPoint(x: plot.midX, y: size.height - 3),
                anchor: .bottom
            )
        }
        .accessibilityLabel("Actual pitching fWAR compared with forecast fWAR")
    }
}

private func performanceColor(gap: Double, strength: Double) -> Color {
    let amount = min(max(strength, 0), 1)
    let light: (red: Double, green: Double, blue: Double)
    let dark: (red: Double, green: Double, blue: Double)

    if gap >= 0 {
        light = (0.76, 0.89, 0.80)
        dark = (0.05, 0.29, 0.17)
    } else {
        light = (0.96, 0.79, 0.80)
        dark = (0.56, 0.06, 0.11)
    }

    return Color(
        red: light.red + (dark.red - light.red) * amount,
        green: light.green + (dark.green - light.green) * amount,
        blue: light.blue + (dark.blue - light.blue) * amount
    )
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

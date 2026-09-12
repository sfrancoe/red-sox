import SwiftUI

struct ChaseChart: View {
    let config: ChaseConfig
    let drawProgress: Double
    let morphProgress: Double
    let markerOpacity: Double
    let projection: [CumulativePoint]?
    let projectionProgress: Double
    let contractEndAge: Int?

    private let minimumAge = 17.0
    private let maximumAge = 43.0
    private let maximumHomeRuns = 800.0

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(
                x: 42,
                y: 24,
                width: max(size.width - 58, 1),
                height: max(size.height - 58, 1)
            )
            let maximumAtBats = max(
                1,
                config.players.flatMap { ChaseEngine.cumulative($0) }.map(\.ab).max() ?? 1
            )

            drawGrid(context: &context, plot: plot, maximumAtBats: maximumAtBats)

            for player in config.players {
                let points = ChaseEngine.cumulative(player)
                guard points.count > 1 else { continue }
                let fullPath = path(
                    points: points,
                    plot: plot,
                    maximumAtBats: maximumAtBats,
                    morph: morphProgress
                )
                let visiblePath = fullPath.trimmedPath(from: 0, to: min(max(drawProgress, 0), 1))
                context.stroke(
                    visiblePath,
                    with: .color(player.isSubject ? AppColor.amber : AppColor.boneMuted.opacity(0.64)),
                    style: StrokeStyle(
                        lineWidth: player.isSubject ? 3.2 : 1.6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if drawProgress > 0.98 {
                drawEndLabels(
                    context: &context,
                    plot: plot,
                    maximumAtBats: maximumAtBats
                )
            }

            if markerOpacity > 0 {
                drawAtBatMarker(
                    context: &context,
                    plot: plot,
                    maximumAtBats: maximumAtBats
                )
            }

            if let contractEndAge {
                drawContractMarker(context: &context, plot: plot, age: contractEndAge)
            }

            if let projection, projection.count > 1 {
                let projectedPath = path(
                    points: projection,
                    plot: plot,
                    maximumAtBats: maximumAtBats,
                    morph: 0
                ).trimmedPath(from: 0, to: min(max(projectionProgress, 0), 1))
                context.stroke(
                    projectedPath,
                    with: .color(AppColor.amber),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [7, 5])
                )
            }
        }
    }

    private func drawGrid(
        context: inout GraphicsContext,
        plot: CGRect,
        maximumAtBats: Double
    ) {
        for value in stride(from: 0, through: 800, by: 200) {
            let y = yPosition(Double(value), plot: plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(line, with: .color(AppColor.rule), lineWidth: value == 0 ? 1.2 : 0.7)
            context.draw(
                Text(String(value))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColor.boneMuted),
                at: CGPoint(x: plot.minX - 7, y: y),
                anchor: .trailing
            )
        }

        let recordY = yPosition(762, plot: plot)
        var record = Path()
        record.move(to: CGPoint(x: plot.minX, y: recordY))
        record.addLine(to: CGPoint(x: plot.maxX, y: recordY))
        context.stroke(
            record,
            with: .color(AppColor.amber.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
        context.draw(
            Text("762 · RECORD")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.amber),
            at: CGPoint(x: plot.minX + 5, y: recordY - 7),
            anchor: .leading
        )

        let isAtBatAxis = morphProgress >= 0.5
        let ticks = isAtBatAxis ? [0.0, 4_000, 8_000, 12_000] : [20.0, 30, 40]
        for tick in ticks {
            let x = isAtBatAxis
                ? xAtBats(tick, plot: plot, maximumAtBats: maximumAtBats)
                : xAge(tick, plot: plot)
            context.draw(
                Text(isAtBatAxis ? abbreviated(tick) : String(Int(tick)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColor.boneMuted),
                at: CGPoint(x: x, y: plot.maxY + 14),
                anchor: .center
            )
        }
        context.draw(
            Text(isAtBatAxis ? "CAREER AT-BATS" : "AGE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.boneDim),
            at: CGPoint(x: plot.midX, y: plot.maxY + 29),
            anchor: .center
        )
    }

    private func drawEndLabels(
        context: inout GraphicsContext,
        plot: CGRect,
        maximumAtBats: Double
    ) {
        struct Placement {
            let player: PlayerHRSeries
            let point: CGPoint
            var labelY: CGFloat
        }

        var placements = config.players.compactMap { player -> Placement? in
            guard let endpoint = ChaseEngine.cumulative(player).last else { return nil }
            let point = screenPoint(
                endpoint,
                plot: plot,
                maximumAtBats: maximumAtBats,
                morph: morphProgress
            )
            return Placement(player: player, point: point, labelY: point.y)
        }.sorted { $0.labelY < $1.labelY }

        for index in placements.indices where index > 0 {
            placements[index].labelY = max(placements[index].labelY, placements[index - 1].labelY + 14)
        }
        if let overflow = placements.last.map({ $0.labelY - plot.maxY }), overflow > 0 {
            for index in placements.indices {
                placements[index].labelY -= overflow
            }
        }

        for placement in placements {
            let color = placement.player.isSubject ? AppColor.amber : AppColor.boneDim
            context.fill(
                Path(ellipseIn: CGRect(
                    x: placement.point.x - 3,
                    y: placement.point.y - 3,
                    width: 6,
                    height: 6
                )),
                with: .color(color)
            )
            let total = Int((ChaseEngine.cumulative(placement.player).last?.hr ?? 0).rounded())
            let isNearRight = placement.point.x > plot.maxX - 80
            context.draw(
                Text("\(placement.player.name) \(total)")
                    .font(.system(size: 9, weight: placement.player.isSubject ? .bold : .medium))
                    .foregroundStyle(color),
                at: CGPoint(
                    x: placement.point.x + (isNearRight ? -7 : 7),
                    y: placement.labelY
                ),
                anchor: isNearRight ? .trailing : .leading
            )
        }
    }

    private func drawAtBatMarker(
        context: inout GraphicsContext,
        plot: CGRect,
        maximumAtBats: Double
    ) {
        let atBats = Double(config.subject.seasons.reduce(0) { $0 + $1.ab })
        let x = xAtBats(atBats, plot: plot, maximumAtBats: maximumAtBats)
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: plot.minY))
        marker.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.opacity = markerOpacity
        context.stroke(
            marker,
            with: .color(AppColor.amber),
            style: StrokeStyle(lineWidth: 1.4, dash: [4, 4])
        )
        context.draw(
            Text("\(Int(atBats).formatted()) AB")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.amber),
            at: CGPoint(x: x, y: plot.minY + 7),
            anchor: .bottom
        )

        for player in config.players {
            let hr = ChaseEngine.hr(for: player, at: atBats, axis: .atBats)
            let y = yPosition(hr, plot: plot)
            context.fill(
                Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                with: .color(player.isSubject ? AppColor.amber : AppColor.boneDim)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                with: .color(AppColor.nightRaised),
                lineWidth: 2
            )
        }
    }

    private func drawContractMarker(context: inout GraphicsContext, plot: CGRect, age: Int) {
        let x = xAge(Double(age), plot: plot)
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: plot.minY))
        marker.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(
            marker,
            with: .color(AppColor.boneMuted.opacity(0.45)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 5])
        )
        context.draw(
            Text("CONTRACT ENDS")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppColor.boneMuted),
            at: CGPoint(x: x - 4, y: plot.minY + 6),
            anchor: .topTrailing
        )
    }

    private func path(
        points: [CumulativePoint],
        plot: CGRect,
        maximumAtBats: Double,
        morph: Double
    ) -> Path {
        var result = Path()
        for (index, point) in points.enumerated() {
            let screen = screenPoint(
                point,
                plot: plot,
                maximumAtBats: maximumAtBats,
                morph: morph
            )
            if index == 0 { result.move(to: screen) } else { result.addLine(to: screen) }
        }
        return result
    }

    private func screenPoint(
        _ point: CumulativePoint,
        plot: CGRect,
        maximumAtBats: Double,
        morph: Double
    ) -> CGPoint {
        let age = xAge(point.age, plot: plot)
        let atBats = xAtBats(point.ab, plot: plot, maximumAtBats: maximumAtBats)
        return CGPoint(
            x: age + (atBats - age) * morph,
            y: yPosition(point.hr, plot: plot)
        )
    }

    private func xAge(_ value: Double, plot: CGRect) -> CGFloat {
        plot.minX + plot.width * (value - minimumAge) / (maximumAge - minimumAge)
    }

    private func xAtBats(_ value: Double, plot: CGRect, maximumAtBats: Double) -> CGFloat {
        plot.minX + plot.width * value / maximumAtBats
    }

    private func yPosition(_ value: Double, plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * value / maximumHomeRuns
    }

    private func abbreviated(_ value: Double) -> String {
        value == 0 ? "0" : "\(Int(value / 1_000))K"
    }
}

struct HomeRunShareCard: View {
    let config: ChaseConfig

    private var subjectAtBats: Int { config.subject.seasons.reduce(0) { $0 + $1.ab } }
    private var subjectTotal: Int { config.subject.seasons.reduce(0) { $0 + $1.hr } }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE HOME RUN CHASE")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(AppColor.amber)
                Text("AARON JUDGE")
                    .font(.system(size: 82, weight: .bold, design: .serif))
                    .foregroundStyle(AppColor.bone)
                Text("The same five careers. Two ways to count time.")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.boneDim)
            }

            shareChart(title: "BY AGE", morph: 0, marker: 0)
            shareChart(title: "BY AT-BATS", morph: 1, marker: 1)

            VStack(alignment: .leading, spacing: 14) {
                Text("APPROX. HR THROUGH \(subjectAtBats.formatted()) AT-BATS")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(AppColor.boneMuted)
                ForEach(config.players.sorted {
                    ChaseEngine.hr(for: $0, at: Double(subjectAtBats), axis: .atBats)
                        > ChaseEngine.hr(for: $1, at: Double(subjectAtBats), axis: .atBats)
                }) { player in
                    ChaseBar(
                        name: player.name,
                        value: ChaseEngine.hr(for: player, at: Double(subjectAtBats), axis: .atBats),
                        maximum: Double(subjectTotal),
                        accented: player.isSubject,
                        large: true
                    )
                    .padding(.bottom, 8)
                }
            }
            .padding(24)
            .background(AppColor.nightRaised)

            HStack(alignment: .bottom) {
                Text("Through the same \(subjectAtBats.formatted()) at-bats, nobody here had more.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColor.bone)
                Spacer()
                Text("HUB BALL")
                    .font(.system(size: 22, weight: .black))
                    .tracking(2)
                    .foregroundStyle(AppColor.amber)
            }
        }
        .padding(58)
        .background(AppColor.night)
    }

    private func shareChart(title: String, morph: Double, marker: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppColor.bone)
            ChaseChart(
                config: config,
                drawProgress: 1,
                morphProgress: morph,
                markerOpacity: marker,
                projection: nil,
                projectionProgress: 0,
                contractEndAge: nil
            )
            .frame(height: 390)
            .background(AppColor.nightRaised)
        }
    }
}

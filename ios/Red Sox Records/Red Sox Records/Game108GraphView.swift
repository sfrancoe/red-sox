import SwiftUI

struct Game108GraphView: View {
    @State private var store = Game108GraphStore()
    @State private var activeSeasonIndex = 0
    @State private var gameProgress = 0.0
    @State private var isPlaying = false
    @State private var speed = 2.0
    @State private var isMusicOn = true
    @State private var musicPlayer = GraphMusicPlayer()
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if !store.series.isEmpty {
                    graphContent
                } else if store.isLoading {
                    ProgressView("Loading Game 108…")
                        .tint(AppColor.red)
                } else {
                    errorView
                }
            }
        }
        .navigationTitle("Game 108 Graph")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private var graphContent: some View {
        GeometryReader { proxy in
            let chartHeight = max(260, min(430, proxy.size.height - 150))

            VStack(spacing: 10) {
                ZStack {
                    Game108Canvas(
                        series: store.series,
                        activeSeasonIndex: activeSeasonIndex,
                        gameProgress: gameProgress
                    )

                    if !isPlaying,
                       activeSeasonIndex == 0,
                       gameProgress == 0 {
                        Button {
                            startAnimation()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                Text("PLAY THE STORY")
                                    .font(.caption.weight(.black))
                                    .tracking(0.8)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                            .background(AppColor.red)
                            .clipShape(Capsule())
                            .shadow(color: AppColor.navy.opacity(0.22), radius: 12, y: 5)
                        }
                    }
                }
                .frame(height: chartHeight)
                .padding(10)
                .background(AppColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 1)
                }

                controls
                storyHeader
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(AppColor.ink)
        }
    }

    private var storyHeader: some View {
        Text("Four straight seasons with the same record after 108 games: 57–51. Where will 2026 go from here?")
            .font(.subheadline.weight(.bold))
            .italic()
            .foregroundStyle(.white)
            .lineSpacing(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    isPlaying ? pauseAnimation() : startAnimation()
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppColor.hunterGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    restartAnimation()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppColor.hunterGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    isMusicOn.toggle()
                    musicPlayer.setEnabled(isMusicOn)
                    if isMusicOn, isPlaying {
                        musicPlayer.play()
                    }
                } label: {
                    Label(
                        isMusicOn ? "Music On" : "Music Off",
                        systemImage: isMusicOn ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppColor.hunterGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 5) {
                Text("SPEED")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)

                ForEach([1.0, 2.0, 4.0], id: \.self) { option in
                    Button {
                        speed = option
                    } label: {
                        Text("\(Int(option))×")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(speed == option ? AppColor.green : AppColor.hunterGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        speed == option ? Color.white : Color.white.opacity(0.18),
                                        lineWidth: speed == option ? 2 : 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(AppColor.hunterGreen)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @MainActor
    private func startAnimation() {
        if activeSeasonIndex >= store.series.count {
            activeSeasonIndex = 0
            gameProgress = 0
        }

        isPlaying = true
        if isMusicOn {
            musicPlayer.play()
        }
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            var previous = ContinuousClock.now

            while !Task.isCancelled,
                  isPlaying,
                  activeSeasonIndex < store.series.count {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let elapsed = previous.duration(to: now)
                previous = now
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

                gameProgress += seconds * 26 * speed
                let season = store.series[activeSeasonIndex]

                if gameProgress >= Double(season.endGame) {
                    gameProgress = Double(season.endGame)
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled, isPlaying else { break }
                    activeSeasonIndex += 1
                    gameProgress = 0
                }
            }

            if activeSeasonIndex >= store.series.count {
                isPlaying = false
                musicPlayer.pause()
            }
        }
    }

    @MainActor
    private func pauseAnimation() {
        isPlaying = false
        musicPlayer.pause()
        animationTask?.cancel()
        animationTask = nil
    }

    @MainActor
    private func restartAnimation() {
        pauseAnimation()
        activeSeasonIndex = 0
        gameProgress = 0
        startAnimation()
    }

    @MainActor
    private func stopAnimation() {
        isPlaying = false
        musicPlayer.stop()
        animationTask?.cancel()
        animationTask = nil
    }

    private func color(for year: Int) -> Color {
        switch year {
        case 2023: Color(red: 0.031, green: 0.494, blue: 0.643)
        case 2024: Color(red: 0.604, green: 0.404, blue: 0.0)
        case 2025: Color(red: 0.467, green: 0.325, blue: 0.780)
        default: Color(red: 0.835, green: 0.173, blue: 0.227)
        }
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Graph Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The Game 108 data could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.red)
        }
    }
}

private struct Game108Canvas: View {
    let series: [GraphSeries]
    let activeSeasonIndex: Int
    let gameProgress: Double

    private let minimumDiff = -16.0
    private let maximumDiff = 18.0
    private let maximumGame = 162.0

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(
                x: 36,
                y: 24,
                width: max(size.width - 48, 1),
                height: max(size.height - 58, 1)
            )

            drawGrid(context: &context, plot: plot)

            for (index, season) in series.enumerated() {
                let fraction: Double
                if index < activeSeasonIndex {
                    fraction = 1
                } else if index == activeSeasonIndex {
                    fraction = min(max(gameProgress / Double(season.endGame), 0), 1)
                } else {
                    fraction = 0
                }

                guard fraction > 0 else { continue }
                let path = seasonPath(season, plot: plot)
                    .trimmedPath(from: 0, to: fraction)
                let lineColor = color(for: season.year)

                context.drawLayer { layer in
                    if index == activeSeasonIndex {
                        layer.addFilter(.shadow(color: lineColor.opacity(0.28), radius: 5))
                    }
                    layer.stroke(
                        path,
                        with: .color(lineColor),
                        style: StrokeStyle(
                            lineWidth: index == activeSeasonIndex ? 3 : 2.2,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                if index == activeSeasonIndex,
                   let lineTip = path.currentPoint {
                    drawWally(
                        context: &context,
                        at: lineTip,
                        size: 24,
                        seasonColor: lineColor
                    )
                }

                if fraction >= 0.999, let lineTip = path.currentPoint {
                    drawSeasonEndLabel(
                        context: &context,
                        season: season,
                        at: lineTip,
                        color: lineColor
                    )
                }
            }

            drawCheckpointAnnotation(context: &context, plot: plot)
        }
        .accessibilityLabel("Four Red Sox seasons showing games above or below .500")
    }

    private func drawWally(
        context: inout GraphicsContext,
        at point: CGPoint,
        size: CGFloat,
        seasonColor: Color
    ) {
        let scale = size / 24
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(
                x: point.x + x * scale,
                y: point.y + y * scale,
                width: width * scale,
                height: height * scale
            )
        }

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: seasonColor.opacity(0.65), radius: 7))
            layer.fill(
                Path(ellipseIn: rect(-13, -13, 26, 26)),
                with: .color(seasonColor.opacity(0.24))
            )

            let furGreen = Color(red: 0.12, green: 0.58, blue: 0.24)
            let darkGreen = Color(red: 0.04, green: 0.34, blue: 0.13)

            for index in 0..<20 {
                let angle = Double(index) / 20 * Double.pi * 2
                let radius: CGFloat = index.isMultiple(of: 2) ? 9.8 : 10.8
                let x = cos(angle) * radius - 1.45
                let y = sin(angle) * radius * 0.9 - 1.45
                layer.fill(
                    Path(ellipseIn: rect(x, y, 2.9, 2.9)),
                    with: .color(index.isMultiple(of: 3) ? darkGreen : furGreen)
                )
            }

            layer.fill(
                Path(ellipseIn: rect(-10.2, -9.7, 20.4, 19.4)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.39, green: 0.84, blue: 0.43), furGreen, darkGreen]),
                    center: CGPoint(x: point.x - 3 * scale, y: point.y - 4 * scale),
                    startRadius: 1,
                    endRadius: 13 * scale
                )
            )

            var cap = Path()
            cap.move(to: CGPoint(x: point.x - 7 * scale, y: point.y - 7 * scale))
            cap.addCurve(
                to: CGPoint(x: point.x + 7 * scale, y: point.y - 7 * scale),
                control1: CGPoint(x: point.x - 6 * scale, y: point.y - 14 * scale),
                control2: CGPoint(x: point.x + 6 * scale, y: point.y - 14 * scale)
            )
            cap.addLine(to: CGPoint(x: point.x + 7 * scale, y: point.y - 5.5 * scale))
            cap.addLine(to: CGPoint(x: point.x - 7 * scale, y: point.y - 5.5 * scale))
            cap.closeSubpath()
            layer.fill(cap, with: .color(AppColor.navy))

            var brim = Path()
            brim.move(to: CGPoint(x: point.x - 5.5 * scale, y: point.y - 6 * scale))
            brim.addCurve(
                to: CGPoint(x: point.x - 11 * scale, y: point.y - 4.5 * scale),
                control1: CGPoint(x: point.x - 8 * scale, y: point.y - 7 * scale),
                control2: CGPoint(x: point.x - 11.5 * scale, y: point.y - 6.2 * scale)
            )
            brim.addCurve(
                to: CGPoint(x: point.x - 5 * scale, y: point.y - 4.5 * scale),
                control1: CGPoint(x: point.x - 9 * scale, y: point.y - 3.4 * scale),
                control2: CGPoint(x: point.x - 6.5 * scale, y: point.y - 3.7 * scale)
            )
            brim.closeSubpath()
            layer.fill(brim, with: .color(AppColor.navy.opacity(0.92)))

            layer.draw(
                Text("B")
                    .font(.system(size: 5 * scale, weight: .black, design: .serif))
                    .foregroundStyle(AppColor.red),
                at: CGPoint(x: point.x + 0.5 * scale, y: point.y - 8.4 * scale),
                anchor: .center
            )

            layer.fill(Path(ellipseIn: rect(-3.2, -5.5, 6, 7)), with: .color(.white))
            layer.fill(Path(ellipseIn: rect(2.1, -5, 5.2, 6.2)), with: .color(.white))
            layer.fill(Path(ellipseIn: rect(-0.7, -3.6, 2.3, 3.1)), with: .color(AppColor.ink))
            layer.fill(Path(ellipseIn: rect(4, -3.3, 2.1, 2.8)), with: .color(AppColor.ink))

            var mouth = Path()
            mouth.move(to: CGPoint(x: point.x - 1 * scale, y: point.y + 3.2 * scale))
            mouth.addCurve(
                to: CGPoint(x: point.x + 7.4 * scale, y: point.y + 4.2 * scale),
                control1: CGPoint(x: point.x + 2 * scale, y: point.y + 2.5 * scale),
                control2: CGPoint(x: point.x + 6.5 * scale, y: point.y + 3 * scale)
            )
            mouth.addCurve(
                to: CGPoint(x: point.x + 0.5 * scale, y: point.y + 6.2 * scale),
                control1: CGPoint(x: point.x + 6.3 * scale, y: point.y + 7.4 * scale),
                control2: CGPoint(x: point.x + 2.6 * scale, y: point.y + 8 * scale)
            )
            mouth.closeSubpath()
            layer.fill(mouth, with: .color(Color.black.opacity(0.88)))

            layer.fill(
                Path(ellipseIn: rect(-0.8, -0.5, 6.7, 5.6)),
                with: .color(Color(red: 1, green: 0.58, blue: 0.08))
            )
        }
    }

    private func drawGrid(context: inout GraphicsContext, plot: CGRect) {
        for value in stride(from: -15, through: 15, by: 5) {
            let y = yPosition(Double(value), plot: plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))

            context.stroke(
                line,
                with: .color(value == 0 ? AppColor.navy.opacity(0.42) : AppColor.border),
                style: StrokeStyle(
                    lineWidth: value == 0 ? 1.3 : 0.8,
                    dash: value == 0 ? [6, 5] : []
                )
            )

            let label = value == 0 ? ".500" : (value > 0 ? "+\(value)" : "\(value)")
            context.draw(
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: plot.minX - 5, y: y),
                anchor: .trailing
            )
        }

        for game in [0, 54, 162] {
            let x = xPosition(Double(game), plot: plot)
            var line = Path()
            line.move(to: CGPoint(x: x, y: plot.minY))
            line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(line, with: .color(AppColor.border), lineWidth: 0.8)
            context.draw(
                Text(game == 0 ? "OPEN" : "G\(game)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: x, y: plot.maxY + 13),
                anchor: .center
            )
        }

        let checkpointX = xPosition(108, plot: plot)
        var checkpoint = Path()
        checkpoint.move(to: CGPoint(x: checkpointX, y: plot.minY))
        checkpoint.addLine(to: CGPoint(x: checkpointX, y: plot.maxY))
        context.stroke(
            checkpoint,
            with: .color(Color(red: 0.69, green: 0.51, blue: 0.08)),
            style: StrokeStyle(lineWidth: 1.4, dash: [3, 4])
        )
    }

    private func drawCheckpointAnnotation(
        context: inout GraphicsContext,
        plot: CGRect
    ) {
        let annotationColor = Color.black
        let point = CGPoint(
            x: xPosition(108, plot: plot),
            y: yPosition(6, plot: plot)
        )

        context.draw(
            Text("GAME 108 = 57–51!")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(annotationColor),
            at: CGPoint(x: point.x - 8, y: point.y - 73),
            anchor: .bottomTrailing
        )

        var arrow = Path()
        arrow.move(to: CGPoint(x: point.x - 42, y: point.y - 66))
        arrow.addLine(to: CGPoint(x: point.x - 20, y: point.y - 29))
        arrow.move(to: CGPoint(x: point.x - 20, y: point.y - 29))
        arrow.addLine(to: CGPoint(x: point.x - 32, y: point.y - 35))
        arrow.move(to: CGPoint(x: point.x - 20, y: point.y - 29))
        arrow.addLine(to: CGPoint(x: point.x - 21, y: point.y - 43))
        context.stroke(
            arrow,
            with: .color(AppColor.paper),
            style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            arrow,
            with: .color(annotationColor),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSeasonEndLabel(
        context: inout GraphicsContext,
        season: GraphSeries,
        at point: CGPoint,
        color: Color
    ) {
        let label = season.year == 2026 ? "’26 YTD" : "’\(String(season.year).suffix(2))"
        context.draw(
            Text(label)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(color),
            at: CGPoint(x: point.x - 6, y: point.y - 13),
            anchor: .bottomTrailing
        )
    }

    private func seasonPath(_ season: GraphSeries, plot: CGRect) -> Path {
        let points = season.displayDiff.enumerated().map { game, difference in
            CGPoint(
                x: xPosition(Double(game), plot: plot),
                y: yPosition(difference, plot: plot)
            )
        }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let firstControl = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let secondControl = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: firstControl, control2: secondControl)
        }

        return path
    }

    private func xPosition(_ game: Double, plot: CGRect) -> CGFloat {
        plot.minX + CGFloat(game / maximumGame) * plot.width
    }

    private func yPosition(_ difference: Double, plot: CGRect) -> CGFloat {
        let ratio = (difference - minimumDiff) / (maximumDiff - minimumDiff)
        return plot.maxY - CGFloat(ratio) * plot.height
    }

    private func color(for year: Int) -> Color {
        switch year {
        case 2023: Color(red: 0.031, green: 0.494, blue: 0.643)
        case 2024: Color(red: 0.604, green: 0.404, blue: 0.0)
        case 2025: Color(red: 0.467, green: 0.325, blue: 0.780)
        default: Color(red: 0.835, green: 0.173, blue: 0.227)
        }
    }
}

#Preview {
    NavigationStack {
        Game108GraphView()
    }
}

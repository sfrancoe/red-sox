import SwiftUI

struct HomeRunChaseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = HomeRunChaseStore()
    @State private var chapter = 0
    @State private var drawProgress = 0.0
    @State private var morphProgress = 0.0
    @State private var markerOpacity = 0.0
    @State private var projectionProgress = 0.0
    @State private var homeRunsPerSeason = 38.0
    @State private var finalAge = 40.0
    @State private var shareURL: URL?

    private var config: ChaseConfig { store.config }
    private var subjectTotal: Int { config.subject.seasons.reduce(0) { $0 + $1.hr } }
    private var subjectAtBats: Int { config.subject.seasons.reduce(0) { $0 + $1.ab } }
    private var subjectAge: Int { config.subject.seasons.last?.age ?? 34 }
    private var careerRate: (abPerHR: Double, hrPerSeason: Double) {
        ChaseEngine.careerRate(config.subject)
    }
    private var passBondsAge: Int {
        ChaseEngine.milestones(for: config).first { $0.label == "PASSES BONDS" }?.age ?? 42
    }
    private var userProjectionTotal: Int {
        config.projectionBaseline.hr
            + max(0, Int(finalAge.rounded()) - config.projectionBaseline.age) * Int(homeRunsPerSeason.rounded())
    }

    var body: some View {
        ZStack {
            AppColor.night.ignoresSafeArea()

            TabView(selection: $chapter) {
                ForEach(0..<4, id: \.self) { index in
                    chapterView(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("The Home Run Chase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColor.night, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareURL {
                    ShareLink(
                        item: shareURL,
                        preview: SharePreview("Judge: by age vs. by at-bats")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the at-bat comparison")
                }
            }
        }
        .task {
            await store.load()
            makeShareCard()
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-chase-chapter-2") {
                chapter = 1
            }
            #endif
        }
        .task(id: chapter) {
            await animateChapter(chapter)
        }
    }

    private func chapterView(_ index: Int) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storyHeader(index)

                    ChaseChart(
                        config: config,
                        drawProgress: index == 0 ? drawProgress : 1,
                        morphProgress: index == 1 ? morphProgress : 0,
                        markerOpacity: index == 1 ? markerOpacity : 0,
                        projection: projection(for: index),
                        projectionProgress: index == 2 ? projectionProgress : 1,
                        contractEndAge: index == 2 ? config.contractEndAge : nil
                    )
                    .frame(height: min(max(proxy.size.height * 0.40, 300), 430))
                    .background(AppColor.nightRaised)
                    .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
                    .accessibilityLabel(chartAccessibilityLabel(index))

                    chapterPanel(index)
                    navigation
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func storyHeader(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker(index).uppercased())
                .font(AppFont.label)
                .tracking(1.2)
                .foregroundStyle(AppColor.amber)

            Text(hero(index))
                .font(.system(size: 68, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(AppColor.bone)
                .contentTransition(.numericText())

            Text(subhead(index))
                .font(AppFont.body)
                .foregroundStyle(AppColor.boneDim)
                .lineSpacing(3)

            if let refreshNote = store.refreshNote {
                Label(refreshNote, systemImage: store.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
            }
        }
    }

    @ViewBuilder
    private func chapterPanel(_ index: Int) -> some View {
        switch index {
        case 0:
            ageBars
        case 1:
            atBatBars
        case 2:
            milestoneGrid
        default:
            projectionControls
        }
    }

    private var ageBars: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelTitle("HOME RUNS THROUGH AGE \(subjectAge)")
            ForEach(config.players.sorted {
                ChaseEngine.hr(for: $0, at: Double(subjectAge), axis: .age)
                    > ChaseEngine.hr(for: $1, at: Double(subjectAge), axis: .age)
            }) { player in
                ChaseBar(
                    name: player.name,
                    value: ChaseEngine.hr(for: player, at: Double(subjectAge), axis: .age),
                    maximum: 550,
                    accented: player.isSubject
                )
            }
            HStack {
                Text("Mays")
                Spacer()
                Text("Not in this comparison")
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.boneMuted)
        }
        .chasePanel()
    }

    private var atBatBars: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelTitle("APPROX. HR THROUGH \(subjectAtBats.formatted()) AT-BATS")
            ForEach(config.players.sorted {
                ChaseEngine.hr(for: $0, at: Double(subjectAtBats), axis: .atBats)
                    > ChaseEngine.hr(for: $1, at: Double(subjectAtBats), axis: .atBats)
            }) { player in
                ChaseBar(
                    name: player.name,
                    value: ChaseEngine.hr(for: player, at: Double(subjectAtBats), axis: .atBats),
                    maximum: Double(subjectTotal),
                    accented: player.isSubject
                )
            }

            Text("Within-season values are linearly estimated. Ruth's early at-bats came mainly as a pitcher. Bonds and McGwire played in the steroid era; this comparison presents the record book without resolving that history.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.boneMuted)
                .lineSpacing(2)
                .padding(.top, 4)
        }
        .chasePanel()
    }

    private var milestoneGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
            ForEach(ChaseEngine.milestones(for: config)) { milestone in
                VStack(alignment: .leading, spacing: 4) {
                    Text(milestone.label)
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.amber)
                    Text("AGE \(milestone.age)")
                        .font(AppFont.displayMedium)
                        .foregroundStyle(AppColor.bone)
                    Text(String(milestone.year))
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.boneMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppColor.nightRaised)
            }
        }
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
    }

    private var projectionControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            slider(
                title: "HOME RUNS PER SEASON",
                value: $homeRunsPerSeason,
                range: 20...55,
                display: Int(homeRunsPerSeason.rounded())
            )
            slider(
                title: "FINAL SEASON AGE",
                value: $finalAge,
                range: 36...42,
                display: Int(finalAge.rounded())
            )
        }
        .chasePanel()
    }

    private func slider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: Int
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(AppFont.label).tracking(0.8)
                Spacer()
                Text(String(display)).font(AppFont.displayMedium).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .tint(AppColor.amber)
                .accessibilityValue(String(display))
        }
        .foregroundStyle(AppColor.bone)
    }

    private var navigation: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    Button {
                        chapter = index
                    } label: {
                        Circle()
                            .fill(index == chapter ? AppColor.amber : AppColor.rule)
                            .frame(width: 10, height: 10)
                            .frame(width: 30, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chapter \(index + 1)")
                    .accessibilityAddTraits(index == chapter ? .isSelected : [])
                }
            }

            Spacer()

            if chapter < 3 {
                Button {
                    chapter += 1
                } label: {
                    Label("NEXT", systemImage: "arrow.right")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.night)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(AppColor.amber)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func panelTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.label)
            .tracking(0.8)
            .foregroundStyle(AppColor.boneMuted)
    }

    private func hero(_ index: Int) -> String {
        switch index {
        case 0:
            let ruthAtAge = ChaseEngine.hr(for: ChaseData.ruth, at: Double(subjectAge), axis: .age)
            return String(max(0, Int(ruthAtAge.rounded()) - subjectTotal))
        case 1: return subjectTotal.formatted()
        case 2: return String(passBondsAge)
        default: return userProjectionTotal.formatted()
        }
    }

    private func kicker(_ index: Int) -> String {
        switch index {
        case 0: "Home runs behind Ruth's pace at \(subjectAge)"
        case 1: "Now count at-bats, not birthdays"
        case 2: "Age he'd pass Bonds at his career rate"
        default: "You call it"
        }
    }

    private func subhead(_ index: Int) -> String {
        switch index {
        case 0:
            return "Judge's first full season came at 25. By age, he's last of these five."
        case 1:
            return "Through the same \(subjectAtBats.formatted()) at-bats, nobody here had more. His 300th came in at-bat \(ChaseData.judge300thHomeRunAtBat.formatted()); Ruth needed \(ChaseData.ruth300thHomeRunAtBat.formatted())."
        case 2:
            return "One homer every \(careerRate.abPerHR.formatted(.number.precision(.fractionLength(1)))) at-bats, 540 at-bats a year, zero decline."
        default:
            let rank = ChaseEngine.allTimeRank(Double(userProjectionTotal), leaderboard: config.leaderboard)
            if let passing = rank.passing {
                return "Would rank \(ordinal(rank.rank)) all-time, passing \(passing)."
            } else {
                return "Would rank \(ordinal(rank.rank)) all-time."
            }
        }
    }

    private func projection(for index: Int) -> [CumulativePoint]? {
        switch index {
        case 2:
            ChaseEngine.project(
                from: config.projectionBaseline,
                rate: careerRate.hrPerSeason,
                throughAge: passBondsAge
            )
        case 3:
            ChaseEngine.project(
                from: config.projectionBaseline,
                rate: homeRunsPerSeason,
                throughAge: Int(finalAge.rounded())
            )
        default: nil
        }
    }

    private func chartAccessibilityLabel(_ index: Int) -> String {
        switch index {
        case 0: "Career home run lines by age. Judge trails the four comparison hitters at age \(subjectAge)."
        case 1: "Career home run lines moving to an at-bat axis. Judge leads at \(subjectAtBats) at-bats."
        default: "Judge career home runs with a straight-line projection through age \(index == 2 ? passBondsAge : Int(finalAge))."
        }
    }

    @MainActor
    private func animateChapter(_ index: Int) async {
        drawProgress = index == 0 ? 0 : 1
        morphProgress = 0
        markerOpacity = 0
        projectionProgress = 0

        guard !reduceMotion else {
            drawProgress = 1
            morphProgress = index == 1 ? 1 : 0
            markerOpacity = index == 1 ? 1 : 0
            projectionProgress = 1
            return
        }

        await Task.yield()
        guard !Task.isCancelled else { return }
        switch index {
        case 0:
            withAnimation(.linear(duration: 4)) { drawProgress = 1 }
        case 1:
            withAnimation(.easeInOut(duration: 1.7)) { morphProgress = 1 }
            try? await Task.sleep(for: .seconds(1.75))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { markerOpacity = 1 }
        case 2:
            withAnimation(.easeOut(duration: 1.25)) { projectionProgress = 1 }
        default:
            projectionProgress = 1
        }
    }

    @MainActor
    private func makeShareCard() {
        let renderer = ImageRenderer(content:
            HomeRunShareCard(config: config)
                .frame(width: 1200, height: 1600)
        )
        renderer.scale = 1
        guard let data = renderer.uiImage?.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-ball-judge-home-run-chase.png")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            shareURL = nil
        }
    }

    private func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
    }
}

struct ChaseBar: View {
    let name: String
    let value: Double
    let maximum: Double
    let accented: Bool
    var large = false

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text(String(Int(value.rounded())))
                    .monospacedDigit()
            }
            .font(large ? .system(size: 20, weight: .medium) : AppFont.bodySmall)
            .foregroundStyle(accented ? AppColor.amber : AppColor.bone)

            GeometryReader { proxy in
                Rectangle()
                    .fill(accented ? AppColor.amber : AppColor.boneMuted.opacity(0.55))
                    .frame(width: proxy.size.width * min(max(value / maximum, 0), 1))
            }
            .frame(height: large ? (accented ? 10 : 7) : (accented ? 7 : 5))
            .background(AppColor.rule)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    func chasePanel() -> some View {
        padding(16)
            .background(AppColor.nightRaised)
            .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
    }
}

#Preview {
    NavigationStack { HomeRunChaseView() }
}

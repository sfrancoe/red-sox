import SwiftUI

private struct ImmaculatePitch: Identifiable {
    let number: Int
    let batter: String
    let velocity: Double
    let type: String
    let result: String
    var id: Int { number }
}

struct NinePitchesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var shown = 0
    @State private var playing = false
    @State private var playbackID = UUID()
    @State private var showSources = false

    private let pitches = [
        ImmaculatePitch(number: 1, batter: "Nick Loftin", velocity: 95.9, type: "Four-seam fastball", result: "Swinging strike"),
        ImmaculatePitch(number: 2, batter: "Nick Loftin", velocity: 96.6, type: "Four-seam fastball", result: "Swinging strike"),
        ImmaculatePitch(number: 3, batter: "Nick Loftin", velocity: 97.2, type: "Four-seam fastball", result: "Called strike — strikeout"),
        ImmaculatePitch(number: 4, batter: "Bobby Witt Jr.", velocity: 97.8, type: "Four-seam fastball", result: "Swinging strike"),
        ImmaculatePitch(number: 5, batter: "Bobby Witt Jr.", velocity: 97.1, type: "Four-seam fastball", result: "Swinging strike"),
        ImmaculatePitch(number: 6, batter: "Bobby Witt Jr.", velocity: 97.0, type: "Four-seam fastball", result: "Swinging strike — strikeout"),
        ImmaculatePitch(number: 7, batter: "Jac Caglianone", velocity: 97.2, type: "Sinker", result: "Foul"),
        ImmaculatePitch(number: 8, batter: "Jac Caglianone", velocity: 97.6, type: "Four-seam fastball", result: "Swinging strike"),
        ImmaculatePitch(number: 9, batter: "Jac Caglianone", velocity: 97.9, type: "Four-seam fastball", result: "Swinging strike — strikeout")
    ]

    var body: some View {
        ZStack {
            AppColor.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("VISUAL STORY 02 · FENWAY PARK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.accent)
                    Text("NINE\nPITCHES.")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .tracking(-2)
                    Text("Payton Tolle opened against Kansas City with an immaculate inning. By pitch nine, he knew.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColor.cream.opacity(0.82))
                    header
                    pitchGrid
                    moment
                    controls
                    Button("Sources") { showSources = true }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppColor.accent)
                }
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(AppColor.cream)
        .navigationTitle("Nine Pitches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColor.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: playbackID) { if playing { await replay() } }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
        .sheet(isPresented: $showSources) { sources }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEPTEMBER 13, 2026 · KANSAS CITY AT BOSTON")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.cream.opacity(0.62))
            HStack(alignment: .firstTextBaseline) {
                Text("\(shown)").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(AppColor.accent).monospacedDigit()
                Text("OF 9 PITCHES").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(AppColor.cream.opacity(0.75))
            }
        }
    }

    private var pitchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(pitches) { pitch in
                VStack(alignment: .leading, spacing: 5) {
                    Text("PITCH \(pitch.number)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(String(format: "%.1f", pitch.velocity)).font(.system(size: 31, weight: .black, design: .rounded)).monospacedDigit()
                    Text(pitch.type.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(pitch.batter).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .padding(10)
                .background(pitch.number <= shown ? AppColor.cream.opacity(0.14) : AppColor.cream.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(pitch.number == shown ? AppColor.accent : .clear, lineWidth: 2))
                .opacity(pitch.number <= shown ? 1 : 0.42)
                .accessibilityLabel("Pitch \(pitch.number), \(pitch.velocity, specifier: "%.1f") miles per hour, \(pitch.type), to \(pitch.batter)")
            }
        }
    }

    private var moment: some View {
        Text(shown == 0 ? "Press replay to take the inning one pitch at a time." : shown == 9 ? "Nine pitches. Nine strikes. Three strikeouts. Immaculate." : "\(pitches[shown - 1].result). \(pitches[shown - 1].batter) is down.")
            .font(.title3.weight(.bold)).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .padding(16).background(AppColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { if playing { stop() } else { start() } } label: {
                Label(playing ? "Pause" : shown == 9 ? "Replay inning" : "Play inning", systemImage: playing ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity).frame(height: 46)
            }.buttonStyle(.borderedProminent).tint(AppColor.accent)
            Button { stop(); shown = 0 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 46, height: 46) }
                .buttonStyle(.bordered).tint(AppColor.cream)
        }
    }

    private var sources: some View {
        NavigationStack {
            List {
                Section("Game data") {
                    Link("MLB Gameday — Kansas City at Boston, Sept. 13, 2026", destination: URL(string: "https://www.mlb.com/gameday/824708")!)
                    Text("Pitch types, velocities and results are from MLB’s live game feed.")
                }
                Section("The moment") {
                    Link("Fan video on X", destination: URL(string: "https://x.com/gingersnaphyde/status/2099245461748002821")!)
                }
            }
            .navigationTitle("Sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false } } }
        }
    }

    private func start() { if shown == 9 { shown = 0 }; if reduceMotion { shown = 9 } else { playing = true; playbackID = UUID() } }
    private func stop() { playing = false }
    private func replay() async { while playing && shown < 9 && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(720)); guard playing else { return }; shown += 1 }; if shown == 9 { playing = false } }
}

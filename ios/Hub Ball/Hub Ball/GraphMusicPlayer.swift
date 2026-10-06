import AVFoundation
import Foundation
import OSLog

@MainActor
final class GraphMusicPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var loopBuffer: AVAudioPCMBuffer?
    private var isPrepared = false
    private var isEnabled = true
    private var wantsPlayback = false
    private var preparation: Task<Void, Never>?
    private var interruption: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HubBall", category: "audio")

    init() {
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.pause() }
        }
    }

    isolated deinit {
        preparation?.cancel()
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { pause() }
    }

    /// Called only by the explicit Play/music-on gesture, never by preparation.
    func play() {
        guard isEnabled else { return }
        wantsPlayback = true
        if isPrepared { startPreparedPlayer() }
        else { Task { await prepare() } }
    }

    func pause() {
        wantsPlayback = false
        player.pause()
    }

    func stop() {
        wantsPlayback = false
        guard isPrepared else { return }
        player.stop()
        scheduleLoop()
    }

    func prepare() async {
        if isPrepared { return }
        if let preparation { await preparation.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let sampleRate = 44_100.0
            let (left, right) = await Self.makeSamples(sampleRate: sampleRate)
            guard !Task.isCancelled,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 2, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
                  let channels = buffer.floatChannelData else { return }
            buffer.frameLength = AVAudioFrameCount(left.count)
            left.withUnsafeBufferPointer { source in
                channels[0].update(from: source.baseAddress!, count: source.count)
            }
            right.withUnsafeBufferPointer { source in
                channels[1].update(from: source.baseAddress!, count: source.count)
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.62
            loopBuffer = buffer
            scheduleLoop()
            engine.prepare()
            isPrepared = true
            if wantsPlayback && isEnabled { startPreparedPlayer() }
        }
        preparation = task
        await task.value
        preparation = nil
    }

    private func startPreparedPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying { player.play() }
        } catch {
            wantsPlayback = false
            logger.error("Unable to start story audio: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleLoop() {
        guard let loopBuffer else { return }
        player.scheduleBuffer(loopBuffer, at: nil, options: .loops)
    }

    @concurrent private static func makeSamples(sampleRate: Double) async -> ([Float], [Float]) {
        let bpm = 84.0
        let secondsPerBeat = 60.0 / bpm
        let duration = secondsPerBeat * 16
        let frameCount = Int(duration * sampleRate)
        var left = [Float](repeating: 0, count: frameCount)
        var right = left

        let roots = [65.41, 51.91, 77.78, 58.27]
        let chords = [
            [261.63, 311.13, 392.00],
            [261.63, 311.13, 415.30],
            [233.08, 311.13, 392.00],
            [233.08, 293.66, 349.23]
        ]
        let riff = [783.99, 622.25, 932.33, 698.46]
        let twoPi = Double.pi * 2

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let beat = time / secondsPerBeat
            let bar = min(Int(beat / 4), 3)
            let beatInBar = beat - Double(bar * 4)

            let bassEnvelope = 0.72 + 0.28 * max(0, sin(Double.pi * beatInBar / 2))
            var sample = sin(twoPi * roots[bar] * time) * 0.105 * bassEnvelope

            for (index, frequency) in chords[bar].enumerated() {
                let detune = index == 1 ? 1.003 : 1
                sample += sin(twoPi * frequency * detune * time) * 0.018
            }

            for kickBeat in [0.0, 1.75, 2.5] {
                let delta = beatInBar - kickBeat
                if delta >= 0, delta < 0.42 {
                    let seconds = delta * secondsPerBeat
                    let envelope = exp(-seconds * 11)
                    let frequency = 48 + 72 * exp(-seconds * 28)
                    sample += sin(twoPi * frequency * seconds) * envelope * 0.28
                }
            }

            let clapDelta = beatInBar - 2
            if clapDelta >= 0, clapDelta < 0.18 {
                let seconds = clapDelta * secondsPerBeat
                sample += noise(frame) * exp(-seconds * 22) * 0.075
            }

            let halfBeat = beat * 2
            let hatDelta = (halfBeat - floor(halfBeat)) * secondsPerBeat / 2
            if hatDelta < 0.045 {
                sample += noise(frame * 7 + 19) * exp(-hatDelta * 70) * 0.028
            }

            let riffStep = floor(beatInBar * 2) / 2
            let riffDelta = beatInBar - riffStep
            if riffDelta < 0.22 {
                let seconds = riffDelta * secondsPerBeat
                let note = riff[bar] * (riffStep.truncatingRemainder(dividingBy: 1) == 0 ? 1 : 0.75)
                sample += sin(twoPi * note * time) * exp(-seconds * 12) * 0.028
            }

            let edgeFade = min(1, min(time / 0.025, (duration - time) / 0.025))
            let output = Float(max(-0.92, min(0.92, sample * edgeFade)))
            left[frame] = output
            right[frame] = output * 0.96
        }

        return (left, right)
    }

    nonisolated private static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43_758.5453
        return (value - floor(value)) * 2 - 1
    }
}

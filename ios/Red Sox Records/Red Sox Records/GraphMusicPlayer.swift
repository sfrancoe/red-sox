import AVFoundation
import Foundation

@MainActor
final class GraphMusicPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var loopBuffer: AVAudioPCMBuffer?
    private var isPrepared = false
    private var isEnabled = true

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            pause()
        }
    }

    func play() {
        guard isEnabled else { return }
        prepareIfNeeded()
        guard isPrepared else { return }

        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    func pause() {
        player.pause()
    }

    func stop() {
        guard isPrepared else { return }
        player.stop()
        scheduleLoop()
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.62
        loopBuffer = makeLoop(format: format)
        scheduleLoop()
        engine.prepare()
        isPrepared = true
    }

    private func scheduleLoop() {
        guard let loopBuffer else { return }
        player.scheduleBuffer(loopBuffer, at: nil, options: .loops)
    }

    private func makeLoop(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let bpm = 84.0
        let secondsPerBeat = 60.0 / bpm
        let duration = secondsPerBeat * 16
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

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
            let time = Double(frame) / format.sampleRate
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
            buffer.floatChannelData?[0][frame] = output
            buffer.floatChannelData?[1][frame] = output * 0.96
        }

        return buffer
    }

    private func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43_758.5453
        return (value - floor(value)) * 2 - 1
    }
}

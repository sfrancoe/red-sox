import Foundation

/// An original solo-piano miniature, rendered locally into a looping WAV.
enum StoryAudioLoop {
    private struct Note {
        let time: Double
        let frequency: Double
        let strength: Double
    }

    private static let sampleRate = 22_050
    private static let duration = 16.0

    // Four slow measures. The left hand plays broken chords; the right hand
    // answers with a melody that resolves into the first note on each repeat.
    private static let leftHand: [Note] = [
        .init(time: 0.00, frequency: 130.81, strength: 0.75),
        .init(time: 1.03, frequency: 196.00, strength: 0.50),
        .init(time: 2.02, frequency: 164.81, strength: 0.55),
        .init(time: 3.05, frequency: 196.00, strength: 0.44),
        .init(time: 4.00, frequency: 110.00, strength: 0.72),
        .init(time: 5.04, frequency: 164.81, strength: 0.48),
        .init(time: 6.02, frequency: 130.81, strength: 0.52),
        .init(time: 7.06, frequency: 164.81, strength: 0.43),
        .init(time: 8.00, frequency: 87.31, strength: 0.73),
        .init(time: 9.02, frequency: 130.81, strength: 0.47),
        .init(time: 10.04, frequency: 110.00, strength: 0.53),
        .init(time: 11.02, frequency: 130.81, strength: 0.43),
        .init(time: 12.00, frequency: 98.00, strength: 0.70),
        .init(time: 13.04, frequency: 146.83, strength: 0.46),
        .init(time: 14.02, frequency: 123.47, strength: 0.52),
        .init(time: 15.04, frequency: 146.83, strength: 0.42)
    ]
    private static let rightHand: [Note] = [
        .init(time: 0.42, frequency: 523.25, strength: 0.79),
        .init(time: 1.35, frequency: 659.25, strength: 0.66),
        .init(time: 2.38, frequency: 783.99, strength: 0.72),
        .init(time: 3.32, frequency: 659.25, strength: 0.61),
        .init(time: 4.42, frequency: 523.25, strength: 0.76),
        .init(time: 5.34, frequency: 493.88, strength: 0.62),
        .init(time: 6.39, frequency: 440.00, strength: 0.71),
        .init(time: 7.33, frequency: 392.00, strength: 0.60),
        .init(time: 8.43, frequency: 440.00, strength: 0.77),
        .init(time: 9.36, frequency: 523.25, strength: 0.65),
        .init(time: 10.37, frequency: 659.25, strength: 0.73),
        .init(time: 11.36, frequency: 523.25, strength: 0.61),
        .init(time: 12.43, frequency: 493.88, strength: 0.74),
        .init(time: 13.37, frequency: 587.33, strength: 0.64),
        .init(time: 14.42, frequency: 392.00, strength: 0.68),
        .init(time: 15.34, frequency: 493.88, strength: 0.56)
    ]

    private static func strike(_ note: Note, gain: Double, into samples: inout [Double]) {
        let count = samples.count
        let start = Int(note.time * Double(sampleRate))
        let voiceFrames = Int(3.6 * Double(sampleRate))
        for offset in 0..<voiceFrames {
            let age = Double(offset) / Double(sampleRate)
            let attack = min(1, age / 0.006)
            let release = min(1, max(0, (3.6 - age) / 0.35))
            let base = 2 * Double.pi * note.frequency * age
            // A struck string has a short bright attack, a long fundamental,
            // and slightly stretched overtones; no sustained synthesizer tone.
            let body = sin(base) * exp(-0.95 * age)
            let second = 0.26 * sin(base * 2.0003) * exp(-2.0 * age)
            let third = 0.09 * sin(base * 3.0012) * exp(-3.9 * age)
            let fourth = 0.03 * sin(base * 4.0030) * exp(-6.5 * age)
            let struck = (body + second + third + fourth) * attack * release
            samples[(start + offset) % count] += gain * note.strength * struck
        }
    }

    /// In-memory PCM WAV; no third-party audio or network request is needed.
    static func makeData() -> Data {
        let frames = Int(duration * Double(sampleRate))
        var samples = [Double](repeating: 0, count: frames)
        for note in leftHand { strike(note, gain: 0.020, into: &samples) }
        for note in rightHand { strike(note, gain: 0.057, into: &samples) }

        // A little room reflection gives the notes space while keeping the
        // piano dry and close. Circular delays preserve the loop boundary.
        let dry = samples
        let firstDelay = Int(0.17 * Double(sampleRate))
        let secondDelay = Int(0.31 * Double(sampleRate))
        for index in samples.indices {
            samples[index] += 0.13 * dry[(index - firstDelay + frames) % frames]
                + 0.08 * dry[(index - secondDelay + frames) % frames]
        }

        let byteCount = frames * 2
        var data = Data()
        data.reserveCapacity(44 + byteCount)
        func append16(_ value: UInt16) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8(value >> 8))
        }
        func append32(_ value: Int) {
            append16(UInt16(value & 0xffff))
            append16(UInt16((value >> 16) & 0xffff))
        }
        data.append(contentsOf: "RIFF".utf8)
        append32(36 + byteCount)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append32(16)
        append16(1) // PCM
        append16(1) // Mono
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(byteCount)
        for sample in samples {
            let value = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(value * Double(Int16.max))))
        }
        return data
    }
}

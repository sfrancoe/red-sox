import Foundation

/// A quiet, repeating melody and warm chord bed generated entirely on the device.
enum StoryAudioLoop {
    private static let length = 16.0
    private static let chords: [[Double]] = [
        [130.81, 164.81, 196.00, 246.94], // Cmaj7
        [110.00, 130.81, 164.81, 196.00], // Am7
        [87.31, 110.00, 130.81, 164.81],  // Fmaj7
        [98.00, 123.47, 146.83, 164.81]  // G6
    ]
    private static let melody: [(time: Double, frequency: Double)] = [
        (0.4, 392.00), (1.3, 523.25), (2.7, 587.33),
        (4.4, 523.25), (5.3, 440.00), (6.7, 392.00),
        (8.4, 440.00), (9.3, 523.25), (10.7, 587.33),
        (12.4, 659.25), (13.3, 587.33), (14.7, 523.25)
    ]

    private static func smooth(_ position: Double) -> Double {
        let x = min(1, max(0, position))
        return x * x * (3 - 2 * x)
    }

    private static func tone(_ frequency: Double, _ age: Double) -> Double {
        let phase = 2 * Double.pi * frequency * age
        return sin(phase) + 0.16 * sin(2 * phase) + 0.04 * sin(3 * phase)
    }

    private static func sample(at time: Double) -> Double {
        var value = 0.0
        // Crossfade each four-second chord; carry the last one across the loop seam.
        for cycle in [-1.0, 0.0] {
            for (index, chord) in chords.enumerated() {
                let age = time - (Double(index) * 4 + cycle * length)
                guard age >= 0 && age < 5.2 else { continue }
                let volume = smooth(age / 0.8) * (1 - smooth((age - 3.7) / 1.5))
                for (voice, frequency) in chord.enumerated() {
                    value += 0.0032 * volume * tone(frequency, age) / Double(voice + 1).squareRoot()
                }
            }
        }
        // Sparse, bell-like notes. The closing note carries into the next loop.
        for cycle in [-1.0, 0.0] {
            for note in melody {
                let age = time - (note.time + cycle * length)
                guard age >= 0 && age < 2.6 else { continue }
                let attack = smooth(age / 0.035)
                let decay = exp(-1.7 * age)
                let release = 1 - smooth((age - 2.1) / 0.5)
                value += 0.042 * attack * decay * release * tone(note.frequency, age)
            }
        }
        return value
    }

    /// In-memory PCM WAV lets AVAudioPlayer use the current output route.
    static func makeData() -> Data {
        let sampleRate = 22_050
        let frames = sampleRate * Int(length)
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
        for frame in 0..<frames {
            let value = max(-1, min(1, sample(at: Double(frame) / Double(sampleRate))))
            append16(UInt16(bitPattern: Int16(value * Double(Int16.max))))
        }
        return data
    }
}

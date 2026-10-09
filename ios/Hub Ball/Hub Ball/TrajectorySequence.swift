import Foundation

/// Optional sequencing preserves the original simultaneous contract when absent.
nonisolated extension TrajectoryStory.Chart {
    struct Frame: Sendable {
        let progresses: [Double?]
        let activeSeries: Int
        let progress: Double
        let beat: Emphasis?
        let holdElapsed: Double?
        var comparisonDraw: Double { min(1, max(0, (holdElapsed ?? 2) / 0.3)) }
        /// Two 0.8-second cosine pulses after a 0.3-second arrow draw. Never disappears.
        var comparisonStrength: Double {
            guard let holdElapsed else { return 1 }
            let pulseTime = min(1.6, max(0, holdElapsed - 0.3))
            return 0.65 + 0.35 * (0.5 + 0.5 * cos(4 * .pi * pulseTime / 1.6))
        }
    }
    func frame(at elapsed: Double) -> Frame {
        guard let sequence else {
            let progress = x(at: elapsed)
            return Frame(progresses: series.map { _ in progress }, activeSeries: series.count - 1, progress: progress,
                         beat: emphasis.last { $0.x <= progress }, holdElapsed: nil)
        }
        var remaining = max(0, elapsed)
        var progresses = [Double?](repeating: nil, count: series.count)
        var latest: Emphasis?
        for index in series.indices {
            let beats = emphasis.filter { ($0.comparison?.sourceSeriesID ?? series.last!.id) == series[index].id }
            let duration = sequence.secondsPerSeries + beats.reduce(0) { $0 + $1.holdSeconds }
            if remaining >= duration {
                progresses[index] = xAxis.maximum; remaining -= duration
                if let beat = beats.last { latest = beat }
                continue
            }
            var previous = xAxis.minimum
            var segmentTime = remaining
            for beat in beats {
                let segment = (beat.x - previous) / (xAxis.maximum - xAxis.minimum) * sequence.secondsPerSeries
                if segmentTime < segment { break }
                segmentTime -= segment; latest = beat
                if segmentTime < beat.holdSeconds {
                    progresses[index] = beat.x
                    return Frame(progresses: progresses, activeSeries: index, progress: beat.x, beat: beat, holdElapsed: segmentTime)
                }
                segmentTime -= beat.holdSeconds; previous = beat.x
            }
            let progress = min(xAxis.maximum, previous + segmentTime / sequence.secondsPerSeries * (xAxis.maximum - xAxis.minimum))
            progresses[index] = progress
            return Frame(progresses: progresses, activeSeries: index, progress: progress, beat: latest, holdElapsed: nil)
        }
        return Frame(progresses: progresses, activeSeries: series.count - 1, progress: xAxis.maximum, beat: latest, holdElapsed: nil)
    }
}

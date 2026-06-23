import Foundation

public struct BPMReading: Equatable, Sendable {
    public let bpm: Double
    public let confidence: Double

    public init(bpm: Double, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }

    /// Display threshold; below this the pill should stay hidden. Real music
    /// produces weaker onset peaks than click tracks (measured ~0.24–0.39 for a
    /// steady beat), so 0.30 flickered; 0.22 keeps a locked beat steady while
    /// still gating out non-rhythmic audio.
    public var isConfident: Bool {
        confidence >= 0.22
    }
}

/// Estimates tempo from streamed PCM via an onset-strength envelope and
/// autocorrelation. Pure DSP, no I/O. Thread-confined: callers serialize
/// `append` and `reading`.
public final class TempoDetector {
    private let sampleRate: Double
    private let frameSize = 512
    private let minBPM = 60.0
    private let maxBPM = 180.0
    private let windowSeconds = 6.0

    private var sampleBuffer: [Float] = []
    private var onsetEnvelope: [Float] = []
    private var lastFrameEnergy: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = max(8_000, sampleRate)
    }

    private var framesPerSecond: Double {
        sampleRate / Double(frameSize)
    }

    public func append(_ samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        while sampleBuffer.count >= frameSize {
            var energy: Float = 0
            for i in 0..<frameSize {
                let sample = sampleBuffer[i]
                energy += sample * sample
            }
            energy = (energy / Float(frameSize)).squareRoot()
            onsetEnvelope.append(max(0, energy - lastFrameEnergy))
            lastFrameEnergy = energy
            sampleBuffer.removeFirst(frameSize)
        }

        let maxFrames = Int(windowSeconds * framesPerSecond)
        if onsetEnvelope.count > maxFrames {
            onsetEnvelope.removeFirst(onsetEnvelope.count - maxFrames)
        }
    }

    public var reading: BPMReading? {
        let minLag = Int((60.0 / maxBPM) * framesPerSecond)
        let maxLag = Int((60.0 / minBPM) * framesPerSecond)
        guard minLag > 0, onsetEnvelope.count > maxLag * 2 else {
            return nil
        }

        let mean = onsetEnvelope.reduce(0, +) / Float(onsetEnvelope.count)
        let env = onsetEnvelope.map { $0 - mean }
        var zeroLag: Float = 0
        for value in env {
            zeroLag += value * value
        }
        guard zeroLag > 0 else {
            return nil
        }

        var bestLag = 0
        var bestScore: Float = 0
        var scoreByLag = [Float](repeating: 0, count: maxLag - minLag + 1)
        for lag in minLag...maxLag {
            var sum: Float = 0
            var index = 0
            while index + lag < env.count {
                sum += env[index] * env[index + lag]
                index += 1
            }
            let score = sum / zeroLag
            scoreByLag[lag - minLag] = score
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestLag > 0 else {
            return nil
        }

        func score(forLag lag: Int) -> Float {
            guard lag >= minLag, lag <= maxLag else { return 0 }
            return scoreByLag[lag - minLag]
        }

        // Octave correction: a strong steady beat also autocorrelates at multiples
        // of its period, so the strongest peak is often the half/quarter tempo
        // (the techno "~72 instead of ~144" error). Fold toward the faster tempo
        // while a peak near half the current period stays strong. The true
        // sub-peak rarely lands exactly on `selectedLag / 2` (integer-lag
        // truncation puts it between bins, where it reads as a trough), so search
        // a small neighborhood and snap to its argmax — that both recovers the
        // peak's real strength and keeps the reported tempo on the true beat.
        // minLag (= maxBPM) caps folding so genuinely fast tempos aren't doubled;
        // a real slow track has no strong half-period peak so it stays put.
        func strongestLagNear(_ lag: Int) -> (lag: Int, score: Float) {
            let lower = max(minLag, lag - 2)
            let upper = min(maxLag, lag + 2)
            guard lower <= upper else { return (lag, 0) }
            var bestLag = lower
            var bestScore = score(forLag: lower)
            for candidate in lower...upper {
                let candidateScore = score(forLag: candidate)
                if candidateScore > bestScore {
                    bestScore = candidateScore
                    bestLag = candidate
                }
            }
            return (bestLag, bestScore)
        }

        // Fold-up gate: the faster peak only needs to be a *clearly real* peak,
        // not nearly as strong as the dominant one. Measured on a 138 BPM beat
        // with a strong 2-beat accent, the real (faster) beat scores ~0.31× the
        // dominant half-tempo peak — whereas a genuinely slow track has ~0 or
        // negative energy at its double. 0.25 sits cleanly between the two, so
        // backbeat-heavy techno folds up to the real tempo while real slow music
        // stays put.
        var selectedLag = bestLag
        while selectedLag / 2 >= minLag {
            let half = strongestLagNear(selectedLag / 2)
            guard half.score >= 0.25 * score(forLag: selectedLag) else { break }
            selectedLag = half.lag
        }

        let bpm = 60.0 * framesPerSecond / Double(selectedLag)
        return BPMReading(bpm: bpm, confidence: Double(max(0, min(1, bestScore))))
    }

    public func reset() {
        sampleBuffer.removeAll(keepingCapacity: true)
        onsetEnvelope.removeAll(keepingCapacity: true)
        lastFrameEnergy = 0
    }
}

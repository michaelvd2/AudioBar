import XCTest
@testable import AudioBarCore

final class TempoDetectorTests: XCTestCase {
    /// Build N seconds of a click train at `bpm` with short impulses on each beat.
    private func clickTrack(bpm: Double, seconds: Double, sampleRate: Double) -> [Float] {
        let total = Int(sampleRate * seconds)
        var signal = [Float](repeating: 0, count: total)
        let samplesPerBeat = Int(sampleRate * 60.0 / bpm)
        var i = 0
        while i < total {
            for k in 0..<8 where i + k < total {
                signal[i + k] = 1.0
            }
            i += samplesPerBeat
        }
        return signal
    }

    func testLocksOntoClickTrackTempo() {
        let sr = 44_100.0
        let detector = TempoDetector(sampleRate: sr)

        detector.append(clickTrack(bpm: 120, seconds: 6, sampleRate: sr))

        let reading = detector.reading
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading!.bpm, 120, accuracy: 5)
        XCTAssertTrue(reading!.isConfident)
    }

    func testLocksOnto150BPM() {
        let sr = 44_100.0
        let detector = TempoDetector(sampleRate: sr)

        detector.append(clickTrack(bpm: 150, seconds: 6, sampleRate: sr))

        XCTAssertEqual(detector.reading?.bpm ?? 0, 150, accuracy: 5)
    }

    func testCorrectsHalfTempoOnAlternatingAccentBeat() {
        // 144 BPM beats with every other beat accented louder. The onset
        // envelope autocorrelates most strongly at the 72 BPM (loud-to-loud)
        // period, which without octave correction reads ~72. The detector
        // should fold up to ~144 (the real beat).
        let sr = 44_100.0
        let bpm = 144.0
        let total = Int(sr * 8)
        var signal = [Float](repeating: 0, count: total)
        let samplesPerBeat = Int(sr * 60.0 / bpm)
        var beat = 0
        var i = 0
        while i < total {
            let amp: Float = beat.isMultiple(of: 2) ? 1.0 : 0.5
            for k in 0..<8 where i + k < total {
                signal[i + k] = amp
            }
            i += samplesPerBeat
            beat += 1
        }

        let detector = TempoDetector(sampleRate: sr)
        detector.append(signal)
        XCTAssertEqual(detector.reading?.bpm ?? 0, 144, accuracy: 6)
    }

    func testCorrectsHalfTempoWithStrongTwoBeatAccent() {
        // Four-on-the-floor at 138 BPM where every other beat carries a much
        // stronger accent (1.0 vs 0.3) — a clap/bass on the 2-beat. The onset
        // envelope autocorrelates most strongly at the 69 BPM period, and the
        // 138 peak lands between integer lag bins, so a naive exact-half fold
        // undervalues it and the reading sticks at ~69. The detector should
        // still recover the real ~138 beat.
        let sr = 44_100.0
        let bpm = 138.0
        let total = Int(sr * 8)
        var signal = [Float](repeating: 0, count: total)
        let samplesPerBeat = Int(sr * 60.0 / bpm)
        var beat = 0
        var i = 0
        while i < total {
            let amp: Float = beat.isMultiple(of: 2) ? 1.0 : 0.3
            for k in 0..<8 where i + k < total {
                signal[i + k] = amp
            }
            i += samplesPerBeat
            beat += 1
        }

        let detector = TempoDetector(sampleRate: sr)
        detector.append(signal)
        XCTAssertEqual(detector.reading?.bpm ?? 0, 138, accuracy: 6)
    }

    func testSilenceIsNotConfident() {
        let detector = TempoDetector(sampleRate: 44_100)

        detector.append([Float](repeating: 0, count: 44_100 * 6))

        let reading = detector.reading
        XCTAssertTrue(reading == nil || !reading!.isConfident)
    }

    func testNeedsEnoughAudioBeforeReporting() {
        let detector = TempoDetector(sampleRate: 44_100)

        detector.append([Float](repeating: 0.2, count: 4_410))

        XCTAssertNil(detector.reading)
    }
}

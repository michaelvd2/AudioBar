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

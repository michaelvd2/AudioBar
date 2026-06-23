import XCTest
@testable import AudioBarCore

final class BPMStabilizerTests: XCTestCase {
    func testReportsFromFirstReading() {
        var stabilizer = BPMStabilizer()
        XCTAssertEqual(stabilizer.add(120) ?? 0, 120, accuracy: 0.1)
    }

    func testSuppressesSingleOctaveOutlier() {
        var stabilizer = BPMStabilizer(windowSize: 5)
        // A correct lock with one spurious half-tempo reading mixed in.
        for value in [120.0, 122, 118, 60, 121] {
            stabilizer.add(value)
        }
        // Median of {60,118,120,121,122} = 120 — the 60 outlier is ignored.
        XCTAssertEqual(stabilizer.stableBPM ?? 0, 120, accuracy: 2)
    }

    func testHysteresisIgnoresMinorJitter() {
        var stabilizer = BPMStabilizer(windowSize: 5, changeThreshold: 3)
        for value in [120.0, 121, 120, 122, 119] {
            stabilizer.add(value)
        }
        // Stays put on ±1–2 noise instead of flickering.
        XCTAssertEqual(stabilizer.stableBPM ?? 0, 120, accuracy: 1)
    }

    func testTracksRealTempoChange() {
        var stabilizer = BPMStabilizer(windowSize: 5, changeThreshold: 3)
        for _ in 0..<5 { stabilizer.add(120) }
        XCTAssertEqual(stabilizer.stableBPM ?? 0, 120, accuracy: 1)
        for _ in 0..<5 { stabilizer.add(140) }
        XCTAssertEqual(stabilizer.stableBPM ?? 0, 140, accuracy: 1)
    }

    func testResetClearsState() {
        var stabilizer = BPMStabilizer()
        for _ in 0..<5 { stabilizer.add(120) }
        stabilizer.reset()
        XCTAssertNil(stabilizer.stableBPM)
    }
}

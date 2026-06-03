import XCTest
@testable import AudioBarCore

final class SystemEQEngineTests: XCTestCase {
    func testEngineStatusDisplayTextIsConciseAndTruthful() {
        XCTAssertEqual(SystemEQEngineStatus.stopped.displayText, "EQ stopped")
        XCTAssertEqual(SystemEQEngineStatus.starting.displayText, "Starting EQ")
        XCTAssertEqual(SystemEQEngineStatus.probing.displayText, "Checking system audio")
        XCTAssertEqual(SystemEQEngineStatus.ready.displayText, "System tap ready")
        XCTAssertEqual(SystemEQEngineStatus.active.displayText, "EQ active")
        XCTAssertEqual(SystemEQEngineStatus.failed(message: "Tap unavailable").displayText, "Tap unavailable")
    }

    func testNewEngineStartsStoppedAndSettingsUpdateDoesNotActivateRoute() {
        let engine = SystemEQEngine()

        engine.update(settings: .applying(.bassBoost))

        XCTAssertEqual(engine.status, .stopped)
    }

    func testStoppingInactiveEngineLeavesItStopped() {
        let engine = SystemEQEngine()

        engine.stop()

        XCTAssertEqual(engine.status, .stopped)
    }

    func testAudioStreamSnapshotFormatsActiveStreamAndLevel() {
        let snapshot = SystemAudioStreamSnapshot.active(
            sampleRate: 48_000,
            channelCount: 2,
            inputLevelDB: -18,
            outputLevelDB: -12
        )

        XCTAssertEqual(snapshot.title, "System Stream")
        XCTAssertEqual(snapshot.subtitle, "2ch 48 kHz")
        XCTAssertGreaterThan(snapshot.levelFraction, 0)
    }

    func testEngineProbeReportsReadyOrFailureWithoutActivatingEQ() {
        let engine = SystemEQEngine()
        let status = engine.probe()

        XCTAssertTrue(status == .ready || status.isFailure)
        XCTAssertNotEqual(status, .active)
    }
}

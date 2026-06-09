import CoreAudio
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

    func testRouteDescriptionUsesOutputDeviceForClockAndPlayback() {
        let description = SystemEQRouteDescription.makeAggregate(
            aggregateUID: "aggregate",
            outputDeviceUID: "output",
            tapUID: "tap"
        )

        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey] as? String, "output")
        XCTAssertEqual(description[kAudioAggregateDeviceClockDeviceKey] as? String, "output")
        XCTAssertEqual(description[kAudioAggregateDeviceTapAutoStartKey] as? Bool, false)

        let subDevices = description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceUIDKey] as? String, "output")
    }

    func testRouteDescriptionRequestsNoExtraLatencyAndTapDriftCompensation() {
        let description = SystemEQRouteDescription.makeAggregate(
            aggregateUID: "aggregate",
            outputDeviceUID: "output",
            tapUID: "tap"
        )

        let subDevices = description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceExtraInputLatencyKey] as? Int, 0)
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceExtraOutputLatencyKey] as? Int, 0)

        let taps = description[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        XCTAssertEqual(taps?.first?[kAudioSubTapUIDKey] as? String, "tap")
        XCTAssertEqual(taps?.first?[kAudioSubTapExtraInputLatencyKey] as? Int, 0)
        XCTAssertEqual(taps?.first?[kAudioSubTapExtraOutputLatencyKey] as? Int, 0)
        XCTAssertEqual(taps?.first?[kAudioSubTapDriftCompensationKey] as? Bool, true)
    }

    func testRouteDescriptionCanCarryMultipleProcessTaps() {
        let description = SystemEQRouteDescription.makeAggregate(
            aggregateUID: "aggregate",
            outputDeviceUID: "output",
            tapUIDs: ["global", "source-1", "source-2"]
        )

        let taps = description[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        XCTAssertEqual(taps?.map { $0[kAudioSubTapUIDKey] as? String }, ["global", "source-1", "source-2"])
    }

    func testEngineTracksSourceProcessIDsAndGainsForRealAudioRoute() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setSourceProcesses"))
        XCTAssertTrue(source.contains("sourceProcessObjectIDs"))
        XCTAssertTrue(source.contains("CATapDescription(stereoMixdownOfProcesses: [processObjectID])"))
        XCTAssertTrue(source.contains("CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)"))
        XCTAssertTrue(source.contains("setSourceVolume"))
        XCTAssertTrue(source.contains("sourceVolumeByProcessObjectID"))
        XCTAssertTrue(source.contains("gainForInputBuffer"))
    }

    private func systemEQEngineURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/SystemEQEngine.swift")
    }
}

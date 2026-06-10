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

    func testRouteDescriptionCanCarryFallbackAndSourceTaps() {
        let description = SystemEQRouteDescription.makeAggregate(
            aggregateUID: "aggregate",
            outputDeviceUID: "output",
            tapUIDs: ["fallback", "youtube", "safari"]
        )

        let taps = description[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        XCTAssertEqual(taps?.map { $0[kAudioSubTapUIDKey] as? String }, ["fallback", "youtube", "safari"])
    }

    func testProcessTapsMuteOriginalHardwarePlaybackWhileRouteReadsTap() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))

        XCTAssertTrue(startFunction.contains("CATapMuteBehavior(rawValue: 2)"))
        XCTAssertFalse(startFunction.contains("CATapMuteBehavior(rawValue: 0)"))
    }

    func testEngineKeepsSourceTapGainStateForRouteMixer() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private var sourceProcessObjectIDs"))
        XCTAssertTrue(source.contains("private var sourceVolumeByProcessObjectID"))
        XCTAssertTrue(source.contains("CATapDescription(stereoMixdownOfProcesses: [processObjectID])"))
        XCTAssertTrue(source.contains("AudioSourceMixer.mixInterleaved"))
        XCTAssertTrue(source.contains("processor.processInterleaved"))
    }

    func testActiveRouteRestartsWhenSourceProcessesChange() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let setSourceProcesses = try XCTUnwrap(source.function(named: "setSourceProcesses"))

        XCTAssertTrue(setSourceProcesses.contains("restartLocked(settings: settings)"))
        XCTAssertFalse(setSourceProcesses.contains("_ = start(settings: settings)"))
    }

    func testRetainedPausedSourcesStayInRouteToAvoidNotificationChurn() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let setSourceProcesses = try XCTUnwrap(source.function(named: "setSourceProcesses"))

        XCTAssertTrue(setSourceProcesses.contains("$0.isActiveOutput || $0.shouldRemainVisibleWhenPaused"))
        XCTAssertFalse(setSourceProcesses.contains(".filter(\\.isActiveOutput)"))
    }

    func testInputBufferMapAlignsTapMetadataAfterExtraDeviceBuffers() {
        let source = AudioObjectID(42)
        let tapProcesses: [AudioObjectID?] = [nil, source]

        XCTAssertNil(SystemEQInputBufferMap.processObjectID(
            inputIndex: 0,
            inputBufferCount: 3,
            tapProcessObjectIDs: tapProcesses
        ))
        XCTAssertNil(SystemEQInputBufferMap.processObjectID(
            inputIndex: 1,
            inputBufferCount: 3,
            tapProcessObjectIDs: tapProcesses
        ))
        XCTAssertEqual(SystemEQInputBufferMap.processObjectID(
            inputIndex: 2,
            inputBufferCount: 3,
            tapProcessObjectIDs: tapProcesses
        ), source)
    }

    private func systemEQEngineURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/SystemEQEngine.swift")
    }
}

private extension String {
    func function(named name: String) -> String? {
        guard let start = range(of: "func \(name)")?.lowerBound else {
            return nil
        }

        var braceDepth = 0
        var didOpenBody = false
        var index = start
        while index < endIndex {
            let character = self[index]
            if character == "{" {
                braceDepth += 1
                didOpenBody = true
            } else if character == "}" {
                braceDepth -= 1
                if didOpenBody && braceDepth == 0 {
                    return String(self[start...index])
                }
            }
            index = self.index(after: index)
        }

        return nil
    }
}

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
        XCTAssertEqual(SystemEQEngineStatus.unavailable(message: "EQ paused for Bluetooth output").displayText, "EQ paused for Bluetooth output")
        XCTAssertFalse(SystemEQEngineStatus.unavailable(message: "EQ paused for Bluetooth output").isFailure)
        XCTAssertTrue(SystemEQEngineStatus.unavailable(message: "EQ paused for Bluetooth output").isUnavailable)
    }

    func testFlatSettingsUpdateDoesNotActivateRoute() {
        let engine = SystemEQEngine()
        XCTAssertEqual(engine.status, .stopped)

        // Flat settings need no processing, so the idle gate short-circuits in
        // update() before the route is ever engaged: the activator is not even
        // invoked, and no phantom `.active` route is left behind. (The route
        // seam itself is exercised by the dedicated-source-change test below.)
        let activator = StubRouteActivator(statusToReturn: .stopped)
        engine.routeActivatorForTesting = activator

        engine.update(settings: .flat)

        XCTAssertEqual(activator.activationCount, 0)
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
        XCTAssertEqual(description[kAudioAggregateDeviceIsStackedKey] as? Bool, false)

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

    func testProcessTapsMuteOriginalHardwarePlaybackForNonBluetoothRoutes() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let muteBehaviorFunction = try XCTUnwrap(source.function(named: "tapMuteBehavior"))

        XCTAssertTrue(muteBehaviorFunction.contains("CATapMuteBehavior(rawValue: 2)"))
    }

    func testBluetoothRouteDetectionIncludesClassicAndLETransports() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let bluetoothDetectionFunction = try XCTUnwrap(source.function(named: "isBluetoothOutputDevice"))

        XCTAssertTrue(bluetoothDetectionFunction.contains("readUInt32(objectID: outputDeviceID, selector: kAudioDevicePropertyTransportType)"))
        XCTAssertTrue(bluetoothDetectionFunction.contains("kAudioDeviceTransportTypeBluetooth"))
        XCTAssertTrue(bluetoothDetectionFunction.contains("kAudioDeviceTransportTypeBluetoothLE"))
    }

    func testBluetoothRoutesUseMutedReplacementRouteInsteadOfUnmutedPassthrough() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let muteBehaviorFunction = try XCTUnwrap(source.function(named: "tapMuteBehavior"))

        XCTAssertTrue(startFunction.contains("let muteBehavior = tapMuteBehavior(forOutputDeviceID: outputDeviceID)"))
        XCTAssertFalse(startFunction.contains("return pauseLocked(\"EQ paused for Bluetooth output\")"))
        XCTAssertTrue(muteBehaviorFunction.contains("isBluetoothOutputDevice(outputDeviceID)"))
        XCTAssertTrue(muteBehaviorFunction.contains("Bluetooth output detected; using muted replacement route"))
        XCTAssertTrue(muteBehaviorFunction.contains("CATapMuteBehavior(rawValue: 2)"))
        XCTAssertFalse(muteBehaviorFunction.contains("CATapMuteBehavior(rawValue: 0)"))
    }

    func testEngineLogsAppliedEQSettingsForRouteDiagnosis() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let updateFunction = try XCTUnwrap(source.function(named: "update"))

        XCTAssertTrue(source.contains("private func settingsSummary"))
        XCTAssertTrue(startFunction.contains("System EQ settings applied"))
        XCTAssertTrue(startFunction.contains("settingsSummary(settings)"))
        XCTAssertTrue(updateFunction.contains("System EQ settings updated"))
        XCTAssertTrue(updateFunction.contains("settingsSummary(settings)"))
    }

    func testEngineRetriesTransientAggregateIOSetupFailures() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let retryFunction = try XCTUnwrap(source.function(named: "createIOProcIDWithRetry"))

        XCTAssertTrue(source.contains("private static let ioSetupRetryCount"))
        XCTAssertTrue(source.contains("private static let ioSetupRetryDelaySeconds"))
        XCTAssertTrue(startFunction.contains("createIOProcIDWithRetry(for: aggregateID)"))
        XCTAssertTrue(retryFunction.contains("AudioDeviceCreateIOProcID"))
        XCTAssertTrue(retryFunction.contains("Thread.sleep"))
        XCTAssertTrue(retryFunction.contains("System EQ IO setup retry"))
    }

    func testEngineTargetsLowLatencyBufferBeforeStartingIO() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let bufferFunction = try XCTUnwrap(source.function(named: "applyLowLatencyBufferLocked"))

        XCTAssertTrue(source.contains("private static let targetBufferFrameSize: UInt32 = 384"))
        XCTAssertTrue(bufferFunction.contains("kAudioDevicePropertyBufferFrameSizeRange"))
        XCTAssertTrue(bufferFunction.contains("kAudioDevicePropertyBufferFrameSize"))
        XCTAssertTrue(bufferFunction.contains("writeUInt32"))

        let bufferRequest = try XCTUnwrap(startFunction.range(of: "applyLowLatencyBufferLocked(to: aggregateID)"))
        let startRequest = try XCTUnwrap(startFunction.range(of: "AudioDeviceStart(aggregateID, newIOProcID)"))
        XCTAssertLessThan(bufferRequest.lowerBound, startRequest.lowerBound)
    }

    func testDeniedGlobalTapSettlesToUnavailableNotFailedRetry() throws {
        // The global (fallback) tap is the system-audio-capture gate. When it
        // can't be created — almost always a missing Screen & System Audio
        // Recording grant — start() must settle into stable direct output
        // (.unavailable via pauseLocked), NOT .failed. .failed makes the store
        // retry start() every tick, re-firing the consent prompt in a loop (the
        // "permission spam") and risking muted audio. This guards that fix.
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))

        XCTAssertTrue(startFunction.contains("createProcessTap(fallbackTapDescription)"))
        XCTAssertTrue(startFunction.contains("return pauseLocked("))
        XCTAssertFalse(startFunction.contains("return failLocked(\"Fallback tap failed\")"))
    }

    func testEngineKeepsSourceTapGainStateForRouteMixer() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private var sourceProcessObjectIDs"))
        XCTAssertTrue(source.contains("private var sourceVolumeByProcessObjectID"))
        XCTAssertTrue(source.contains("private var sourceBalanceByProcessObjectID"))
        XCTAssertTrue(source.contains("private var sourceMonoByProcessObjectID"))
        XCTAssertTrue(source.contains("public func setSourceBalance"))
        XCTAssertTrue(source.contains("public func setSourceMono"))
        XCTAssertTrue(source.contains("CATapDescription(stereoMixdownOfProcesses: [processObjectID])"))
        XCTAssertTrue(source.contains("isMono: controls.isMono"))
        XCTAssertTrue(source.contains("AudioSourceMixer.mixInterleaved"))
        XCTAssertTrue(source.contains("processor.processInterleaved"))
    }

    func testActiveRouteRestartsWhenDedicatedSourceProcessesChange() {
        let engine = SystemEQEngine()
        let activator = StubRouteActivator(statusToReturn: .active)
        engine.routeActivatorForTesting = activator

        // Engage the route.
        engine.update(settings: .applying(.bassBoost))
        XCTAssertEqual(engine.status, .active)
        XCTAssertEqual(activator.activationCount, 1)

        let process = AudioProcess(
            audioObjectID: 42,
            pid: 420,
            bundleID: "com.example.Player",
            appName: "Player",
            trackTitle: nil,
            currentVolume: 100,
            volumeCapability: .systemRoute
        )

        // A source with only default controls doesn't need a dedicated tap, so the
        // active route is untouched — no rebuild.
        engine.setSourceProcesses([process])
        XCTAssertEqual(activator.activationCount, 1)

        // A dedicated per-source control now appears while the route is active. The
        // route must be fully rebuilt (restartLocked → a fresh activation) so the
        // new source tap actually takes effect — NOT short-circuited by start()'s
        // "already active" guard, which would silently drop the new source.
        engine.setSourceBalance(40, for: process.audioObjectID)

        XCTAssertEqual(activator.activationCount, 2)
        XCTAssertEqual(engine.status, .active)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [AudioObjectID(process.audioObjectID)])
    }

    func testBluetoothReplacementRouteDoesNotDedicateEveryAvailableSource() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let sourceNeedsDedicatedTap = try XCTUnwrap(source.function(named: "sourceNeedsDedicatedTap"))

        XCTAssertFalse(source.contains("keepsAvailableSourcesDedicated"))
        XCTAssertTrue(startFunction.contains("updateDedicatedSourceProcessesLocked()"))
        XCTAssertFalse(sourceNeedsDedicatedTap.contains("if keepsAvailableSourcesDedicated"))
        XCTAssertTrue(sourceNeedsDedicatedTap.contains("sourceVolumeByProcessObjectID"))
        XCTAssertTrue(sourceNeedsDedicatedTap.contains("sourceBalanceByProcessObjectID"))
        XCTAssertTrue(sourceNeedsDedicatedTap.contains("sourceMonoByProcessObjectID"))
    }

    func testActiveRouteRestartsWhenDefaultOutputDeviceChanges() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("kAudioHardwarePropertyDefaultOutputDevice"))
        XCTAssertTrue(source.contains("AudioObjectAddPropertyListenerBlock"))
        XCTAssertTrue(source.contains("restartAfterDefaultOutputDeviceChange"))

        let restartFunction = try XCTUnwrap(source.function(named: "restartAfterDefaultOutputDeviceChange"))
        XCTAssertTrue(restartFunction.contains("case .active, .unavailable"))
        XCTAssertTrue(restartFunction.contains("restartLocked(settings: settings)"))
    }

    func testActiveRouteListensForOutputAndAggregateFormatChanges() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "start"))
        let stopFunction = try XCTUnwrap(source.function(named: "stopLocked"))
        let registerFunction = try XCTUnwrap(source.function(named: "registerRouteFormatListenersLocked"))
        let unregisterFunction = try XCTUnwrap(source.function(named: "unregisterRouteFormatListenersLocked"))

        XCTAssertTrue(source.contains("private var routeFormatListenerRegistrations"))
        XCTAssertTrue(startFunction.contains("registerRouteFormatListenersLocked(outputDeviceID: outputDeviceID, aggregateID: aggregateID)"))
        XCTAssertTrue(stopFunction.contains("unregisterRouteFormatListenersLocked()"))
        XCTAssertTrue(registerFunction.contains("kAudioDevicePropertyNominalSampleRate"))
        XCTAssertTrue(registerFunction.contains("kAudioDevicePropertyStreamConfiguration"))
        XCTAssertTrue(registerFunction.contains("kAudioDevicePropertyScopeOutput"))
        XCTAssertTrue(registerFunction.contains("outputDeviceID"))
        XCTAssertTrue(registerFunction.contains("aggregateID"))
        XCTAssertTrue(unregisterFunction.contains("AudioObjectRemovePropertyListenerBlock"))
    }

    func testRouteFormatChangeRestartsActiveOrUnavailableRoute() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let restartFunction = try XCTUnwrap(source.function(named: "restartAfterRouteFormatChange"))

        XCTAssertTrue(restartFunction.contains("case .active, .unavailable"))
        XCTAssertTrue(restartFunction.contains("restartLocked(settings: settings)"))
        XCTAssertTrue(restartFunction.contains("Route format changed"))
    }

    func testWatchdogRestartsWhenAudioResumesAfterSustainedSilence() throws {
        let source = try String(contentsOf: systemEQEngineURL(), encoding: .utf8)
        let processFunction = try XCTUnwrap(source.function(named: "process"))
        let recoverFunction = try XCTUnwrap(source.function(named: "recoverIfRouteStalled"))
        let markFunction = try XCTUnwrap(source.function(named: "markAudibleInputResumeIfNeeded"))

        XCTAssertTrue(source.contains("private static let audibleResumeIdleThresholdSeconds"))
        XCTAssertTrue(source.contains("private var pendingAudibleResumeRestart"))
        XCTAssertTrue(processFunction.contains("markAudibleInputResumeIfNeeded(inputLevelDB: inputLevelDB)"))
        XCTAssertTrue(markFunction.contains("pendingAudibleResumeRestart = true"))
        XCTAssertFalse(markFunction.contains("restartLocked(settings:"))
        XCTAssertTrue(recoverFunction.contains("pendingAudibleResumeRestart"))
        XCTAssertTrue(recoverFunction.contains("resumed after idle"))
        XCTAssertTrue(recoverFunction.contains("restartLocked(settings: processor.currentSettings)"))
    }

    func testRetainedPausedSourcesStayOutOfTapRouteToAvoidStaleCoreAudioObjects() {
        let engine = SystemEQEngine()
        let pausedWebApp = AudioProcess(
            audioObjectID: 42,
            pid: 420,
            bundleID: "com.apple.Safari.WebApp.Example",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 100,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.Example",
            isActiveOutput: false
        )

        engine.setSourceProcesses([pausedWebApp])
        engine.setSourceBalance(40, for: pausedWebApp.audioObjectID)

        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [])
    }

    func testEngineOnlyCreatesSourceTapsForSourcesWithNonDefaultControls() {
        let engine = SystemEQEngine()
        let process = AudioProcess(
            audioObjectID: 42,
            pid: 420,
            bundleID: "com.example.Player",
            appName: "Player",
            trackTitle: nil,
            currentVolume: 100,
            volumeCapability: .systemRoute
        )

        engine.setSourceProcesses([process])
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [])

        engine.setSourceBalance(40, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [AudioObjectID(process.audioObjectID)])

        engine.setSourceBalance(0, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [])

        engine.setSourceMono(true, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [AudioObjectID(process.audioObjectID)])

        engine.setSourceMono(false, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [])

        engine.setSourceVolume(80, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [AudioObjectID(process.audioObjectID)])

        engine.setSourceVolume(100, for: process.audioObjectID)
        XCTAssertEqual(sourceProcessObjectIDs(in: engine), [])
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

    func testInputBufferMapGroupsPlanarChannelBuffersByTap() {
        let source = AudioObjectID(42)
        let tapProcesses: [AudioObjectID?] = [nil, source]

        XCTAssertNil(SystemEQInputBufferMap.processObjectID(
            inputIndex: 0,
            inputBufferCount: 4,
            tapProcessObjectIDs: tapProcesses
        ))
        XCTAssertNil(SystemEQInputBufferMap.processObjectID(
            inputIndex: 1,
            inputBufferCount: 4,
            tapProcessObjectIDs: tapProcesses
        ))
        XCTAssertEqual(SystemEQInputBufferMap.processObjectID(
            inputIndex: 2,
            inputBufferCount: 4,
            tapProcessObjectIDs: tapProcesses
        ), source)
        XCTAssertEqual(SystemEQInputBufferMap.processObjectID(
            inputIndex: 3,
            inputBufferCount: 4,
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

    private func sourceProcessObjectIDs(in engine: SystemEQEngine) -> [AudioObjectID] {
        Mirror(reflecting: engine).children.first { $0.label == "sourceProcessObjectIDs" }?.value as? [AudioObjectID] ?? []
    }
}

/// Deterministic stand-in for the engine's real CoreAudio route. Records how many
/// times the engine asked to (re)activate a route and reports a fixed status, so
/// activation/restart behavior can be asserted without creating or muting real
/// system audio.
private final class StubRouteActivator: SystemEQRouteActivating {
    private(set) var activationCount = 0
    private(set) var lastSettings: EQSettings?
    var statusToReturn: SystemEQEngineStatus

    init(statusToReturn: SystemEQEngineStatus) {
        self.statusToReturn = statusToReturn
    }

    func activateRoute(for engine: SystemEQEngine, settings: EQSettings) -> SystemEQEngineStatus {
        activationCount += 1
        lastSettings = settings
        return statusToReturn
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

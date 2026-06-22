import CoreAudio
import XCTest
@testable import AudioBarCore

final class BPMAnalysisEngineTests: XCTestCase {
    func testBPMEnginePublicContract() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("@MainActor"))
        XCTAssertTrue(source.contains("public final class BPMAnalysisEngine"))
        XCTAssertTrue(source.contains("public func start(sources: [AudioObjectID], sampleRateHint: Double?)"))
        XCTAssertTrue(source.contains("public func setSources(_ sources: [AudioObjectID])"))
        XCTAssertTrue(source.contains("public func stop()"))
        XCTAssertTrue(source.contains("public private(set) var readings: [AudioObjectID: BPMReading]"))
    }

    func testBPMEngineUsesMonoUnmutedPassiveTaps() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "startLocked"))

        XCTAssertTrue(startFunction.contains("CATapDescription(monoMixdownOfProcesses: [processObjectID])"))
        XCTAssertFalse(startFunction.contains("CATapDescription(stereoMixdownOfProcesses: [processObjectID])"))
        XCTAssertTrue(startFunction.contains("CATapMuteBehavior(rawValue: 0)"))
        XCTAssertFalse(startFunction.contains("CATapMuteBehavior(rawValue: 2)"))
    }

    func testBPMEngineUsesClockedAnalysisAggregate() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "startLocked"))

        XCTAssertTrue(startFunction.contains("defaultOutputDeviceID()"))
        XCTAssertTrue(startFunction.contains("outputDeviceUID"))
        XCTAssertTrue(startFunction.contains("SystemEQRouteDescription.makeBPMAnalysisAggregate"))
        XCTAssertFalse(startFunction.contains("SystemEQRouteDescription.makeTapOnlyAggregate"))
        XCTAssertFalse(startFunction.contains("SystemEQRouteDescription.makeAggregate"))
    }

    func testBPMAnalysisAggregateKeepsClockWithoutPlaybackDriftCompensation() {
        let description = SystemEQRouteDescription.makeBPMAnalysisAggregate(
            aggregateUID: "bpm",
            outputDeviceUID: "output",
            tapUIDs: ["tap"]
        )

        XCTAssertEqual(description[kAudioAggregateDeviceUIDKey] as? String, "bpm")
        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey] as? String, "output")
        XCTAssertEqual(description[kAudioAggregateDeviceClockDeviceKey] as? String, "output")
        XCTAssertEqual(description[kAudioAggregateDeviceTapAutoStartKey] as? Bool, false)

        let subDevices = description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceUIDKey] as? String, "output")
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceExtraInputLatencyKey] as? Int, 0)
        XCTAssertEqual(subDevices?.first?[kAudioSubDeviceExtraOutputLatencyKey] as? Int, 0)

        let taps = description[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        XCTAssertEqual(taps?.first?[kAudioSubTapUIDKey] as? String, "tap")
        XCTAssertEqual(taps?.first?[kAudioSubTapDriftCompensationKey] as? Bool, false)
        XCTAssertNil(taps?.first?[kAudioSubTapDriftCompensationQualityKey])
    }

    func testBPMEngineTargetsAnalysisBufferBeforeStartingIO() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "startLocked"))
        let bufferFunction = try XCTUnwrap(source.function(named: "applyAnalysisBufferLocked"))

        XCTAssertTrue(source.contains("private static let targetAnalysisBufferFrameSize: UInt32 = 2048"))
        XCTAssertTrue(bufferFunction.contains("kAudioDevicePropertyBufferFrameSizeRange"))
        XCTAssertTrue(bufferFunction.contains("kAudioDevicePropertyBufferFrameSize"))

        let bufferRequest = try XCTUnwrap(startFunction.range(of: "applyAnalysisBufferLocked(to: aggregateID)"))
        let startRequest = try XCTUnwrap(startFunction.range(of: "AudioDeviceStart"))
        XCTAssertLessThan(bufferRequest.lowerBound, startRequest.lowerBound)
    }

    func testBPMEngineReadsInputsWithoutReplayingOutput() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let processFunction = try XCTUnwrap(source.function(named: "process"))
        let ioProc = try XCTUnwrap(source.range(of: "private let bpmAnalysisIOProc"))

        XCTAssertTrue(source.contains("detectorsByProcessObjectID: [AudioObjectID: TempoDetector]"))
        XCTAssertTrue(processFunction.contains("append(monoSamples"))
        XCTAssertTrue(processFunction.contains("SystemEQInputBufferMap.processObjectID"))
        XCTAssertTrue(source[ioProc.lowerBound...].contains("silence(outputData: outputData)"))
        XCTAssertFalse(source.contains("AudioSourceMixer.mixInterleaved"))
        XCTAssertFalse(source.contains("processor.processInterleaved"))
        XCTAssertFalse(source.contains("writeInterleaved"))
    }

    func testBPMEngineTearsDownTapAggregateAndIOProc() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let stopFunction = try XCTUnwrap(source.function(named: "stopLocked"))

        XCTAssertTrue(stopFunction.contains("AudioDeviceStop"))
        XCTAssertTrue(stopFunction.contains("AudioDeviceDestroyIOProcID"))
        XCTAssertTrue(stopFunction.contains("AudioHardwareDestroyAggregateDevice"))
        XCTAssertTrue(stopFunction.contains("AudioHardwareDestroyProcessTap"))
    }

    func testBPMEngineSerializesCoreAudioWorkOffMainActor() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private let workQueue = DispatchQueue("))
        XCTAssertTrue(source.contains("private func performCoreAudioWork"))
        XCTAssertTrue(source.contains("workQueue.async"))
        XCTAssertTrue(source.contains("BPMAnalysisCore.Work.stop"))
    }

    @MainActor
    func testStopAfterEmptyStartLeavesNoReadingsOrAggregate() {
        let engine = BPMAnalysisEngine()

        engine.start(sources: [], sampleRateHint: nil)
        engine.stop()

        XCTAssertEqual(engine.readings, [:])
        XCTAssertEqual(aggregateID(in: engine), AudioObjectID(kAudioObjectUnknown))
    }

    private func bpmEngineURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/BPMAnalysisEngine.swift")
    }

    @MainActor
    private func aggregateID(in engine: BPMAnalysisEngine) -> AudioObjectID {
        guard let core = Mirror(reflecting: engine).children.first(where: { $0.label == "core" })?.value else {
            return AudioObjectID(kAudioObjectUnknown)
        }
        return Mirror(reflecting: core).children.first { $0.label == "aggregateID" }?.value as? AudioObjectID
            ?? AudioObjectID(kAudioObjectUnknown)
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

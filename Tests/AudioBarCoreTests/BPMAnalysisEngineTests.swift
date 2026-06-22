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

    func testBPMEngineUsesUnmutedPassiveTaps() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let startFunction = try XCTUnwrap(source.function(named: "startLocked"))

        XCTAssertTrue(startFunction.contains("CATapDescription(stereoMixdownOfProcesses: [processObjectID])"))
        XCTAssertTrue(startFunction.contains("CATapMuteBehavior(rawValue: 0)"))
        XCTAssertFalse(startFunction.contains("CATapMuteBehavior(rawValue: 2)"))
    }

    func testBPMEngineReadsInputsWithoutReplayingOutput() throws {
        let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
        let processFunction = try XCTUnwrap(source.function(named: "process"))

        XCTAssertTrue(source.contains("detectorsByProcessObjectID: [AudioObjectID: TempoDetector]"))
        XCTAssertTrue(processFunction.contains("append(monoSamples"))
        XCTAssertTrue(processFunction.contains("SystemEQInputBufferMap.processObjectID"))
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

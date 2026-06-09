import Foundation
import XCTest

final class AudioPopoverViewSourceTests: XCTestCase {
    func testEQPanelKeepsOneSwitchControl() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("Label(\"EQ\""))
        XCTAssertTrue(eqPanel.contains("Toggle(\"On\""))
        XCTAssertTrue(eqPanel.contains("get: { !store.eqSettings.isBypassed }"))
        XCTAssertTrue(eqPanel.contains("set: { store.setEQBypassed(!$0) }"))
        XCTAssertFalse(eqPanel.contains("store.eqEngineStatus.displayText"))
        XCTAssertFalse(eqPanel.contains("Toggle(\"EQ On\""))
        XCTAssertFalse(eqPanel.contains("Toggle(\"Bypass\""))
        XCTAssertFalse(eqPanel.contains("store.stopEQEngine()"))
        XCTAssertFalse(eqPanel.contains("store.startEQEngine()"))
    }

    func testSourceListAppearsBeforeEQPanel() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let contentIndex = try XCTUnwrap(body.range(of: "OutputSourceListView(store: store)")?.lowerBound)
        let eqIndex = try XCTUnwrap(body.range(of: "EQPanelView(store: store)")?.lowerBound)

        XCTAssertLessThan(contentIndex, eqIndex)
    }

    func testOutputSourceListIsAlwaysAVisibleViewerWithVolumeSliders() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let sourceList = try XCTUnwrap(source.slice(
            from: "private struct OutputSourceListView",
            to: "private struct EQPanelView"
        ))

        XCTAssertTrue(sourceList.contains("Text(\"Audio Outputs\")"))
        XCTAssertTrue(sourceList.contains("ForEach(store.processes)"))
        XCTAssertTrue(sourceList.contains("AudioProcessRow(process: process, store: store)"))
        XCTAssertTrue(sourceList.contains(".frame(minHeight:"))
        XCTAssertTrue(source.contains("Slider("))
        XCTAssertTrue(source.contains("store.setVolume(for: process, to: $0)"))
        XCTAssertTrue(source.contains(".disabled(!process.volumeCapability.isAdjustable)"))
        XCTAssertFalse(source.contains("Image(systemName: \"lock\")"))
    }

    func testEQPresetMenuCanSaveAndApplyCustomPresets() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("Save Current..."))
        XCTAssertTrue(eqPanel.contains("store.saveCurrentEQPreset(named: presetName)"))
        XCTAssertTrue(eqPanel.contains("store.applySavedEQPreset(preset)"))
    }

    private func audioPopoverViewURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/Views/AudioPopoverView.swift")
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }

        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}

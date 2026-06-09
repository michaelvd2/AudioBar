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
        XCTAssertTrue(source.contains("VolumeDragBar("))
        XCTAssertTrue(source.contains("store.setVolume(for: process, to: $0)"))
        XCTAssertTrue(source.contains("isEnabled: process.volumeCapability.isAdjustable"))
        XCTAssertFalse(source.contains("Image(systemName: \"lock\")"))
    }

    func testAudioProcessRowsUseTwoTextLinesOnly() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var control"
        ))

        XCTAssertTrue(row.contains("Text(process.displayTitle)"))
        XCTAssertTrue(row.contains("Text(process.displaySubtitle)"))
        XCTAssertFalse(row.contains("capabilityText"))
        XCTAssertFalse(row.contains("web app volume"))
        XCTAssertFalse(row.contains("view only"))
    }

    func testAudioProcessRowsUseCustomCommitOnEndVolumeDragBar() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))
        let dragBar = try XCTUnwrap(source.sliceToEnd(from: "private struct VolumeDragBar"))

        XCTAssertTrue(row.contains("VolumeDragBar("))
        XCTAssertTrue(row.contains("step: 1"))
        XCTAssertFalse(row.contains("Slider("))
        XCTAssertTrue(dragBar.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertTrue(dragBar.contains(".onChanged"))
        XCTAssertTrue(dragBar.contains(".onEnded"))
        XCTAssertTrue(dragBar.contains("onCommit"))
        XCTAssertFalse(dragBar.contains("Slider("))
    }

    func testOutputSourceListIsExpandedByDefaultAndDoesNotScrollForSmallLists() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let sourceList = try XCTUnwrap(source.slice(
            from: "private struct OutputSourceListView",
            to: "private struct EQPanelView"
        ))

        XCTAssertTrue(sourceList.contains("@State private var isExpanded = true"))
        XCTAssertTrue(sourceList.contains("DisclosureGroup("))
        XCTAssertTrue(sourceList.contains("if store.processes.count > visibleRowLimit"))
        XCTAssertTrue(sourceList.contains("LazyVStack(spacing: 0)"))
        XCTAssertTrue(sourceList.contains("sourceRows"))
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

    func sliceToEnd(from start: String) -> String? {
        guard let startRange = range(of: start) else {
            return nil
        }
        return String(self[startRange.lowerBound..<endIndex])
    }
}

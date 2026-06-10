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

    func testEQPanelCanCollapseFullSliderControlsWithCaret() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("@State private var isExpanded = true"))
        XCTAssertTrue(eqPanel.contains("DisclosureGroup("))
        XCTAssertTrue(eqPanel.contains("isExpanded: $isExpanded"))
        XCTAssertTrue(eqPanel.contains(".help(isExpanded ? \"Collapse EQ sliders\" : \"Expand EQ sliders\")"))
        XCTAssertTrue(eqPanel.contains("PreampSlider(store: store)"))
        XCTAssertTrue(eqPanel.contains("ForEach(EQBand.classic)"))
        XCTAssertFalse(eqPanel.contains("isExpanded.toggle()"))
    }

    func testSourceListAppearsBeforeEQPanel() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let contentIndex = try XCTUnwrap(body.range(of: "OutputSourceListView(store: store)")?.lowerBound)
        let eqIndex = try XCTUnwrap(body.range(of: "EQPanelView(store: store)")?.lowerBound)

        XCTAssertLessThan(contentIndex, eqIndex)
    }

    func testFirstUseSetupAppearsBeforeAudioControls() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let setupIndex = try XCTUnwrap(body.range(of: "FirstUseSetupView(store: store)")?.lowerBound)
        let contentIndex = try XCTUnwrap(body.range(of: "OutputSourceListView(store: store)")?.lowerBound)
        let setupView = try XCTUnwrap(source.slice(
            from: "private struct FirstUseSetupView",
            to: "private struct OutputSourceListView"
        ))

        XCTAssertLessThan(setupIndex, contentIndex)
        XCTAssertTrue(body.contains("if store.needsFirstUseSetup"))
        XCTAssertTrue(setupView.contains("Button(\"Enable AudioBar\")"))
        XCTAssertTrue(setupView.contains("store.completeFirstUseSetup()"))
        XCTAssertTrue(setupView.contains("System Audio"))
        XCTAssertTrue(setupView.contains("Input Monitoring"))
    }

    func testHiddenSourcesSettingsStayAtBottomOfLeftClickPanel() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let eqIndex = try XCTUnwrap(body.range(of: "EQPanelView(store: store)")?.lowerBound)
        let settingsIndex = try XCTUnwrap(body.range(of: "SourceSettingsView(store: store)")?.lowerBound)
        let footerIndex = try XCTUnwrap(body.range(of: "footer")?.lowerBound)

        XCTAssertLessThan(eqIndex, settingsIndex)
        XCTAssertLessThan(settingsIndex, footerIndex)
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
        XCTAssertTrue(source.contains("PlaybackControlButton(process: process, store: store)"))
        XCTAssertTrue(source.contains("store.hideSource(process)"))
        XCTAssertFalse(source.contains("Image(systemName: \"lock\")"))
    }

    func testPopoverShowsRestorableHiddenSourcesSettings() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("SourceSettingsView(store: store)"))
        XCTAssertTrue(source.contains("private struct SourceSettingsView"))
        XCTAssertTrue(source.contains("Text(\"Hidden Sources\")"))
        XCTAssertTrue(source.contains("ForEach(store.hiddenSources)"))
        XCTAssertTrue(source.contains("store.restoreHiddenSource(source.id)"))
    }

    func testFooterShowsHiddenSourceCountWhenBlacklistHasEntries() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))

        XCTAssertTrue(footer.contains("if !store.hiddenSources.isEmpty"))
        XCTAssertTrue(footer.contains("Text(\"Blacklisted \\(store.hiddenSources.count)\")"))
        XCTAssertTrue(footer.contains(".help(\"Hidden sources can be restored above the footer\")"))
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

    func testAudioProcessRowsUpdateRouteVolumeWhileDragging() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))
        let dragBar = try XCTUnwrap(source.sliceToEnd(from: "private struct VolumeDragBar"))

        XCTAssertTrue(row.contains("VolumeDragBar("))
        XCTAssertTrue(row.contains("step: 1"))
        XCTAssertTrue(row.contains("@State private var draftVolume"))
        XCTAssertTrue(row.contains("store.previewVolume(for: process, to: $0)"))
        XCTAssertTrue(row.contains("draftVolume = $0"))
        XCTAssertFalse(row.contains("Slider("))
        XCTAssertTrue(dragBar.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertTrue(dragBar.contains(".onChanged"))
        XCTAssertTrue(dragBar.contains(".onEnded"))
        XCTAssertTrue(dragBar.contains("onPreview"))
        XCTAssertTrue(dragBar.contains("onCommit"))
        XCTAssertFalse(dragBar.contains("Slider("))
    }

    func testAudioProcessRowsRevealHideActionOnlyOnRowHover() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))

        XCTAssertTrue(row.contains("@State private var isHovered = false"))
        XCTAssertTrue(row.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(row.contains(".onHover { isHovered = $0 }"))
        XCTAssertTrue(row.contains("Image(systemName: \"eye.slash\")"))
        XCTAssertTrue(row.contains(".opacity(isHovered ? 1 : 0)"))
        XCTAssertTrue(row.contains(".allowsHitTesting(isHovered)"))
        XCTAssertTrue(row.contains(".frame(width: 174, height: 18, alignment: .trailing)"))
        XCTAssertTrue(row.contains(".padding(.trailing, 56)"))
    }

    func testAudioProcessRowsIncludePlaybackControlPerSource() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let playbackButton = try XCTUnwrap(source.slice(
            from: "private struct PlaybackControlButton",
            to: "private struct VolumeDragBar"
        ))

        XCTAssertTrue(playbackButton.contains("process.playbackCapability.isControllable"))
        XCTAssertTrue(playbackButton.contains("store.togglePlayback(for: process)"))
        XCTAssertTrue(playbackButton.contains("process.isActiveOutput ? \"pause.fill\" : \"play.fill\""))
        XCTAssertTrue(playbackButton.contains(".help(playbackHelpText)"))
    }

    func testAudioProcessRowsDefaultMissingVolumeToFullVolume() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let displayedVolume = try XCTUnwrap(source.slice(
            from: "private var displayedVolume",
            to: "private var volumeHelpText"
        ))

        XCTAssertTrue(displayedVolume.contains("process.currentVolume ?? 100"))
        XCTAssertFalse(displayedVolume.contains("process.currentVolume ?? 50"))
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

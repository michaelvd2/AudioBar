import Foundation
import XCTest

final class AudioPopoverViewSourceTests: XCTestCase {
    func testPopoverRootUsesOpaqueSystemBackgroundForReadableContrast() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))

        XCTAssertTrue(body.contains(".background(Color(nsColor: .windowBackgroundColor))"))
    }

    func testEQPanelKeepsOneSwitchControl() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("Label(\"EQ\""))
        XCTAssertTrue(eqPanel.contains("Toggle(store.eqSettings.isBypassed ? \"Off\" : \"On\""))
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

    func testSettingsShowsLaunchAtLoginToggleEvenWithoutHiddenSources() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let settingsView = try XCTUnwrap(source.slice(
            from: "private struct SourceSettingsView",
            to: "private struct EQPanelView"
        ))

        XCTAssertTrue(settingsView.contains("VStack(spacing: 0)"))
        XCTAssertTrue(settingsView.contains("Toggle(\"Launch at Login\""))
        XCTAssertTrue(settingsView.contains("get: { store.isLaunchAtLoginEnabled }"))
        XCTAssertTrue(settingsView.contains("set: { store.setLaunchAtLoginEnabled($0) }"))
        XCTAssertTrue(settingsView.contains("if !store.hiddenSources.isEmpty"))
    }

    func testFooterShowsHiddenSourceCountWhenBlacklistHasEntries() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))

        XCTAssertTrue(footer.contains("if !store.hiddenSources.isEmpty"))
        XCTAssertTrue(footer.contains("Text(\"Blacklisted \\(store.hiddenSources.count)\")"))
        XCTAssertTrue(footer.contains(".help(\"Hidden sources can be restored above the footer\")"))
    }

    func testFooterExposesRestartBeforeQuit() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))

        let restartIndex = try XCTUnwrap(footer.range(of: "Button(\"Restart\")")?.lowerBound)
        let quitIndex = try XCTUnwrap(footer.range(of: "Button(\"Quit\")")?.lowerBound)
        XCTAssertLessThan(restartIndex, quitIndex)
        XCTAssertTrue(footer.contains("restartAudioBar()"))
        XCTAssertTrue(source.contains("private func restartAudioBar()"))
        XCTAssertTrue(source.contains("/usr/bin/open"))
    }

    func testAudioProcessRowsUseAtMostTwoTextLines() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var control"
        ))

        XCTAssertTrue(row.contains("Text(process.displayTitle)"))
        XCTAssertTrue(row.contains("if let inlineSubtitle"))
        XCTAssertTrue(row.contains("Text(inlineSubtitle)"))
        XCTAssertFalse(row.contains("capabilityText"))
        XCTAssertFalse(row.contains("web app volume"))
        XCTAssertFalse(row.contains("view only"))
    }

    func testAudioProcessRowsKeepAppAudioAsTooltipOnly() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var control"
        ))

        XCTAssertTrue(row.contains("process.displaySubtitle == \"App audio\" ? nil : process.displaySubtitle"))
        XCTAssertTrue(row.contains(".help(process.displaySubtitle)"))
        XCTAssertFalse(row.contains("Text(process.displaySubtitle)"))
    }

    func testAudioProcessRowsShowChannelModeButtonUnderSourceText() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var control"
        ))
        let channelModeButton = try XCTUnwrap(source.slice(
            from: "private struct ChannelModeButton",
            to: "private struct BalanceDragBar"
        ))

        let subtitleIndex = try XCTUnwrap(row.range(of: "Text(inlineSubtitle)")?.lowerBound)
        let buttonIndex = try XCTUnwrap(row.range(of: "ChannelModeButton(process: process, store: store)")?.lowerBound)

        XCTAssertLessThan(subtitleIndex, buttonIndex)
        XCTAssertTrue(channelModeButton.contains("Button(store.channelModeLabel(for: process))"))
        XCTAssertTrue(channelModeButton.contains("store.toggleChannelMode(for: process)"))
        XCTAssertTrue(channelModeButton.contains(".font(.caption2)"))
        XCTAssertTrue(channelModeButton.contains(".help(\"Toggle mono/stereo for this source\")"))
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

    func testAudioProcessRowsExposeHideOnlyThroughContextMenu() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))

        XCTAssertTrue(row.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(row.contains(".contextMenu"))
        XCTAssertTrue(row.contains("Button(\"Hide Source\")"))
        XCTAssertTrue(row.contains("store.hideSource(process)"))
        XCTAssertFalse(row.contains("Image(systemName: \"eye.slash\")"))
        XCTAssertFalse(row.contains("@State private var isHovered"))
        XCTAssertFalse(row.contains(".onHover"))
    }

    func testAudioProcessRowsPutVolumeValueRightOfVolumeAndBalanceBelow() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))

        XCTAssertTrue(row.contains("VolumeDragBar("))
        XCTAssertTrue(row.contains("Text(volumeLabel)"))
        XCTAssertTrue(row.contains("BalanceDragBar("))
        XCTAssertTrue(row.contains("value: displayedBalance"))
        XCTAssertTrue(row.contains("Self.sliderTrackWidth"))
        XCTAssertTrue(row.contains("Self.sideMarkerWidth"))
        XCTAssertTrue(row.contains("Self.valueColumnWidth"))
        XCTAssertTrue(row.contains(".frame(width: Self.valueColumnWidth, alignment: .leading)"))
        XCTAssertFalse(row.contains(".frame(width: Self.valueColumnWidth, alignment: .trailing)"))
        XCTAssertTrue(row.contains("Color.clear"))
        XCTAssertTrue(source.contains("store.balance(for: process)"))
        XCTAssertTrue(row.contains("store.setBalance(for: process, to: $0)"))
        XCTAssertTrue(row.contains("Text(\"L\")"))
        XCTAssertTrue(row.contains("Text(\"R\")"))
        XCTAssertTrue(source.contains("private static let sliderTrackWidth"))
        XCTAssertTrue(source.contains("private static let sideMarkerWidth"))
        XCTAssertTrue(source.contains("private static let valueColumnWidth"))
        XCTAssertFalse(row.contains(".padding(.trailing, 26)"))
    }

    func testBalanceSliderSnapsNearCenter() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let balanceDragBar = try XCTUnwrap(source.slice(
            from: "private struct BalanceDragBar",
            to: "private struct PreviousTrackButton"
        ))

        XCTAssertTrue(balanceDragBar.contains("private static let centerSnapThreshold"))
        XCTAssertTrue(balanceDragBar.contains("abs(snappedValue) <= Self.centerSnapThreshold"))
        XCTAssertTrue(balanceDragBar.contains("return 0"))
    }

    func testAudioProcessRowsIncludePlaybackControlPerSource() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private var volumeLabel"
        ))
        let playbackButton = try XCTUnwrap(source.slice(
            from: "private struct PlaybackControlButton",
            to: "private struct RewindPlaybackButton"
        ))
        let rewindButton = try XCTUnwrap(source.slice(
            from: "private struct RewindPlaybackButton",
            to: "private struct VolumeDragBar"
        ))
        let previousButton = try XCTUnwrap(source.slice(
            from: "private struct PreviousTrackButton",
            to: "private struct PlaybackControlButton"
        ))
        let nextButton = try XCTUnwrap(source.slice(
            from: "private struct NextTrackButton",
            to: "private struct RewindPlaybackButton"
        ))

        XCTAssertTrue(row.contains("PreviousTrackButton(process: process, store: store)"))
        XCTAssertTrue(playbackButton.contains("process.playbackCapability.isControllable"))
        XCTAssertTrue(playbackButton.contains("store.togglePlayback(for: process)"))
        XCTAssertTrue(playbackButton.contains("store.isPlaybackPlaying(process) ? \"pause.fill\" : \"play.fill\""))
        XCTAssertTrue(playbackButton.contains(".font(.system(size: 16, weight: .semibold))"))
        XCTAssertTrue(playbackButton.contains(".frame(width: 26, height: 28)"))
        XCTAssertTrue(playbackButton.contains(".help(playbackHelpText)"))
        XCTAssertTrue(row.contains("NextTrackButton(process: process, store: store)"))
        XCTAssertTrue(previousButton.contains("Image(systemName: \"backward.end.fill\")"))
        XCTAssertTrue(previousButton.contains("store.previousTrack(for: process)"))
        XCTAssertTrue(previousButton.contains("process.playbackCapability.isControllable"))
        XCTAssertTrue(previousButton.contains(".disabled(!process.playbackCapability.isControllable)"))
        XCTAssertTrue(nextButton.contains("Image(systemName: \"forward.end.fill\")"))
        XCTAssertTrue(nextButton.contains("store.nextTrack(for: process)"))
        XCTAssertTrue(nextButton.contains("process.playbackCapability.isControllable"))
        XCTAssertTrue(nextButton.contains(".disabled(!process.playbackCapability.isControllable)"))
        XCTAssertTrue(rewindButton.contains("Image(systemName: \"gobackward.15\")"))
        XCTAssertTrue(rewindButton.contains("store.rewindPlayback(for: process)"))
        XCTAssertTrue(rewindButton.contains(".font(.system(size: 16, weight: .semibold))"))
        XCTAssertTrue(rewindButton.contains(".frame(width: 26, height: 28)"))
        XCTAssertTrue(rewindButton.contains(".help(\"Rewind 15 seconds\")"))
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

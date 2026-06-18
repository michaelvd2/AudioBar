import Foundation
import XCTest

final class AudioPopoverViewSourceTests: XCTestCase {
    func testPopoverRootUsesOpaqueSystemBackgroundForReadableContrast() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))

        XCTAssertTrue(body.contains(".frame(width: 460)"))
        XCTAssertTrue(body.contains(".background(Color(nsColor: .windowBackgroundColor))"))
    }

    func testOpeningPopoverDoesNotStartAudioRouteRefresh() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let appSource = try String(contentsOf: audioBarAppURL(), encoding: .utf8)
        let launchFunction = try XCTUnwrap(appSource.slice(from: "func applicationDidFinishLaunching", to: "}\n}"))

        XCTAssertTrue(launchFunction.contains("store.startAutoRefresh()"))
        XCTAssertFalse(body.contains("store.startAutoRefresh()"))
    }

    func testEQPanelKeepsOneSwitchControl() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct CaptureStripView"
        ))

        XCTAssertTrue(eqPanel.contains("Label(\"EQ\""))
        XCTAssertTrue(eqPanel.contains("Text(store.eqSettings.isBypassed ? \"Off\" : \"On\")"))
        XCTAssertTrue(eqPanel.contains("Toggle(\"\", isOn: Binding("))
        XCTAssertTrue(eqPanel.contains("get: { !store.eqSettings.isBypassed }"))
        XCTAssertTrue(eqPanel.contains("set: { store.setEQBypassed(!$0) }"))
        XCTAssertTrue(eqPanel.contains(".labelsHidden()"))
        XCTAssertFalse(eqPanel.contains("store.eqEngineStatus.displayText"))
        XCTAssertFalse(eqPanel.contains("Toggle(store.eqSettings.isBypassed ? \"Off\" : \"On\""))
        XCTAssertFalse(eqPanel.contains("Toggle(\"EQ On\""))
        XCTAssertFalse(eqPanel.contains("Toggle(\"Bypass\""))
        XCTAssertFalse(eqPanel.contains("store.stopEQEngine()"))
        XCTAssertFalse(eqPanel.contains("store.startEQEngine()"))
    }

    func testEQPanelCanCollapseFullSliderControlsWithCaret() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct CaptureStripView"
        ))

        XCTAssertTrue(eqPanel.contains("@State private var isExpanded = true"))
        XCTAssertTrue(eqPanel.contains("DisclosureGroup("))
        XCTAssertTrue(eqPanel.contains("isExpanded: $isExpanded"))
        XCTAssertTrue(eqPanel.contains(".help(isExpanded ? \"Collapse EQ sliders\" : \"Expand EQ sliders\")"))
        XCTAssertTrue(eqPanel.contains("EQBaseline()"))
        XCTAssertTrue(eqPanel.contains("PreampSlider(store: store)"))
        XCTAssertTrue(eqPanel.contains("ForEach(EQBand.classic)"))
        XCTAssertTrue(eqPanel.contains("EQBandSlider(band: band, store: store)"))
        XCTAssertFalse(eqPanel.contains("isExpanded.toggle()"))
    }

    func testCaptureStripSitsBelowHeaderBeforeAudioControls() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let header = try XCTUnwrap(source.slice(from: "private var header", to: "private var footer"))
        let captureIndex = try XCTUnwrap(body.range(of: "CaptureStripView(snapshot: store.eqStreamSnapshot)")?.lowerBound)
        let contentIndex = try XCTUnwrap(body.range(of: "OutputSourceListView(store: store)")?.lowerBound)
        let eqIndex = try XCTUnwrap(body.range(of: "EQPanelView(store: store)")?.lowerBound)

        XCTAssertTrue(header.contains("store.refresh()"))
        XCTAssertLessThan(captureIndex, contentIndex)
        XCTAssertLessThan(contentIndex, eqIndex)
        XCTAssertFalse(source.slice(from: "private struct EQPanelView", to: "private struct CaptureStripView")?.contains("CaptureStripView(snapshot: store.eqStreamSnapshot)") ?? true)
    }

    func testCaptureStripShowsStreamTextBeforeLevelBar() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let meter = try XCTUnwrap(source.slice(from: "private struct CaptureStripView", to: "private struct CountBadge"))
        let titleIndex = try XCTUnwrap(meter.range(of: "Text(snapshot.title)")?.lowerBound)
        let subtitleIndex = try XCTUnwrap(meter.range(of: "Text(snapshot.subtitle)")?.lowerBound)
        let barIndex = try XCTUnwrap(meter.range(of: "StreamLevelBar(value: snapshot.levelFraction)")?.lowerBound)

        XCTAssertTrue(meter.contains("snapshot.isActive ? \"waveform\" : \"waveform.slash\""))
        XCTAssertTrue(meter.contains(".frame(width: 150, height: 5)"))
        XCTAssertLessThan(titleIndex, subtitleIndex)
        XCTAssertLessThan(subtitleIndex, barIndex)
    }

    func testFirstUseSetupAppearsBeforeAudioControls() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let body = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let setupIndex = try XCTUnwrap(body.range(of: "FirstUseSetupView(store: store)")?.lowerBound)
        let contentIndex = try XCTUnwrap(body.range(of: "OutputSourceListView(store: store)")?.lowerBound)
        let setupView = try XCTUnwrap(source.slice(
            from: "private struct FirstUseSetupView",
            to: "private struct PermissionPill"
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

    func testOutputSourceListIsAReorderableVisibleViewerWithVolumeSliders() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let sourceList = try XCTUnwrap(source.slice(
            from: "private struct OutputSourceListView",
            to: "private struct SourceReorderDropDelegate"
        ))

        XCTAssertTrue(sourceList.contains("Text(\"Audio Outputs\")"))
        XCTAssertTrue(sourceList.contains("@State private var isExpanded = true"))
        XCTAssertTrue(sourceList.contains("@State private var draggingID: String?"))
        XCTAssertTrue(sourceList.contains("ForEach(store.processes)"))
        XCTAssertTrue(sourceList.contains("AudioProcessRow(process: process, store: store, draggingID: $draggingID)"))
        XCTAssertTrue(sourceList.contains("CountBadge(count: store.processes.count)"))
        XCTAssertTrue(source.contains("VolumeDragBar("))
        XCTAssertTrue(source.contains("store.setVolume(for: process, to: $0)"))
        XCTAssertTrue(source.contains("isEnabled: process.volumeCapability.isAdjustable"))
        XCTAssertTrue(source.contains("PlaybackControlButton(process: process, store: store)"))
        XCTAssertTrue(source.contains("store.hideSource(process)"))
        XCTAssertFalse(source.contains("Image(systemName: \"lock\")"))
    }

    func testSourceReorderDropDelegateMovesDraggedSources() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let delegate = try XCTUnwrap(source.slice(
            from: "private struct SourceReorderDropDelegate",
            to: "private struct SourceSettingsView"
        ))

        XCTAssertTrue(delegate.contains("DropProposal(operation: .move)"))
        XCTAssertTrue(delegate.contains("store.moveSource(withID: draggingID, aboveID: targetID)"))
        XCTAssertTrue(delegate.contains("draggingID = nil"))
    }

    func testPopoverShowsRestorableHiddenSourcesSettings() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("SourceSettingsView(store: store)"))
        XCTAssertTrue(source.contains("private struct SourceSettingsView"))
        XCTAssertTrue(source.contains("Text(\"Hidden Sources\")"))
        XCTAssertTrue(source.contains("ForEach(store.hiddenSources)"))
        XCTAssertTrue(source.contains("store.restoreHiddenSource(source.id)"))
    }

    func testHiddenSourcesLabelTogglesDisclosureWhenClicked() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let settingsView = try XCTUnwrap(source.slice(
            from: "private struct SourceSettingsView",
            to: "private struct EQPanelView"
        ))
        let hiddenSourcesLabel = try XCTUnwrap(settingsView.slice(
            from: "Text(\"Hidden Sources\")",
            to: ".padding(.horizontal, 14)"
        ))

        XCTAssertTrue(hiddenSourcesLabel.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(hiddenSourcesLabel.contains(".onTapGesture"))
        XCTAssertTrue(hiddenSourcesLabel.contains("isExpanded.toggle()"))
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

    func testFooterShowsHiddenSourceCountWhenHiddenSourcesExist() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))

        XCTAssertTrue(footer.contains("if !store.hiddenSources.isEmpty"))
        XCTAssertTrue(footer.contains("Text(\"· Hidden \\(store.hiddenSources.count)\")"))
        XCTAssertFalse(footer.contains("Blacklisted"))
        XCTAssertTrue(footer.contains(".help(\"Hidden sources can be restored above the footer\")"))
    }

    func testFooterPermissionButtonReflectsPermissionState() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))
        let permissionButton = try XCTUnwrap(source.slice(
            from: "private struct PermissionButton",
            to: "private struct EQBaseline"
        ))

        XCTAssertTrue(footer.contains("PermissionButton(store: store)"))
        XCTAssertTrue(permissionButton.contains("let granted = store.hasRequiredPermissions()"))
        XCTAssertTrue(permissionButton.contains("Image(systemName: granted ? \"checkmark.shield\" : \"exclamationmark.shield.fill\")"))
        XCTAssertTrue(permissionButton.contains("if !granted"))
        XCTAssertTrue(permissionButton.contains("Text(\"Permissions\")"))
        XCTAssertTrue(permissionButton.contains("store.requestPermissions()"))
        XCTAssertTrue(permissionButton.contains("Color.orange"))
        XCTAssertTrue(permissionButton.contains("Permissions granted"))
        XCTAssertTrue(permissionButton.contains("Permissions needed"))
    }

    func testFooterExposesRestartBeforeQuit() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let footer = try XCTUnwrap(source.slice(from: "private var footer", to: "private var footerText"))

        let restartIndex = try XCTUnwrap(footer.range(of: "FooterButton(title: \"Restart\"")?.lowerBound)
        let quitIndex = try XCTUnwrap(footer.range(of: "FooterButton(title: \"Quit\"")?.lowerBound)
        XCTAssertLessThan(restartIndex, quitIndex)
        XCTAssertTrue(footer.contains("restartAudioBar()"))
        XCTAssertTrue(source.contains("private func restartAudioBar()"))
        XCTAssertTrue(source.contains("/usr/bin/open"))
    }

    func testAudioProcessRowsPlaceSourceDetailInHeaderRow() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))
        let headerRow = try XCTUnwrap(source.slice(
            from: "private var headerRow",
            to: "private var expandedControls"
        ))

        XCTAssertTrue(row.contains("headerRow"))
        XCTAssertTrue(row.contains("expandedControls"))
        XCTAssertTrue(headerRow.contains("Text(process.appDisplayName)"))
        XCTAssertTrue(headerRow.contains("MarqueeText(text: store.sourceDetail(for: process), isPlaying: store.isPlaybackPlaying(process))"))
        XCTAssertTrue(headerRow.contains(".help(store.sourceDetail(for: process))"))
        XCTAssertTrue(headerRow.contains("playbackControls"))
        XCTAssertTrue(headerRow.contains("VolumeDragBar("))
        XCTAssertTrue(headerRow.contains("Text(volumeLabel)"))
        XCTAssertFalse(row.contains("capabilityText"))
        XCTAssertFalse(row.contains("web app volume"))
        XCTAssertFalse(row.contains("view only"))
    }

    func testAudioProcessRowsKeepAppAudioAsTooltipOnly() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))

        XCTAssertTrue(row.contains(".help(process.displaySubtitle)"))
        XCTAssertFalse(row.contains("Text(process.displaySubtitle)"))
        XCTAssertFalse(row.contains("inlineSubtitle"))
    }

    func testAudioProcessRowsShowChannelModeButtonInExpandedControls() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private var expandedControls",
            to: "private var playbackControls"
        ))
        let channelModeButton = try XCTUnwrap(source.slice(
            from: "private struct ChannelModeButton",
            to: "private struct BalanceDragBar"
        ))

        XCTAssertTrue(row.contains("ChannelModeButton(process: process, store: store)"))
        XCTAssertTrue(row.contains("BalanceDragBar("))
        XCTAssertTrue(row.contains("Text(balanceLabel)"))
        XCTAssertTrue(channelModeButton.contains("Button(store.channelModeLabel(for: process))"))
        XCTAssertTrue(channelModeButton.contains("store.toggleChannelMode(for: process)"))
        XCTAssertTrue(channelModeButton.contains(".font(.caption2)"))
        XCTAssertTrue(channelModeButton.contains(".help(\"Toggle mono/stereo for this source\")"))
    }

    func testAudioProcessRowsAlignVisibleLeftTextEdges() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))
        let channelModeButton = try XCTUnwrap(source.slice(
            from: "private struct ChannelModeButton",
            to: "private struct BalanceDragBar"
        ))

        XCTAssertTrue(row.contains("Text(process.appDisplayName)"))
        XCTAssertTrue(row.contains("MarqueeText(text: store.sourceDetail(for: process), isPlaying: store.isPlaybackPlaying(process))"))
        XCTAssertTrue(row.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(channelModeButton.contains("static let horizontalPadding: CGFloat = 6"))
        XCTAssertTrue(channelModeButton.contains(".padding(.horizontal, Self.horizontalPadding)"))
    }

    func testAudioProcessRowsExposeFullSourceDetailAsTooltip() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let headerRow = try XCTUnwrap(source.slice(
            from: "private var headerRow",
            to: "private var expandedControls"
        ))

        XCTAssertTrue(headerRow.contains("MarqueeText(text: store.sourceDetail(for: process), isPlaying: store.isPlaybackPlaying(process))"))
        XCTAssertTrue(headerRow.contains(".help(store.sourceDetail(for: process))"))
    }

    func testAudioProcessRowsUpdateRouteVolumeWhileDragging() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
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
            to: "private struct ChannelModeButton"
        ))

        XCTAssertTrue(row.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(row.contains(".contextMenu"))
        XCTAssertTrue(row.contains("Button(\"Hide Source\")"))
        XCTAssertTrue(row.contains("store.hideSource(process)"))
        XCTAssertFalse(row.contains("Image(systemName: \"eye.slash\")"))
        XCTAssertFalse(row.contains("@State private var isHovered"))
        XCTAssertFalse(row.contains(".onHover"))
    }

    func testAudioProcessRowsPutVolumeValueRightOfVolumeAndBalanceBehindDisclosure() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))

        XCTAssertTrue(row.contains("VolumeDragBar("))
        XCTAssertTrue(row.contains("Text(volumeLabel)"))
        XCTAssertTrue(row.contains("expandedControls"))
        XCTAssertTrue(row.contains("BalanceDragBar("))
        XCTAssertTrue(row.contains("value: displayedBalance"))
        XCTAssertTrue(row.contains("Color.clear"))
        XCTAssertTrue(source.contains("store.balance(for: process)"))
        XCTAssertTrue(row.contains("store.setBalance(for: process, to: $0)"))
        XCTAssertTrue(source.contains("private static let sliderTrackWidth"))
        XCTAssertTrue(source.contains("private static let sideMarkerWidth"))
        XCTAssertTrue(source.contains("private static let valueColumnWidth"))
        XCTAssertFalse(row.contains(".padding(.trailing, 26)"))
    }

    func testAudioProcessRowsUseAvailableWidthWithoutEnlargingSliders() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let root = try XCTUnwrap(source.slice(from: "var body: some View", to: "private var header"))
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))

        XCTAssertTrue(root.contains(".frame(width: 460)"))
        XCTAssertTrue(row.contains("private static let sliderTrackWidth: CGFloat = 104"))
        XCTAssertFalse(row.contains("private static let sliderTrackWidth: CGFloat = 144"))
        XCTAssertTrue(row.contains("private static let controlGroupSpacing: CGFloat = 10"))
        XCTAssertTrue(row.contains("private static var sliderRowWidth: CGFloat"))
        XCTAssertTrue(row.contains("private var headerRow"))
        XCTAssertTrue(row.contains("private var expandedControls"))
        XCTAssertTrue(row.contains("playbackControls"))
        XCTAssertTrue(row.contains(".frame(width: 72)"))
        XCTAssertFalse(row.contains("playbackOffsetFromChannelPill"))
        XCTAssertFalse(row.contains("private static let controlColumnWidth: CGFloat = 322"))
    }

    func testAudioProcessRowsKeepPlaybackControlsInHeaderAndBalanceInExpandedRow() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let headerRow = try XCTUnwrap(source.slice(
            from: "private var headerRow",
            to: "private var expandedControls"
        ))
        let expandedControls = try XCTUnwrap(source.slice(
            from: "private var expandedControls",
            to: "private var playbackControls"
        ))

        XCTAssertTrue(headerRow.contains("playbackControls"))
        XCTAssertTrue(headerRow.contains("VolumeDragBar("))
        XCTAssertTrue(headerRow.contains("Text(volumeLabel)"))
        XCTAssertTrue(expandedControls.contains("ChannelModeButton(process: process, store: store)"))
        XCTAssertTrue(expandedControls.contains("BalanceDragBar("))
        XCTAssertTrue(expandedControls.contains("Text(balanceLabel)"))
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

    func testEQUsesCustomVerticalGainSlidersInsteadOfRotatedNativeSliders() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let preampSlider = try XCTUnwrap(source.slice(
            from: "private struct PreampSlider",
            to: "private struct EQBandSlider"
        ))
        let bandSlider = try XCTUnwrap(source.slice(
            from: "private struct EQBandSlider",
            to: "private struct VerticalGainSlider"
        ))
        let verticalSlider = try XCTUnwrap(source.slice(
            from: "private struct VerticalGainSlider",
            to: "private func valueText"
        ))

        XCTAssertTrue(preampSlider.contains("VerticalGainSlider("))
        XCTAssertTrue(preampSlider.contains("onChange: { store.setEQPreamp($0) }"))
        XCTAssertTrue(bandSlider.contains("VerticalGainSlider("))
        XCTAssertTrue(bandSlider.contains("onChange: { store.setEQGain($0, for: band.frequencyHz) }"))
        XCTAssertTrue(verticalSlider.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertTrue(verticalSlider.contains(".onChanged { emit($0.location.y, height: h, usable: usable, span: span) }"))
        XCTAssertTrue(verticalSlider.contains(".onEnded { emit($0.location.y, height: h, usable: usable, span: span) }"))
        XCTAssertTrue(verticalSlider.contains("let stepped = (range.lowerBound + fraction * span).rounded()"))
        XCTAssertFalse(preampSlider.contains("\n            Slider("))
        XCTAssertFalse(bandSlider.contains("\n            Slider("))
    }

    func testAudioProcessRowsIncludePlaybackControlPerSource() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let row = try XCTUnwrap(source.slice(
            from: "private struct AudioProcessRow",
            to: "private struct ChannelModeButton"
        ))
        let previousButton = try XCTUnwrap(source.slice(
            from: "private struct PreviousTrackButton",
            to: "private struct PlaybackControlButton"
        ))
        let playbackButton = try XCTUnwrap(source.slice(
            from: "private struct PlaybackControlButton",
            to: "private struct NextTrackButton"
        ))
        let nextButton = try XCTUnwrap(source.slice(
            from: "private struct NextTrackButton",
            to: "private struct RewindPlaybackButton"
        ))
        let rewindButton = try XCTUnwrap(source.slice(
            from: "private struct RewindPlaybackButton",
            to: "private struct VolumeDragBar"
        ))

        XCTAssertTrue(row.contains("PreviousTrackButton(process: process, store: store)"))
        XCTAssertTrue(row.contains("NextTrackButton(process: process, store: store)"))
        XCTAssertTrue(playbackButton.contains("process.playbackCapability.isControllable"))
        XCTAssertTrue(playbackButton.contains("store.togglePlayback(for: process)"))
        XCTAssertTrue(playbackButton.contains("store.isPlaybackPlaying(process) ? \"pause.fill\" : \"play.fill\""))
        XCTAssertTrue(playbackButton.contains(".font(.system(size: 14, weight: .semibold))"))
        XCTAssertTrue(playbackButton.contains(".frame(width: 22, height: 22)"))
        XCTAssertTrue(playbackButton.contains(".help(playbackHelpText)"))
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
        XCTAssertTrue(rewindButton.contains(".font(.system(size: 14, weight: .semibold))"))
        XCTAssertTrue(rewindButton.contains(".frame(width: 22, height: 22)"))
        XCTAssertTrue(rewindButton.contains(".help(\"Rewind 15 seconds\")"))
    }

    func testAudioProcessRowsDefaultMissingVolumeToFullVolume() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let displayedVolume = try XCTUnwrap(source.slice(
            from: "private var displayedVolume",
            to: "private var displayedBalance"
        ))

        XCTAssertTrue(displayedVolume.contains("process.currentVolume ?? 100"))
        XCTAssertFalse(displayedVolume.contains("process.currentVolume ?? 50"))
    }

    func testOutputSourceListIsExpandedByDefaultAndDoesNotScrollForSmallLists() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let sourceList = try XCTUnwrap(source.slice(
            from: "private struct OutputSourceListView",
            to: "private struct SourceReorderDropDelegate"
        ))

        XCTAssertTrue(sourceList.contains("@State private var isExpanded = true"))
        XCTAssertTrue(sourceList.contains("if isExpanded"))
        XCTAssertTrue(sourceList.contains("sourceRows"))
        XCTAssertTrue(sourceList.contains("VStack(spacing: 0)"))
        XCTAssertFalse(sourceList.contains("LazyVStack(spacing: 0)"))
    }

    func testEQPresetMenuCanSaveAndApplyCustomPresets() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct CaptureStripView"
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

    private func audioBarAppURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/App/AudioBarApp.swift")
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

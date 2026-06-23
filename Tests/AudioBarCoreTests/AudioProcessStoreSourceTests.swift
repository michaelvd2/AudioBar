import Foundation
import XCTest

final class AudioProcessStoreSourceTests: XCTestCase {
    func testEQEditsEnableTheEffectBeforeUpdatingEngine() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)

        for functionName in ["setEQGain", "setEQPreamp", "applyEQPreset"] {
            let function = try XCTUnwrap(source.function(named: functionName))
            XCTAssertTrue(function.contains("eqSettings.isBypassed = false"), functionName)
            XCTAssertTrue(function.contains("updateEQEngine()"), functionName)
        }
    }

    func testTurningEQOnRestartsTheRoute() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let function = try XCTUnwrap(source.function(named: "setEQBypassed"))

        XCTAssertTrue(source.contains("private let audioProcessStoreLogger"))
        XCTAssertTrue(function.contains("EQ bypass changed"))
        XCTAssertTrue(function.contains("restartEQEngine()"))
        XCTAssertTrue(function.contains("updateEQEngine()"))
    }

    func testEQEditsRecoverFailedRoutesInsteadOfOnlyUpdatingDeadProcessor() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let updateFunction = try XCTUnwrap(source.function(named: "updateEQEngine"))

        XCTAssertTrue(updateFunction.contains("eqEngineStatus.isFailure"))
        XCTAssertTrue(updateFunction.contains("startEQEngine()"))
        XCTAssertTrue(updateFunction.contains("return"))
    }

    func testRefreshRetriesFailedEQRouteAfterSourceListChanges() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let routeUpdateFunction = try XCTUnwrap(source.function(named: "updateEQSourceProcesses"))

        XCTAssertTrue(routeUpdateFunction.contains("recoverEQRouteIfNeeded()"))
        XCTAssertTrue(source.contains("private func recoverEQRouteIfNeeded()"))
    }

    func testUnavailableEQRoutesAreNotRetriedAsFailures() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let updateFunction = try XCTUnwrap(source.function(named: "updateEQEngine"))
        let recoverFunction = try XCTUnwrap(source.function(named: "recoverEQRouteIfNeeded"))

        XCTAssertTrue(updateFunction.contains("eqEngineStatus.isFailure"))
        XCTAssertFalse(updateFunction.contains("isUnavailable"))
        XCTAssertTrue(recoverFunction.contains("eqEngineStatus.isFailure"))
        XCTAssertFalse(recoverFunction.contains("isUnavailable"))
    }

    func testRefreshSyncsEQStatusAfterSourceRouteChangesBeforeRecovering() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let refreshFunction = try XCTUnwrap(source.function(named: "refresh"))

        let routeUpdateIndex = try XCTUnwrap(refreshFunction.range(of: "updateEQSourceProcesses(nextProcesses)")?.lowerBound)
        let publishIndex = try XCTUnwrap(refreshFunction.range(of: "processes = nextProcesses")?.lowerBound)

        XCTAssertLessThan(routeUpdateIndex, publishIndex)
        XCTAssertTrue(source.contains("private func updateEQSourceProcesses"))
        XCTAssertTrue(source.contains("eqEngineStatus = eqEngine.status"))
        XCTAssertTrue(source.contains("recoverEQRouteIfNeeded()"))
        XCTAssertTrue(source.contains("updateEQStreamSnapshot()"))
    }

    func testFirstUseSetupGatesAutomaticEQStartupUntilPermissionsAreRequested() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let startAutoRefreshFunction = try XCTUnwrap(source.function(named: "startAutoRefresh"))
        let completeSetupFunction = try XCTUnwrap(source.function(named: "completeFirstUseSetup"))

        XCTAssertTrue(source.contains("@Published private(set) var needsFirstUseSetup"))
        XCTAssertTrue(source.contains("private let firstUseSetupCompletedKey"))
        XCTAssertTrue(startAutoRefreshFunction.contains("if !needsFirstUseSetup"))
        XCTAssertTrue(completeSetupFunction.contains("requestGuidedPermissions()"))
        XCTAssertTrue(completeSetupFunction.contains("userDefaults.set(true, forKey: firstUseSetupCompletedKey)"))
        XCTAssertTrue(completeSetupFunction.contains("startEQEngine()"))
    }

    func testSourceListIsLoadedBeforeStartingEQRoute() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let startAutoRefreshFunction = try XCTUnwrap(source.function(named: "startAutoRefresh"))
        let completeSetupFunction = try XCTUnwrap(source.function(named: "completeFirstUseSetup"))

        let autoRefreshIndex = try XCTUnwrap(startAutoRefreshFunction.range(of: "refresh()")?.lowerBound)
        let autoStartIndex = try XCTUnwrap(startAutoRefreshFunction.range(of: "startEQEngine()")?.lowerBound)
        XCTAssertLessThan(autoRefreshIndex, autoStartIndex)

        let setupRefreshIndex = try XCTUnwrap(completeSetupFunction.range(of: "refresh()")?.lowerBound)
        let setupStartIndex = try XCTUnwrap(completeSetupFunction.range(of: "startEQEngine()")?.lowerBound)
        XCTAssertLessThan(setupRefreshIndex, setupStartIndex)
    }

    func testStoreRoutesLaunchAtLoginThroughLoginItemController() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setLaunchFunction = try XCTUnwrap(source.function(named: "setLaunchAtLoginEnabled"))
        let loginController = try String(contentsOf: loginItemControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("@Published private(set) var isLaunchAtLoginEnabled"))
        XCTAssertTrue(source.contains("private let loginItemController"))
        XCTAssertTrue(source.contains("private static let launchAtLoginPreferenceKey"))
        XCTAssertTrue(source.contains("Self.loadLaunchAtLoginPreference("))
        XCTAssertTrue(source.contains("key: Self.launchAtLoginPreferenceKey"))
        XCTAssertTrue(source.contains("loginItemController.setEnabled(preferredLaunchAtLogin)"))
        XCTAssertTrue(setLaunchFunction.contains("loginItemController.setEnabled(isEnabled)"))
        XCTAssertTrue(setLaunchFunction.contains("userDefaults.set(isLaunchAtLoginEnabled, forKey: Self.launchAtLoginPreferenceKey)"))
        XCTAssertTrue(setLaunchFunction.contains("isLaunchAtLoginEnabled = loginItemController.isEnabled"))
        XCTAssertTrue(loginController.contains("import ServiceManagement"))
        XCTAssertTrue(loginController.contains("SMAppService.mainApp"))
        XCTAssertTrue(loginController.contains(".register()"))
        XCTAssertTrue(loginController.contains(".unregister()"))
    }

    func testStorePersistsAndAppliesSavedEQPresets() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("@Published private(set) var savedEQPresets: [SavedEQPreset]"))
        XCTAssertTrue(source.contains("private let savedEQPresetsKey"))

        let saveFunction = try XCTUnwrap(source.function(named: "saveCurrentEQPreset"))
        XCTAssertTrue(saveFunction.contains("savedEQPresets.append"))
        XCTAssertTrue(saveFunction.contains("saveSavedEQPresets()"))

        let applyFunction = try XCTUnwrap(source.function(named: "applySavedEQPreset"))
        XCTAssertTrue(applyFunction.contains("eqSettings = preset.settings"))
        XCTAssertTrue(applyFunction.contains("eqSettings.isBypassed = false"))
        XCTAssertTrue(applyFunction.contains("updateEQEngine()"))
    }

    func testStoreKeepsPausedSourcesWithoutCountingThemActive() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private var processCache: AudioProcessListCache"))
        XCTAssertTrue(source.contains("AudioProcessListCache("))
        XCTAssertTrue(source.contains("persistedVolumes: Self.loadSourceVolumes"))

        let refreshFunction = try XCTUnwrap(source.function(named: "refresh"))
        let routeUpdateFunction = try XCTUnwrap(source.function(named: "updateEQSourceProcesses"))
        XCTAssertTrue(refreshFunction.contains("updateEQSourceProcesses(nextProcesses)"))
        XCTAssertTrue(routeUpdateFunction.contains("eqEngine.setSourceProcesses(processes)"))
        XCTAssertTrue(refreshFunction.contains("processCache.merge(activeProcesses: activeProcesses)"))
        XCTAssertTrue(refreshFunction.contains("activeProcesses.count"))
    }

    func testStorePersistsCommittedVolumeIntoProcessCache() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setVolumeFunction = try XCTUnwrap(source.function(named: "setVolume"))

        XCTAssertTrue(setVolumeFunction.contains("guard process.volumeCapability.isAdjustable else"))
        XCTAssertTrue(setVolumeFunction.contains("applyRouteVolume(volume, for: process)"))
        XCTAssertTrue(setVolumeFunction.contains("processCache.setCurrentVolume(volume, forStableSourceID: process.stableSourceID)"))
        XCTAssertTrue(setVolumeFunction.contains("saveSourceVolumes()"))
        XCTAssertTrue(setVolumeFunction.contains("processes[index].currentVolume = min(100, max(0, volume))"))
    }

    func testStorePersistsAndAppliesSourceBalance() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setBalanceFunction = try XCTUnwrap(source.function(named: "setBalance"))
        let updateRouteFunction = try XCTUnwrap(source.function(named: "updateEQSourceProcesses"))

        XCTAssertTrue(source.contains("@Published private(set) var sourceBalances"))
        XCTAssertTrue(source.contains("private let sourceBalancesKey"))
        XCTAssertTrue(source.contains("func balance(for process: AudioProcess) -> Int"))
        XCTAssertTrue(setBalanceFunction.contains("sourceBalances[process.stableSourceID] = balance"))
        XCTAssertTrue(setBalanceFunction.contains("eqEngine.setSourceBalance(balance, for: process.audioObjectID)"))
        XCTAssertTrue(setBalanceFunction.contains("saveSourceBalances()"))
        XCTAssertTrue(updateRouteFunction.contains("eqEngine.setSourceBalance(balance(for: process), for: process.audioObjectID)"))
    }

    func testStoreAppliesDefaultOutputBalanceFallbackWhenEQRouteIsUnavailable() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setBalanceFunction = try XCTUnwrap(source.function(named: "setBalance"))
        let fallbackFunction = try XCTUnwrap(source.function(named: "applyDefaultOutputBalanceFallback"))
        let resetFunction = try XCTUnwrap(source.function(named: "resetDefaultOutputBalanceFallbackIfNeeded"))

        XCTAssertTrue(source.contains("private let defaultOutputBalanceController"))
        XCTAssertTrue(setBalanceFunction.contains("applyDefaultOutputBalanceFallback(balance, for: process)"))
        XCTAssertTrue(fallbackFunction.contains("guard eqEngineStatus.isUnavailable else"))
        XCTAssertTrue(fallbackFunction.contains("defaultOutputBalanceController.apply(balance: balance)"))
        XCTAssertTrue(resetFunction.contains("defaultOutputBalanceController.apply(balance: 0)"))
    }

    func testStoreAppliesDefaultOutputVolumeFallbackForSystemRouteWhenEQRouteIsUnavailable() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let routeVolumeFunction = try XCTUnwrap(source.function(named: "applyRouteVolume"))
        let fallbackFunction = try XCTUnwrap(source.function(named: "applyDefaultOutputVolumeFallback"))

        XCTAssertTrue(routeVolumeFunction.contains("eqEngine.setSourceVolume(volume, for: process.audioObjectID)"))
        XCTAssertTrue(routeVolumeFunction.contains("eqEngineStatus = eqEngine.status"))
        XCTAssertTrue(routeVolumeFunction.contains("applyDefaultOutputVolumeFallback(volume, for: process)"))
        XCTAssertTrue(fallbackFunction.contains("guard process.volumeCapability == .systemRoute else"))
        XCTAssertTrue(fallbackFunction.contains("guard eqEngineStatus.isUnavailable else"))
        XCTAssertTrue(fallbackFunction.contains("defaultOutputBalanceController.apply(volume: volume, balance: balance(for: process))"))
    }

    func testStoreAppliesSafariMediaEQFallbackWhenEQRouteIsUnavailable() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let updateEQEngineFunction = try XCTUnwrap(source.function(named: "updateEQEngine"))
        let fallbackFunction = try XCTUnwrap(source.function(named: "applySafariMediaEQFallbackIfNeeded"))

        XCTAssertTrue(source.contains("private let safariMediaEQController"))
        XCTAssertTrue(updateEQEngineFunction.contains("applySafariMediaEQFallbackIfNeeded(for: processes)"))
        XCTAssertTrue(fallbackFunction.contains("guard eqEngineStatus.isUnavailable else"))
        XCTAssertTrue(fallbackFunction.contains("processes.contains(where: { $0.volumeCapability == .safariMedia })"))
        XCTAssertTrue(fallbackFunction.contains("safariMediaEQController.apply(settings: eqSettings)"))
        XCTAssertTrue(source.contains("safariMediaEQController.reset()"))
    }

    func testBPMSourceChangesAreDebouncedAndDoNotRestartAggregateEveryTick() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let activeSourcesFunction = try XCTUnwrap(source.function(named: "activeSourceObjectIDs"))
        let startFunction = try XCTUnwrap(source.function(named: "startBPMAnalysis"))
        let tickFunction = try XCTUnwrap(source.function(named: "updateBPMAnalysisTick"))

        XCTAssertTrue(source.contains("private var bpmSourceSetGate = BPMSourceSetGate("))
        XCTAssertTrue(activeSourcesFunction.contains("BPMSourceSetGate.normalized"))
        XCTAssertTrue(startFunction.contains("bpmSourceSetGate.reset(appliedSources: lastBPMSources)"))
        XCTAssertTrue(tickFunction.contains("bpmSourceSetGate.nextAppliedSources"))
        XCTAssertTrue(tickFunction.contains("bpmEngine.setSources(nextSources)"))
        XCTAssertFalse(tickFunction.contains("bpmEngine.start"))
    }

    func testStorePersistsAndAppliesSourceChannelMode() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let toggleFunction = try XCTUnwrap(source.function(named: "toggleChannelMode"))
        let updateRouteFunction = try XCTUnwrap(source.function(named: "updateEQSourceProcesses"))

        XCTAssertTrue(source.contains("@Published private(set) var monoSourceIDs"))
        XCTAssertTrue(source.contains("private let monoSourceIDsKey"))
        XCTAssertTrue(source.contains("func isMono(for process: AudioProcess) -> Bool"))
        XCTAssertTrue(source.contains("func channelModeLabel(for process: AudioProcess) -> String"))
        XCTAssertTrue(toggleFunction.contains("monoSourceIDs.contains(process.stableSourceID)"))
        XCTAssertTrue(toggleFunction.contains("eqEngine.setSourceMono(isMono(for: process), for: process.audioObjectID)"))
        XCTAssertTrue(toggleFunction.contains("saveMonoSourceIDs()"))
        XCTAssertTrue(updateRouteFunction.contains("eqEngine.setSourceMono(isMono(for: process), for: process.audioObjectID)"))
    }

    func testStorePersistsSourceVolumeMapInUserDefaults() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private let sourceVolumesKey"))
        XCTAssertTrue(source.contains("private func saveSourceVolumes()"))
        XCTAssertTrue(source.contains("private static func loadSourceVolumes"))
        XCTAssertTrue(source.contains("JSONEncoder().encode(processCache.persistedVolumes)"))
        XCTAssertTrue(source.contains("JSONDecoder().decode([String: Int].self"))
    }

    func testStorePersistsAndFiltersHiddenSources() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let refreshFunction = try XCTUnwrap(source.function(named: "refresh"))
        let hideFunction = try XCTUnwrap(source.function(named: "hideSource"))
        let restoreFunction = try XCTUnwrap(source.function(named: "restoreHiddenSource"))

        XCTAssertTrue(source.contains("@Published private(set) var hiddenSources: [HiddenAudioSource]"))
        XCTAssertTrue(source.contains("private let hiddenSourcesKey"))
        XCTAssertTrue(refreshFunction.contains("filter { !isHiddenSource($0) }"))
        XCTAssertTrue(hideFunction.contains("hiddenSourceNames[process.stableSourceID] = process.displayTitle"))
        XCTAssertTrue(hideFunction.contains("saveHiddenSources()"))
        XCTAssertTrue(hideFunction.contains("updateEQSourceProcesses(processes)"))
        XCTAssertFalse(hideFunction.contains("eqEngine.setSourceProcesses(processes)"))
        XCTAssertTrue(restoreFunction.contains("hiddenSourceNames.removeValue(forKey: sourceID)"))
        XCTAssertTrue(restoreFunction.contains("refresh()"))
    }

    func testStorePreviewsRouteVolumeWithoutRunningAppScripts() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let previewFunction = try XCTUnwrap(source.function(named: "previewVolume"))

        XCTAssertTrue(previewFunction.contains("guard process.volumeCapability.isAdjustable else"))
        XCTAssertTrue(previewFunction.contains("applyRouteVolume(volume, for: process)"))
        XCTAssertFalse(previewFunction.contains("volumeController.setVolume"))
        XCTAssertFalse(previewFunction.contains("safariMediaVolumeController.setVolume"))
    }

    func testStoreRoutesSafariMediaVolumeToSafariController() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setVolumeFunction = try XCTUnwrap(source.function(named: "setVolume"))

        XCTAssertTrue(source.contains("private let safariMediaVolumeController"))
        XCTAssertTrue(setVolumeFunction.contains("case .systemRoute:"))
        XCTAssertTrue(setVolumeFunction.contains("didSet = true"))
        XCTAssertTrue(setVolumeFunction.contains("case .safariMedia:"))
        XCTAssertTrue(setVolumeFunction.contains("didSet = safariMediaVolumeController.setVolume(volume)"))
    }

    func testStoreRoutesPlaybackToggleBySourceCapability() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let togglePlaybackFunction = try XCTUnwrap(source.function(named: "togglePlayback"))

        XCTAssertTrue(source.contains("private let playbackController"))
        XCTAssertTrue(togglePlaybackFunction.contains("guard process.playbackCapability.isControllable else"))
        XCTAssertTrue(togglePlaybackFunction.contains("playbackController.togglePlayback(for: process)"))
    }

    func testStoreRoutesFifteenSecondRewindBySourceCapability() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let rewindFunction = try XCTUnwrap(source.function(named: "rewindPlayback"))

        XCTAssertTrue(rewindFunction.contains("guard process.playbackCapability.isControllable else"))
        XCTAssertTrue(rewindFunction.contains("playbackController.rewind15Seconds(for: process)"))
    }

    func testStoreRoutesTrackNavigationBySourceCapability() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let previousFunction = try XCTUnwrap(source.function(named: "previousTrack"))
        let nextFunction = try XCTUnwrap(source.function(named: "nextTrack"))

        XCTAssertTrue(previousFunction.contains("guard process.playbackCapability.isControllable else"))
        XCTAssertTrue(previousFunction.contains("playbackController.previousTrack(for: process)"))
        XCTAssertTrue(nextFunction.contains("guard process.playbackCapability.isControllable else"))
        XCTAssertTrue(nextFunction.contains("playbackController.nextTrack(for: process)"))
    }

    func testPlaybackToggleUpdatesDisplayedPlaybackStateImmediately() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let togglePlaybackFunction = try XCTUnwrap(source.function(named: "togglePlayback"))
        let isPlayingFunction = try XCTUnwrap(source.function(named: "isPlaybackPlaying"))

        XCTAssertTrue(source.contains("private var playbackStateOverrides: [String: Bool]"))
        XCTAssertTrue(togglePlaybackFunction.contains("guard playbackController.togglePlayback(for: process) else"))
        XCTAssertTrue(togglePlaybackFunction.contains("let intendedPlaying = !isPlaybackPlaying(process)"))
        XCTAssertTrue(togglePlaybackFunction.contains("playbackStateOverrides[process.stableSourceID] = intendedPlaying"))
        XCTAssertTrue(isPlayingFunction.contains("playbackStateOverrides[process.stableSourceID] ?? process.isActiveOutput"))
    }

    func testWebAppPlaybackUsesBackgroundMediaKeyInsteadOfActivatingWebApp() throws {
        let source = try String(contentsOf: sourcePlaybackControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private let nowPlayingController"))
        XCTAssertTrue(source.contains("nowPlayingController.togglePlayPause()"))
        XCTAssertTrue(source.contains("WebAppKeyboardPlaybackCommandBuilder.previousTrackScript"))
        XCTAssertTrue(source.contains("WebAppKeyboardPlaybackCommandBuilder.nextTrackScript"))
        XCTAssertTrue(source.contains("MRMediaRemoteSendCommand"))
        XCTAssertTrue(source.contains("let togglePlayPauseCommand: Int32 = 2"))
        XCTAssertTrue(source.contains("let goBackFifteenSecondsCommand: Int32 = 12"))
        XCTAssertTrue(source.contains("public func rewind15Seconds() -> Bool"))
        XCTAssertTrue(source.contains("sendCommand(goBackFifteenSecondsCommand"))
        XCTAssertTrue(source.contains("private let mediaKeyController"))
        XCTAssertTrue(source.contains("mediaKeyController.togglePlayPause()"))
        XCTAssertTrue(source.contains("CGPreflightListenEventAccess()"))
        XCTAssertTrue(source.contains("CGRequestListenEventAccess()"))
        XCTAssertFalse(source.contains("key code 40"))
        XCTAssertFalse(source.contains("key code 49"))
    }

    func testStoreNotifiesBeforeExternalCommandCanMoveAppFocus() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let setVolumeFunction = try XCTUnwrap(source.function(named: "setVolume"))
        let previousFunction = try XCTUnwrap(source.function(named: "previousTrack"))
        let nextFunction = try XCTUnwrap(source.function(named: "nextTrack"))

        XCTAssertTrue(source.contains("extension Notification.Name"))
        XCTAssertTrue(source.contains("audioBarWillRunExternalFocusCommand"))
        XCTAssertTrue(setVolumeFunction.contains("notifyExternalFocusCommandIfNeeded(for: process)"))
        XCTAssertTrue(previousFunction.contains("notifyExternalFocusCommandIfNeeded(for: process)"))
        XCTAssertTrue(nextFunction.contains("notifyExternalFocusCommandIfNeeded(for: process)"))
        XCTAssertTrue(source.contains("private func notifyExternalFocusCommandIfNeeded"))
        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .audioBarWillRunExternalFocusCommand, object: self)"))
    }

    private func audioProcessStoreURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/Stores/AudioProcessStore.swift")
    }

    private func sourcePlaybackControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/SourcePlaybackController.swift")
    }

    private func loginItemControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/Services/LoginItemController.swift")
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

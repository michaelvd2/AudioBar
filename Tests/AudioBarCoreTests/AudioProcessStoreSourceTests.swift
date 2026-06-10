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
        let refreshFunction = try XCTUnwrap(source.function(named: "refresh"))

        XCTAssertTrue(refreshFunction.contains("recoverEQRouteIfNeeded()"))
        XCTAssertTrue(source.contains("private func recoverEQRouteIfNeeded()"))
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
        XCTAssertTrue(refreshFunction.contains("eqEngine.setSourceProcesses(nextProcesses)"))
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

    func testWebAppPlaybackUsesBackgroundMediaKeyInsteadOfActivatingWebApp() throws {
        let source = try String(contentsOf: sourcePlaybackControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private let mediaKeyController"))
        XCTAssertTrue(source.contains("mediaKeyController.togglePlayPause()"))
        XCTAssertTrue(source.contains("CGPreflightListenEventAccess()"))
        XCTAssertTrue(source.contains("CGRequestListenEventAccess()"))
        XCTAssertFalse(source.contains("WebAppKeyboardPlaybackCommandBuilder"))
        XCTAssertFalse(source.contains("to activate"))
        XCTAssertFalse(source.contains("key code 40"))
        XCTAssertFalse(source.contains("key code 49"))
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

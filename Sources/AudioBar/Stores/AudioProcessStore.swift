import AppKit
import AudioBarCore
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import OSLog

private let audioProcessStoreLogger = Logger(
    subsystem: "com.michaelvandijk.AudioBar",
    category: "AudioProcessStore"
)

extension Notification.Name {
    static let audioBarWillRunExternalFocusCommand = Notification.Name("AudioBarWillRunExternalFocusCommand")
}

struct HiddenAudioSource: Equatable, Identifiable {
    let id: String
    let name: String
}

@MainActor
final class AudioProcessStore: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var statusMessage = "Waiting for audio"
    @Published private(set) var eqSettings: EQSettings
    @Published private(set) var eqEngineStatus: SystemEQEngineStatus = .stopped
    @Published private(set) var eqStreamSnapshot: SystemAudioStreamSnapshot = .inactive
    @Published private(set) var needsFirstUseSetup: Bool
    @Published private(set) var isLaunchAtLoginEnabled: Bool
    @Published private(set) var savedEQPresets: [SavedEQPreset]
    @Published private(set) var hiddenSources: [HiddenAudioSource]
    @Published private(set) var sourceBalances: [String: Int]
    @Published private(set) var monoSourceIDs: Set<String>

    private let provider: AudioProcessProviding
    private let volumeController: AppVolumeControlling
    private let webAppVolumeController: WebAppKeyboardVolumeController
    private let safariMediaVolumeController: SafariMediaVolumeController
    private let safariMediaEQController: SafariMediaEQController
    private let playbackController: SourcePlaybackController
    private let loginItemController: LoginItemController
    private let eqEngine: SystemEQEngine
    private let defaultOutputBalanceController: DefaultOutputBalanceController
    private let userDefaults: UserDefaults
    private var timer: Timer?
    private var streamTimer: Timer?
    private let eqSettingsKey = "AudioBar.eqSettings"
    private let savedEQPresetsKey = "AudioBar.savedEQPresets"
    private let sourceVolumesKey = "AudioBar.sourceVolumes"
    private let sourceBalancesKey = "AudioBar.sourceBalances"
    private let monoSourceIDsKey = "AudioBar.monoSourceIDs"
    private let hiddenSourcesKey = "AudioBar.hiddenSources"
    private let firstUseSetupCompletedKey = "AudioBar.firstUseSetupCompleted"
    private var processCache: AudioProcessListCache
    private var hiddenSourceNames: [String: String]
    private var playbackStateOverrides: [String: Bool] = [:]
    private var defaultOutputBalanceFallbackSourceID: String?
    private var isSafariMediaEQFallbackActive = false

    init(
        volumeController: AppVolumeControlling = ScriptedAppVolumeController(),
        webAppVolumeController: WebAppKeyboardVolumeController = WebAppKeyboardVolumeController(),
        safariMediaVolumeController: SafariMediaVolumeController = SafariMediaVolumeController(),
        safariMediaEQController: SafariMediaEQController = SafariMediaEQController(),
        playbackController: SourcePlaybackController = SourcePlaybackController(),
        loginItemController: LoginItemController = LoginItemController(),
        provider: AudioProcessProviding? = nil,
        eqEngine: SystemEQEngine = SystemEQEngine(),
        defaultOutputBalanceController: DefaultOutputBalanceController = DefaultOutputBalanceController(),
        userDefaults: UserDefaults = .standard
    ) {
        self.volumeController = volumeController
        self.webAppVolumeController = webAppVolumeController
        self.safariMediaVolumeController = safariMediaVolumeController
        self.safariMediaEQController = safariMediaEQController
        self.playbackController = playbackController
        self.loginItemController = loginItemController
        self.provider = provider ?? CoreAudioProcessProvider(volumeController: volumeController)
        self.eqEngine = eqEngine
        self.defaultOutputBalanceController = defaultOutputBalanceController
        self.userDefaults = userDefaults
        self.eqSettings = Self.loadEQSettings(from: userDefaults, key: eqSettingsKey)
        self.needsFirstUseSetup = !userDefaults.bool(forKey: firstUseSetupCompletedKey)
        self.isLaunchAtLoginEnabled = loginItemController.isEnabled
        self.savedEQPresets = Self.loadSavedEQPresets(from: userDefaults, key: savedEQPresetsKey)
        self.sourceBalances = Self.loadSourceBalances(from: userDefaults, key: sourceBalancesKey)
        self.monoSourceIDs = Self.loadMonoSourceIDs(from: userDefaults, key: monoSourceIDsKey)
        self.hiddenSourceNames = Self.loadHiddenSources(from: userDefaults, key: hiddenSourcesKey)
        self.hiddenSources = Self.makeHiddenSources(from: hiddenSourceNames)
        self.processCache = AudioProcessListCache(
            persistedVolumes: Self.loadSourceVolumes(from: userDefaults, key: sourceVolumesKey)
        )
    }

    deinit {
        if defaultOutputBalanceFallbackSourceID != nil {
            _ = defaultOutputBalanceController.apply(balance: 0)
        }
        if isSafariMediaEQFallbackActive {
            _ = safariMediaEQController.reset()
        }
    }

    func startAutoRefresh() {
        guard timer == nil else {
            return
        }
        refresh()
        if !needsFirstUseSetup {
            startEQEngine()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateEQStreamSnapshot()
            }
        }
    }

    func completeFirstUseSetup() {
        needsFirstUseSetup = false
        userDefaults.set(true, forKey: firstUseSetupCompletedKey)
        requestGuidedPermissions()
        refresh()
        startEQEngine()
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        streamTimer?.invalidate()
        streamTimer = nil
    }

    private var displayOrder: [String] = []
    private var lastTrackTitles: [String: String] = [:]

    private func orderedByFirstSeen(_ sources: [AudioProcess]) -> [AudioProcess] {
        for source in sources where !displayOrder.contains(source.stableSourceID) {
            displayOrder.append(source.stableSourceID)
        }
        for source in sources where !source.sourceDetailLabel.isEmpty {
            lastTrackTitles[source.stableSourceID] = source.sourceDetailLabel
        }
        return sources.sorted { lhs, rhs in
            (displayOrder.firstIndex(of: lhs.stableSourceID) ?? Int.max)
                < (displayOrder.firstIndex(of: rhs.stableSourceID) ?? Int.max)
        }
    }

    func sourceDetail(for process: AudioProcess) -> String {
        let live = process.sourceDetailLabel
        if !live.isEmpty {
            return live
        }
        return lastTrackTitles[process.stableSourceID] ?? ""
    }

    func moveSource(withID draggedID: String, aboveID targetID: String) {
        guard draggedID != targetID,
              let fromIndex = displayOrder.firstIndex(of: draggedID) else {
            return
        }
        displayOrder.remove(at: fromIndex)
        if let targetIndex = displayOrder.firstIndex(of: targetID) {
            displayOrder.insert(draggedID, at: targetIndex)
        } else {
            displayOrder.append(draggedID)
        }
        processes = processes.sorted { lhs, rhs in
            (displayOrder.firstIndex(of: lhs.stableSourceID) ?? Int.max)
                < (displayOrder.firstIndex(of: rhs.stableSourceID) ?? Int.max)
        }
    }

    func refresh() {
        isRefreshing = true
        playbackStateOverrides.removeAll()
        let activeProcesses = provider.activeOutputProcesses()
        let nextProcesses = orderedByFirstSeen(
            processCache.merge(activeProcesses: activeProcesses)
                .filter { !isHiddenSource($0) }
        )
        updateEQSourceProcesses(nextProcesses)
        processes = nextProcesses
        applySafariMediaEQFallbackIfNeeded(for: nextProcesses)
        lastRefreshDate = Date()
        statusMessage = activeProcesses.isEmpty ? "No active output detected" : "\(activeProcesses.count) active"
        isRefreshing = false
    }

    func hideSource(_ process: AudioProcess) {
        hiddenSourceNames[process.stableSourceID] = process.displayTitle
        updateHiddenSources()
        saveHiddenSources()
        processes.removeAll { isHiddenSource($0) }
        updateEQSourceProcesses(processes)
    }

    func restoreHiddenSource(_ sourceID: String) {
        hiddenSourceNames.removeValue(forKey: sourceID)
        updateHiddenSources()
        saveHiddenSources()
        refresh()
    }

    func setVolume(for process: AudioProcess, to value: Double) {
        let volume = Int(value.rounded())
        guard process.volumeCapability.isAdjustable else {
            return
        }

        applyRouteVolume(volume, for: process)

        let didSet: Bool
        switch process.volumeCapability {
        case .systemRoute:
            didSet = true
        case .scripted:
            notifyExternalFocusCommandIfNeeded(for: process)
            didSet = volumeController.setVolume(volume, for: process.bundleID)
        case .webAppKeyboard:
            notifyExternalFocusCommandIfNeeded(for: process)
            didSet = webAppVolumeController.setVolume(volume, for: process.volumeControlID)
        case .safariMedia:
            notifyExternalFocusCommandIfNeeded(for: process)
            didSet = safariMediaVolumeController.setVolume(volume)
        case .unavailable:
            didSet = false
        }
        _ = didSet

        processCache.setCurrentVolume(volume, forStableSourceID: process.stableSourceID)
        saveSourceVolumes()
        if let index = processes.firstIndex(where: { $0.id == process.id }) {
            processes[index].currentVolume = min(100, max(0, volume))
        }
    }

    func previewVolume(for process: AudioProcess, to value: Double) {
        let volume = Int(value.rounded())
        guard process.volumeCapability.isAdjustable else {
            return
        }

        applyRouteVolume(volume, for: process)
        if let index = processes.firstIndex(where: { $0.id == process.id }) {
            processes[index].currentVolume = min(100, max(0, volume))
        }
    }

    func balance(for process: AudioProcess) -> Int {
        sourceBalances[process.stableSourceID] ?? 0
    }

    func setBalance(for process: AudioProcess, to value: Double) {
        let balance = Self.clampBalance(Int(value.rounded()))
        sourceBalances[process.stableSourceID] = balance
        eqEngineStatus = eqEngine.status
        eqEngine.setSourceBalance(balance, for: process.audioObjectID)
        applyDefaultOutputBalanceFallback(balance, for: process)
        saveSourceBalances()
    }

    func isMono(for process: AudioProcess) -> Bool {
        monoSourceIDs.contains(process.stableSourceID)
    }

    func channelModeLabel(for process: AudioProcess) -> String {
        isMono(for: process) ? "Mono" : "Stereo"
    }

    func toggleChannelMode(for process: AudioProcess) {
        if monoSourceIDs.contains(process.stableSourceID) {
            monoSourceIDs.remove(process.stableSourceID)
        } else {
            monoSourceIDs.insert(process.stableSourceID)
        }
        eqEngine.setSourceMono(isMono(for: process), for: process.audioObjectID)
        saveMonoSourceIDs()
    }

    func togglePlayback(for process: AudioProcess) {
        guard process.playbackCapability.isControllable else {
            return
        }

        guard playbackController.togglePlayback(for: process) else {
            return
        }

        let intendedPlaying = !isPlaybackPlaying(process)
        refresh()
        playbackStateOverrides[process.stableSourceID] = intendedPlaying
    }

    func rewindPlayback(for process: AudioProcess) {
        guard process.playbackCapability.isControllable else {
            return
        }

        _ = playbackController.rewind15Seconds(for: process)
    }

    func previousTrack(for process: AudioProcess) {
        guard process.playbackCapability.isControllable else {
            return
        }

        notifyExternalFocusCommandIfNeeded(for: process)
        _ = playbackController.previousTrack(for: process)
    }

    func nextTrack(for process: AudioProcess) {
        guard process.playbackCapability.isControllable else {
            return
        }

        notifyExternalFocusCommandIfNeeded(for: process)
        _ = playbackController.nextTrack(for: process)
    }

    func isPlaybackPlaying(_ process: AudioProcess) -> Bool {
        playbackStateOverrides[process.stableSourceID] ?? process.isActiveOutput
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        loginItemController.setEnabled(isEnabled)
        isLaunchAtLoginEnabled = loginItemController.isEnabled
    }

    func setEQGain(_ gain: Double, for frequencyHz: Int) {
        eqSettings.setGain(gain, for: frequencyHz)
        eqSettings.isBypassed = false
        saveEQSettings()
        updateEQEngine()
    }

    func setEQPreamp(_ gain: Double) {
        eqSettings.preampDB = EQSettings.clamp(gain)
        eqSettings.isBypassed = false
        saveEQSettings()
        updateEQEngine()
    }

    func setEQBypassed(_ isBypassed: Bool) {
        eqSettings.isBypassed = isBypassed
        saveEQSettings()
        audioProcessStoreLogger.info("EQ bypass changed: \(isBypassed)")
        if isBypassed {
            updateEQEngine()
        } else {
            restartEQEngine()
        }
    }

    func applyEQPreset(_ preset: EQPreset) {
        eqSettings.apply(preset)
        eqSettings.isBypassed = false
        saveEQSettings()
        updateEQEngine()
    }

    func applySavedEQPreset(_ preset: SavedEQPreset) {
        eqSettings = preset.settings
        eqSettings.isBypassed = false
        saveEQSettings()
        updateEQEngine()
    }

    func saveCurrentEQPreset(named name: String) {
        let cleanName = sanitizedPresetName(name)
        guard !cleanName.isEmpty else {
            return
        }

        var settings = eqSettings
        settings.isBypassed = false
        savedEQPresets.removeAll { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }
        savedEQPresets.append(SavedEQPreset(name: cleanName, settings: settings))
        saveSavedEQPresets()
    }

    func nextSavedEQPresetName() -> String {
        var index = savedEQPresets.count + 1
        var name = "Custom \(index)"
        while savedEQPresets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            index += 1
            name = "Custom \(index)"
        }
        return name
    }

    func resetEQ() {
        eqSettings.reset()
        saveEQSettings()
        updateEQEngine()
    }

    func startEQEngine() {
        guard !needsFirstUseSetup else {
            eqEngineStatus = .stopped
            updateEQStreamSnapshot()
            return
        }
        eqEngineStatus = .starting
        eqEngineStatus = eqEngine.start(settings: eqSettings)
        resetDefaultOutputBalanceFallbackIfRouteIsAvailable()
        updateEQStreamSnapshot()
    }

    func stopEQEngine() {
        eqEngine.stop()
        eqEngineStatus = eqEngine.status
        resetDefaultOutputBalanceFallbackIfNeeded()
        updateEQStreamSnapshot()
    }

    private func restartEQEngine() {
        eqEngine.stop()
        startEQEngine()
    }

    private func updateEQSourceProcesses(_ processes: [AudioProcess]) {
        eqEngine.setSourceProcesses(processes)
        for process in processes {
            eqEngine.setSourceBalance(balance(for: process), for: process.audioObjectID)
            eqEngine.setSourceMono(isMono(for: process), for: process.audioObjectID)
        }
        eqEngineStatus = eqEngine.status
        resetDefaultOutputBalanceFallbackIfRouteIsAvailable()
        applySafariMediaEQFallbackIfNeeded(for: processes)
        recoverEQRouteIfNeeded()
        updateEQStreamSnapshot()
    }

    private func updateEQEngine() {
        if eqEngineStatus.isFailure {
            guard !eqSettings.isBypassed else {
                updateEQStreamSnapshot()
                return
            }
            startEQEngine()
            return
        }

        guard eqEngineStatus != .stopped else {
            if eqSettings.isBypassed {
                updateEQStreamSnapshot()
            } else {
                startEQEngine()
            }
            return
        }
        eqEngine.update(settings: eqSettings)
        eqEngineStatus = eqEngine.status
        resetDefaultOutputBalanceFallbackIfRouteIsAvailable()
        applySafariMediaEQFallbackIfNeeded(for: processes)
        updateEQStreamSnapshot()
    }

    private func recoverEQRouteIfNeeded() {
        guard eqEngineStatus.isFailure, !eqSettings.isBypassed else {
            return
        }
        startEQEngine()
    }

    private func updateEQStreamSnapshot() {
        eqStreamSnapshot = eqEngine.streamSnapshot
    }

    private func applyRouteVolume(_ volume: Int, for process: AudioProcess) {
        eqEngine.setSourceVolume(volume, for: process.audioObjectID)
        eqEngineStatus = eqEngine.status
        applyDefaultOutputVolumeFallback(volume, for: process)
    }

    private func applyDefaultOutputBalanceFallback(_ balance: Int, for process: AudioProcess) {
        guard eqEngineStatus.isUnavailable else {
            resetDefaultOutputBalanceFallbackIfNeeded()
            return
        }
        if defaultOutputBalanceController.apply(balance: balance) {
            defaultOutputBalanceFallbackSourceID = process.stableSourceID
        }
    }

    private func applyDefaultOutputVolumeFallback(_ volume: Int, for process: AudioProcess) {
        guard process.volumeCapability == .systemRoute else {
            return
        }
        guard eqEngineStatus.isUnavailable else {
            return
        }
        _ = defaultOutputBalanceController.apply(volume: volume, balance: balance(for: process))
    }

    private func resetDefaultOutputBalanceFallbackIfNeeded() {
        guard defaultOutputBalanceFallbackSourceID != nil else {
            return
        }
        _ = defaultOutputBalanceController.apply(balance: 0)
        defaultOutputBalanceFallbackSourceID = nil
    }

    private func resetDefaultOutputBalanceFallbackIfRouteIsAvailable() {
        guard !eqEngineStatus.isUnavailable else {
            return
        }
        resetDefaultOutputBalanceFallbackIfNeeded()
    }

    private func applySafariMediaEQFallbackIfNeeded(for processes: [AudioProcess]) {
        guard eqEngineStatus.isUnavailable else {
            resetSafariMediaEQFallbackIfNeeded()
            return
        }
        guard processes.contains(where: { $0.volumeCapability == .safariMedia }) else {
            resetSafariMediaEQFallbackIfNeeded()
            return
        }
        if eqSettings.isBypassed {
            resetSafariMediaEQFallbackIfNeeded()
            return
        }
        if safariMediaEQController.apply(settings: eqSettings) {
            isSafariMediaEQFallbackActive = true
        }
    }

    private func resetSafariMediaEQFallbackIfNeeded() {
        guard isSafariMediaEQFallbackActive else {
            return
        }
        _ = safariMediaEQController.reset()
        isSafariMediaEQFallbackActive = false
    }

    private func notifyExternalFocusCommandIfNeeded(for process: AudioProcess) {
        switch process.volumeCapability {
        case .scripted, .webAppKeyboard, .safariMedia:
            NotificationCenter.default.post(name: .audioBarWillRunExternalFocusCommand, object: self)
        case .systemRoute, .unavailable:
            break
        }
    }

    func requestPermissions() {
        requestGuidedPermissions()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestGuidedPermissions() {
        _ = CGRequestListenEventAccess()

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func isHiddenSource(_ process: AudioProcess) -> Bool {
        hiddenSourceNames[process.stableSourceID] != nil
    }

    private func updateHiddenSources() {
        hiddenSources = Self.makeHiddenSources(from: hiddenSourceNames)
    }

    private func saveEQSettings() {
        guard let data = try? JSONEncoder().encode(eqSettings) else {
            return
        }
        userDefaults.set(data, forKey: eqSettingsKey)
    }

    private func saveSavedEQPresets() {
        guard let data = try? JSONEncoder().encode(savedEQPresets) else {
            return
        }
        userDefaults.set(data, forKey: savedEQPresetsKey)
    }

    private func saveSourceVolumes() {
        guard let data = try? JSONEncoder().encode(processCache.persistedVolumes) else {
            return
        }
        userDefaults.set(data, forKey: sourceVolumesKey)
    }

    private func saveSourceBalances() {
        guard let data = try? JSONEncoder().encode(sourceBalances) else {
            return
        }
        userDefaults.set(data, forKey: sourceBalancesKey)
    }

    private func saveMonoSourceIDs() {
        guard let data = try? JSONEncoder().encode(monoSourceIDs) else {
            return
        }
        userDefaults.set(data, forKey: monoSourceIDsKey)
    }

    private func saveHiddenSources() {
        guard let data = try? JSONEncoder().encode(hiddenSourceNames) else {
            return
        }
        userDefaults.set(data, forKey: hiddenSourcesKey)
    }

    private func sanitizedPresetName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
    }

    private static func loadEQSettings(from userDefaults: UserDefaults, key: String) -> EQSettings {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(EQSettings.self, from: data)
        else {
            return .flat
        }
        return settings
    }

    private static func loadSavedEQPresets(from userDefaults: UserDefaults, key: String) -> [SavedEQPreset] {
        guard let data = userDefaults.data(forKey: key),
              let presets = try? JSONDecoder().decode([SavedEQPreset].self, from: data)
        else {
            return []
        }
        return presets
    }

    private static func loadSourceVolumes(from userDefaults: UserDefaults, key: String) -> [String: Int] {
        guard let data = userDefaults.data(forKey: key),
              let volumes = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        return volumes.mapValues { min(100, max(0, $0)) }
    }

    private static func loadSourceBalances(from userDefaults: UserDefaults, key: String) -> [String: Int] {
        guard let data = userDefaults.data(forKey: key),
              let balances = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        return balances.mapValues(clampBalance)
    }

    private static func loadMonoSourceIDs(from userDefaults: UserDefaults, key: String) -> Set<String> {
        guard let data = userDefaults.data(forKey: key),
              let sourceIDs = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return []
        }
        return sourceIDs
    }

    private static func clampBalance(_ balance: Int) -> Int {
        min(100, max(-100, balance))
    }

    private static func loadHiddenSources(from userDefaults: UserDefaults, key: String) -> [String: String] {
        guard let data = userDefaults.data(forKey: key),
              let sources = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return sources
    }

    private static func makeHiddenSources(from hiddenSourceNames: [String: String]) -> [HiddenAudioSource] {
        hiddenSourceNames
            .map { HiddenAudioSource(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

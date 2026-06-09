import AudioBarCore
import Combine
import Foundation

@MainActor
final class AudioProcessStore: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var statusMessage = "Waiting for audio"
    @Published private(set) var eqSettings: EQSettings
    @Published private(set) var eqEngineStatus: SystemEQEngineStatus = .stopped
    @Published private(set) var eqStreamSnapshot: SystemAudioStreamSnapshot = .inactive
    @Published private(set) var savedEQPresets: [SavedEQPreset]

    private let provider: AudioProcessProviding
    private let volumeController: AppVolumeControlling
    private let webAppVolumeController: WebAppKeyboardVolumeController
    private let safariMediaVolumeController: SafariMediaVolumeController
    private let eqEngine: SystemEQEngine
    private let userDefaults: UserDefaults
    private var timer: Timer?
    private var streamTimer: Timer?
    private let eqSettingsKey = "AudioBar.eqSettings"
    private let savedEQPresetsKey = "AudioBar.savedEQPresets"
    private var processCache = AudioProcessListCache()

    init(
        volumeController: AppVolumeControlling = ScriptedAppVolumeController(),
        webAppVolumeController: WebAppKeyboardVolumeController = WebAppKeyboardVolumeController(),
        safariMediaVolumeController: SafariMediaVolumeController = SafariMediaVolumeController(),
        provider: AudioProcessProviding? = nil,
        eqEngine: SystemEQEngine = SystemEQEngine(),
        userDefaults: UserDefaults = .standard
    ) {
        self.volumeController = volumeController
        self.webAppVolumeController = webAppVolumeController
        self.safariMediaVolumeController = safariMediaVolumeController
        self.provider = provider ?? CoreAudioProcessProvider(volumeController: volumeController)
        self.eqEngine = eqEngine
        self.userDefaults = userDefaults
        self.eqSettings = Self.loadEQSettings(from: userDefaults, key: eqSettingsKey)
        self.savedEQPresets = Self.loadSavedEQPresets(from: userDefaults, key: savedEQPresetsKey)
    }

    func startAutoRefresh() {
        guard timer == nil else {
            return
        }
        startEQEngine()
        refresh()
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

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        streamTimer?.invalidate()
        streamTimer = nil
    }

    func refresh() {
        isRefreshing = true
        let activeProcesses = provider.activeOutputProcesses()
        let nextProcesses = processCache.merge(activeProcesses: activeProcesses)
        processes = nextProcesses
        lastRefreshDate = Date()
        statusMessage = activeProcesses.isEmpty ? "No active output detected" : "\(activeProcesses.count) active"
        isRefreshing = false
    }

    func setVolume(for process: AudioProcess, to value: Double) {
        let volume = Int(value.rounded())
        guard process.volumeCapability.isAdjustable else {
            return
        }

        let didSet: Bool
        switch process.volumeCapability {
        case .scripted:
            didSet = volumeController.setVolume(volume, for: process.bundleID)
        case .webAppKeyboard:
            didSet = webAppVolumeController.setVolume(volume, for: process.volumeControlID)
        case .safariMedia:
            didSet = safariMediaVolumeController.setVolume(volume)
        case .unavailable:
            didSet = false
        }
        _ = didSet

        processCache.setCurrentVolume(volume, forStableSourceID: process.stableSourceID)
        if let index = processes.firstIndex(where: { $0.id == process.id }) {
            processes[index].currentVolume = min(100, max(0, volume))
        }
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
        eqEngineStatus = .starting
        eqEngineStatus = eqEngine.start(settings: eqSettings)
        updateEQStreamSnapshot()
    }

    func stopEQEngine() {
        eqEngine.stop()
        eqEngineStatus = eqEngine.status
        updateEQStreamSnapshot()
    }

    private func restartEQEngine() {
        eqEngine.stop()
        startEQEngine()
    }

    private func updateEQEngine() {
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
        updateEQStreamSnapshot()
    }

    private func updateEQStreamSnapshot() {
        eqStreamSnapshot = eqEngine.streamSnapshot
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
}

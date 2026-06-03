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

    private let provider: AudioProcessProviding
    private let volumeController: AppVolumeControlling
    private let webAppVolumeController: WebAppKeyboardVolumeController
    private let eqEngine: SystemEQEngine
    private let userDefaults: UserDefaults
    private var timer: Timer?
    private var streamTimer: Timer?
    private let eqSettingsKey = "AudioBar.eqSettings"

    init(
        volumeController: AppVolumeControlling = ScriptedAppVolumeController(),
        webAppVolumeController: WebAppKeyboardVolumeController = WebAppKeyboardVolumeController(),
        provider: AudioProcessProviding? = nil,
        eqEngine: SystemEQEngine = SystemEQEngine(),
        userDefaults: UserDefaults = .standard
    ) {
        self.volumeController = volumeController
        self.webAppVolumeController = webAppVolumeController
        self.provider = provider ?? CoreAudioProcessProvider(volumeController: volumeController)
        self.eqEngine = eqEngine
        self.userDefaults = userDefaults
        self.eqSettings = Self.loadEQSettings(from: userDefaults, key: eqSettingsKey)
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
        let nextProcesses = provider.activeOutputProcesses()
        processes = nextProcesses
        lastRefreshDate = Date()
        statusMessage = nextProcesses.isEmpty ? "No active output detected" : "\(nextProcesses.count) active"
        isRefreshing = false
    }

    func setVolume(for process: AudioProcess, to value: Double) {
        let volume = Int(value.rounded())
        let didSet: Bool
        switch process.volumeCapability {
        case .scripted:
            didSet = volumeController.setVolume(volume, for: process.bundleID)
        case .webAppKeyboard:
            didSet = webAppVolumeController.setVolume(volume, for: process.volumeControlID)
        case .unavailable:
            didSet = false
        }

        guard didSet else {
            return
        }
        if let index = processes.firstIndex(where: { $0.id == process.id }) {
            processes[index].currentVolume = min(100, max(0, volume))
        }
    }

    func setEQGain(_ gain: Double, for frequencyHz: Int) {
        eqSettings.setGain(gain, for: frequencyHz)
        saveEQSettings()
        updateEQEngine()
    }

    func setEQPreamp(_ gain: Double) {
        eqSettings.preampDB = EQSettings.clamp(gain)
        saveEQSettings()
        updateEQEngine()
    }

    func setEQBypassed(_ isBypassed: Bool) {
        eqSettings.isBypassed = isBypassed
        saveEQSettings()
        updateEQEngine()
    }

    func applyEQPreset(_ preset: EQPreset) {
        eqSettings.apply(preset)
        saveEQSettings()
        updateEQEngine()
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

    private func updateEQEngine() {
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

    private static func loadEQSettings(from userDefaults: UserDefaults, key: String) -> EQSettings {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(EQSettings.self, from: data)
        else {
            return .flat
        }
        return settings
    }
}

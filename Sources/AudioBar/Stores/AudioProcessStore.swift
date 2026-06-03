import AudioBarCore
import Combine
import Foundation

@MainActor
final class AudioProcessStore: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var statusMessage = "Waiting for audio"

    private let provider: AudioProcessProviding
    private let volumeController: AppVolumeControlling
    private var timer: Timer?

    init(
        volumeController: AppVolumeControlling = ScriptedAppVolumeController(),
        provider: AudioProcessProviding? = nil
    ) {
        self.volumeController = volumeController
        self.provider = provider ?? CoreAudioProcessProvider(volumeController: volumeController)
    }

    func startAutoRefresh() {
        guard timer == nil else {
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
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
        guard volumeController.setVolume(volume, for: process.bundleID) else {
            return
        }
        if let index = processes.firstIndex(where: { $0.id == process.id }) {
            processes[index].currentVolume = min(100, max(0, volume))
        }
    }
}

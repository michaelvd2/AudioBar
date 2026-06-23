import Foundation

public struct AudioProcessListCache {
    private var knownProcesses: [String: AudioProcess] = [:]
    public private(set) var persistedVolumes: [String: Int]

    public init(persistedVolumes: [String: Int] = [:]) {
        self.persistedVolumes = persistedVolumes.mapValues { min(100, max(0, $0)) }
    }

    public mutating func merge(activeProcesses: [AudioProcess]) -> [AudioProcess] {
        let activeProcesses = activeProcesses.map { process in
            let activeProcess = process.markingActiveOutput(true)
            guard process.volumeCapability.isAdjustable else {
                return activeProcess
            }
            if let knownVolume = knownProcesses[process.stableSourceID]?.currentVolume {
                return activeProcess.withCurrentVolume(knownVolume)
            }
            if let persistedVolume = persistedVolumes[process.stableSourceID] {
                return activeProcess.withCurrentVolume(persistedVolume)
            }
            return activeProcess
        }
        let activeIDs = Set(activeProcesses.map(\.stableSourceID))

        for process in activeProcesses {
            knownProcesses[process.stableSourceID] = process
        }

        let pausedProcesses = knownProcesses.values
            .filter { !activeIDs.contains($0.stableSourceID) }
            .filter(\.shouldRemainVisibleWhenPaused)
            .map { $0.markingActiveOutput(false) }

        return AudioProcess.sortedForDisplay(activeProcesses + pausedProcesses)
    }

    /// Permanently forgets a source so it will not reappear as a paused row.
    /// Use for one-off / dev sources that won't come back (unlike hiding, which
    /// keeps the source on a restorable list). If the source is still actively
    /// producing audio it will be re-discovered on the next `merge`.
    public mutating func remove(stableSourceID: String) {
        knownProcesses.removeValue(forKey: stableSourceID)
        persistedVolumes.removeValue(forKey: stableSourceID)
    }

    public mutating func setCurrentVolume(_ volume: Int, forStableSourceID stableSourceID: String) {
        let volume = min(100, max(0, volume))
        persistedVolumes[stableSourceID] = volume
        guard let process = knownProcesses[stableSourceID] else {
            return
        }
        knownProcesses[stableSourceID] = process.withCurrentVolume(volume)
    }
}

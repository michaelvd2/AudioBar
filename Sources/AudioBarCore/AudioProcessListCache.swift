import Foundation

public struct AudioProcessListCache {
    private var knownProcesses: [String: AudioProcess] = [:]

    public init() {}

    public mutating func merge(activeProcesses: [AudioProcess]) -> [AudioProcess] {
        let activeProcesses = activeProcesses.map { process in
            let activeProcess = process.markingActiveOutput(true)
            guard case .webAppKeyboard = process.volumeCapability,
                  let knownVolume = knownProcesses[process.stableSourceID]?.currentVolume
            else {
                return activeProcess
            }
            return activeProcess.withCurrentVolume(knownVolume)
        }
        let activeIDs = Set(activeProcesses.map(\.stableSourceID))

        for process in activeProcesses {
            knownProcesses[process.stableSourceID] = process
        }

        let pausedProcesses = knownProcesses.values
            .filter { !activeIDs.contains($0.stableSourceID) }
            .map { $0.markingActiveOutput(false) }

        return AudioProcess.sortedForDisplay(activeProcesses + pausedProcesses)
    }

    public mutating func setCurrentVolume(_ volume: Int, forStableSourceID stableSourceID: String) {
        guard let process = knownProcesses[stableSourceID] else {
            return
        }
        knownProcesses[stableSourceID] = process.withCurrentVolume(min(100, max(0, volume)))
    }
}

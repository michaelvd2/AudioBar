import Foundation

public struct AudioProcessListCache {
    private var knownProcesses: [String: AudioProcess] = [:]

    public init() {}

    public mutating func merge(activeProcesses: [AudioProcess]) -> [AudioProcess] {
        let activeProcesses = activeProcesses.map { $0.markingActiveOutput(true) }
        let activeIDs = Set(activeProcesses.map(\.stableSourceID))

        for process in activeProcesses {
            knownProcesses[process.stableSourceID] = process
        }

        let pausedProcesses = knownProcesses.values
            .filter { !activeIDs.contains($0.stableSourceID) }
            .map { $0.markingActiveOutput(false) }

        return AudioProcess.sortedForDisplay(activeProcesses + pausedProcesses)
    }
}

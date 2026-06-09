import CoreAudio
import Foundation

public enum AudioProcessResolver {
    public static func resolve(
        audioObjectID: AudioObjectID,
        pid: pid_t,
        bundleID: String?,
        localizedAppName: String?,
        trackTitle: String?,
        currentVolume: Int?
    ) -> AudioProcess {
        let appName = localizedAppName?.nilIfBlank
            ?? bundleID?.nilIfBlank
            ?? "PID \(pid)"

        let scriptedCapability = ScriptedAppVolumeSupport.capability(for: bundleID)
        let volumeCapability: VolumeCapability = scriptedCapability.isAdjustable ? scriptedCapability : .systemRoute
        let resolvedCurrentVolume = currentVolume ?? (volumeCapability.isAdjustable ? 100 : nil)

        return AudioProcess(
            audioObjectID: audioObjectID,
            pid: pid,
            bundleID: bundleID?.nilIfBlank,
            appName: appName,
            trackTitle: trackTitle?.nilIfBlank,
            currentVolume: resolvedCurrentVolume,
            volumeCapability: volumeCapability,
            volumeControlID: volumeCapability.isAdjustable ? bundleID?.nilIfBlank : nil
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

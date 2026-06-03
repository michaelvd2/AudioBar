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

        return AudioProcess(
            audioObjectID: audioObjectID,
            pid: pid,
            bundleID: bundleID?.nilIfBlank,
            appName: appName,
            trackTitle: trackTitle?.nilIfBlank,
            currentVolume: currentVolume,
            volumeCapability: ScriptedAppVolumeSupport.capability(for: bundleID)
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

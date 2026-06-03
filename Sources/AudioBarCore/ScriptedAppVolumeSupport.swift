import Foundation

public enum ScriptedAppVolumeSupport {
    public static let unsupportedReason = "No public per-app volume control"

    public static func capability(for bundleID: String?) -> VolumeCapability {
        guard let bundleID, supportedBundleIDs.contains(bundleID) else {
            return .unavailable(reason: unsupportedReason)
        }
        return .scripted
    }

    public static func supports(_ bundleID: String?) -> Bool {
        capability(for: bundleID).isAdjustable
    }

    private static let supportedBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.spotify.client"
    ]
}

public enum ScriptVolumeCommandBuilder {
    public static func setVolumeScript(bundleID: String, volume: Int) -> String {
        let clamped = min(100, max(0, volume))
        return """
        tell application id "\(bundleID)"
            set sound volume to \(clamped)
        end tell
        """
    }

    public static func getVolumeScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            sound volume
        end tell
        """
    }

    public static func currentTrackScript(bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Music":
            return """
            tell application id "com.apple.Music"
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    if artistName is "" then
                        return trackName
                    else
                        return trackName & " - " & artistName
                    end if
                end if
                return ""
            end tell
            """
        case "com.spotify.client":
            return """
            tell application id "com.spotify.client"
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    if artistName is "" then
                        return trackName
                    else
                        return trackName & " - " & artistName
                    end if
                end if
                return ""
            end tell
            """
        default:
            return nil
        }
    }
}

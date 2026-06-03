import Foundation

public enum WebAppKeyboardVolumeCommandBuilder {
    public static func setYouTubeVolumeScript(bundleID: String, volume: Int) -> String {
        let clamped = min(100, max(0, volume))
        let steps = clamped / 5

        return """
        tell application id "\(bundleID)" to activate
        delay 0.08
        tell application "System Events"
            tell (first process whose bundle identifier is "\(bundleID)")
                repeat 20 times
                    key code 125
                    delay 0.005
                end repeat
                repeat \(steps) times
                    key code 126
                    delay 0.005
                end repeat
            end tell
        end tell
        """
    }
}

public final class WebAppKeyboardVolumeController {
    public init() {}

    public func setVolume(_ volume: Int, for bundleID: String?) -> Bool {
        guard let bundleID, bundleID.hasPrefix("com.apple.Safari.WebApp.") else {
            return false
        }

        let script = WebAppKeyboardVolumeCommandBuilder.setYouTubeVolumeScript(
            bundleID: bundleID,
            volume: volume
        )
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }

        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        return error == nil
    }
}

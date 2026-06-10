import Foundation

public enum ScriptedAppPlaybackSupport {
    public static let unsupportedReason = "No public per-source playback control"

    public static func supports(_ bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }
        return supportedBundleIDs.contains(bundleID)
    }

    private static let supportedBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.spotify.client"
    ]
}

public enum ScriptPlaybackCommandBuilder {
    public static func togglePlaybackScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            playpause
        end tell
        """
    }
}

public enum SafariMediaPlaybackCommandBuilder {
    public static func togglePlaybackScript() -> String {
        let javascript = """
        (function() {
            const media = Array.from(document.querySelectorAll('audio,video'));
            const target = media.find(function(item) { return !item.paused; }) || media[0];
            if (!target) { return false; }
            if (target.paused) { target.play(); } else { target.pause(); }
            return true;
        })();
        """

        return """
        tell application id "com.apple.Safari"
            if (count of windows) is 0 then return false
            do JavaScript "\(javascript.escapedForAppleScript)" in current tab of front window
            return true
        end tell
        """
    }
}

public enum WebAppKeyboardPlaybackCommandBuilder {
    public static func togglePlaybackScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)" to activate
        delay 0.08
        tell application "System Events"
            tell (first process whose bundle identifier is "\(bundleID)")
                key code 49
            end tell
        end tell
        """
    }
}

public final class SourcePlaybackController {
    public init() {}

    public func togglePlayback(for process: AudioProcess) -> Bool {
        let source: String?
        switch process.playbackCapability {
        case .scripted:
            guard let bundleID = process.bundleID else {
                return false
            }
            source = ScriptPlaybackCommandBuilder.togglePlaybackScript(bundleID: bundleID)
        case .webAppKeyboard:
            guard let bundleID = process.volumeControlID else {
                return false
            }
            source = WebAppKeyboardPlaybackCommandBuilder.togglePlaybackScript(bundleID: bundleID)
        case .safariMedia:
            source = SafariMediaPlaybackCommandBuilder.togglePlaybackScript()
        case .unavailable:
            source = nil
        }

        guard let source, let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

private extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

import AppKit
import CoreGraphics
import Foundation
import OSLog

private let playbackLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.michaelvandijk.AudioBar",
    category: "Playback"
)

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

public final class SystemMediaKeyPlaybackController {
    public init() {}

    public func togglePlayPause() -> Bool {
        guard hasInputMonitoringAccess() else {
            playbackLogger.info("Requesting Input Monitoring access for system play/pause media key")
            return CGRequestListenEventAccess()
        }

        playbackLogger.info("Posting system play/pause media key; inputMonitoringTrusted=true")
        postMediaKey(NX_KEYTYPE_PLAY, state: NX_KEYDOWN)
        postMediaKey(NX_KEYTYPE_PLAY, state: NX_KEYUP)
        return true
    }

    private func hasInputMonitoringAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    private func postMediaKey(_ key: Int32, state: Int32) {
        let data1 = (Int(key) << 16) | (Int(state) << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return
        }

        event.post(tap: .cghidEventTap)
    }
}

public final class SourcePlaybackController {
    private let mediaKeyController: SystemMediaKeyPlaybackController

    public init(mediaKeyController: SystemMediaKeyPlaybackController = SystemMediaKeyPlaybackController()) {
        self.mediaKeyController = mediaKeyController
    }

    public func togglePlayback(for process: AudioProcess) -> Bool {
        let source: String?
        switch process.playbackCapability {
        case .scripted:
            guard let bundleID = process.bundleID else {
                return false
            }
            source = ScriptPlaybackCommandBuilder.togglePlaybackScript(bundleID: bundleID)
        case .webAppKeyboard:
            return mediaKeyController.togglePlayPause()
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

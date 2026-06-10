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

    public static func rewind15SecondsScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            try
                set player position to ((player position) - 15)
                return true
            on error
                return false
            end try
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

    public static func rewind15SecondsScript() -> String {
        let javascript = """
        (function() {
            const media = Array.from(document.querySelectorAll('audio,video'));
            const target = media.find(function(item) { return !item.paused; }) || media[0];
            if (!target) { return false; }
            target.currentTime = Math.max(0, target.currentTime - 15);
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

#if APP_STORE
public final class SystemMediaKeyPlaybackController {
    public init() {}

    public func togglePlayPause() -> Bool {
        false
    }
}

public final class NowPlayingPlaybackController {
    public init() {}

    public func togglePlayPause() -> Bool {
        false
    }

    public func rewind15Seconds() -> Bool {
        false
    }
}
#else
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

public final class NowPlayingPlaybackController {
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Void

    private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private let togglePlayPauseCommand: Int32 = 2
    private let goBackFifteenSecondsCommand: Int32 = 12

    public init() {}

    public func togglePlayPause() -> Bool {
        sendCommand(togglePlayPauseCommand, logMessage: "Sent Now Playing toggle through MediaRemote")
    }

    public func rewind15Seconds() -> Bool {
        sendCommand(goBackFifteenSecondsCommand, logMessage: "Sent Now Playing 15-second rewind through MediaRemote")
    }

    private func sendCommand(_ command: Int32, logMessage: StaticString) -> Bool {
        guard
            let handle = dlopen(frameworkPath, RTLD_NOW),
            let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else {
            playbackLogger.info("MediaRemote unavailable for Now Playing command")
            return false
        }
        defer { dlclose(handle) }

        let sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
        sendCommand(command, nil)
        playbackLogger.info("\(logMessage)")
        return true
    }
}
#endif

public final class SourcePlaybackController {
    private let mediaKeyController: SystemMediaKeyPlaybackController
    private let nowPlayingController: NowPlayingPlaybackController

    public init(
        mediaKeyController: SystemMediaKeyPlaybackController = SystemMediaKeyPlaybackController(),
        nowPlayingController: NowPlayingPlaybackController = NowPlayingPlaybackController()
    ) {
        self.mediaKeyController = mediaKeyController
        self.nowPlayingController = nowPlayingController
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
            #if APP_STORE
            return false
            #else
            if nowPlayingController.togglePlayPause() {
                return true
            }
            return mediaKeyController.togglePlayPause()
            #endif
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

    public func rewind15Seconds(for process: AudioProcess) -> Bool {
        let source: String?
        switch process.playbackCapability {
        case .scripted:
            guard let bundleID = process.bundleID else {
                return false
            }
            source = ScriptPlaybackCommandBuilder.rewind15SecondsScript(bundleID: bundleID)
        case .webAppKeyboard:
            #if APP_STORE
            return false
            #else
            return nowPlayingController.rewind15Seconds()
            #endif
        case .safariMedia:
            source = SafariMediaPlaybackCommandBuilder.rewind15SecondsScript()
        case .unavailable:
            source = nil
        }

        guard let source, let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }
}

private extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

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

    public static func previousTrackScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            previous track
        end tell
        """
    }

    public static func nextTrackScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            next track
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
        let pauseJS = """
        (function() {
            const m = Array.from(document.querySelectorAll('audio,video')).find(function(x){ return !x.paused && !x.ended; });
            if (m) { m.pause(); return true; }
            return false;
        })();
        """
        let playJS = """
        (function() {
            const m = document.querySelector('audio,video');
            if (m) { m.play(); return true; }
            return false;
        })();
        """

        return """
        tell application id "com.apple.Safari"
            if (count of windows) is 0 then return false
            repeat with safariWindow in windows
                repeat with safariTab in tabs of safariWindow
                    try
                        set didPause to do JavaScript "\(pauseJS.escapedForAppleScript)" in safariTab
                        if didPause is true or didPause is "true" then return true
                    end try
                end repeat
            end repeat
            repeat with safariWindow in windows
                repeat with safariTab in tabs of safariWindow
                    try
                        set didPlay to do JavaScript "\(playJS.escapedForAppleScript)" in safariTab
                        if didPlay is true or didPlay is "true" then return true
                    end try
                end repeat
            end repeat
            return false
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
            repeat with safariWindow in windows
                repeat with safariTab in tabs of safariWindow
                    try
                        set didRewind to do JavaScript "\(javascript.escapedForAppleScript)" in safariTab
                        if didRewind is true or didRewind is "true" then return true
                    end try
                end repeat
            end repeat
            return false
        end tell
        """
    }
}

public enum WebAppKeyboardPlaybackCommandBuilder {
    #if !APP_STORE
    public static func previousTrackScript(bundleID: String) -> String {
        trackShortcutScript(bundleID: bundleID, key: "p")
    }

    public static func nextTrackScript(bundleID: String) -> String {
        trackShortcutScript(bundleID: bundleID, key: "n")
    }

    private static func trackShortcutScript(bundleID: String, key: String) -> String {
        """
        tell application id "\(bundleID)" to activate
        delay 0.08
        tell application "System Events"
            tell (first process whose bundle identifier is "\(bundleID)")
                keystroke "\(key)" using {shift down}
                return true
            end tell
        end tell
        """
    }
    #endif
}

#if APP_STORE
public final class SystemMediaKeyPlaybackController {
    public init() {}

    public func togglePlayPause() -> Bool {
        false
    }

    public func previousTrack() -> Bool {
        false
    }

    public func nextTrack() -> Bool {
        false
    }
}

public final class NowPlayingPlaybackController {
    public init() {}

    public func togglePlayPause() -> Bool {
        false
    }

    public func previousTrack() -> Bool {
        false
    }

    public func nextTrack() -> Bool {
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
        postMediaCommand(NX_KEYTYPE_PLAY, label: "play/pause")
    }

    public func previousTrack() -> Bool {
        postMediaCommand(NX_KEYTYPE_PREVIOUS, label: "previous track")
    }

    public func nextTrack() -> Bool {
        postMediaCommand(NX_KEYTYPE_NEXT, label: "next track")
    }

    private func postMediaCommand(_ key: Int32, label: StaticString) -> Bool {
        guard hasInputMonitoringAccess() else {
            playbackLogger.info("Requesting Input Monitoring access for system media key")
            return CGRequestListenEventAccess()
        }

        playbackLogger.info("Posting system \(label) media key; inputMonitoringTrusted=true")
        postMediaKey(key, state: NX_KEYDOWN)
        postMediaKey(key, state: NX_KEYUP)
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
    private let nextTrackCommand: Int32 = 4
    private let previousTrackCommand: Int32 = 5
    private let goBackFifteenSecondsCommand: Int32 = 12

    public init() {}

    public func togglePlayPause() -> Bool {
        sendCommand(togglePlayPauseCommand, logMessage: "Sent Now Playing toggle through MediaRemote")
    }

    public func previousTrack() -> Bool {
        sendCommand(previousTrackCommand, logMessage: "Sent Now Playing previous track through MediaRemote")
    }

    public func nextTrack() -> Bool {
        sendCommand(nextTrackCommand, logMessage: "Sent Now Playing next track through MediaRemote")
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

    public func previousTrack(for process: AudioProcess) -> Bool {
        let source: String?
        switch process.playbackCapability {
        case .scripted:
            guard let bundleID = process.bundleID else {
                return false
            }
            source = ScriptPlaybackCommandBuilder.previousTrackScript(bundleID: bundleID)
        case .webAppKeyboard:
            #if APP_STORE
            return false
            #else
            guard let bundleID = process.volumeControlID ?? process.bundleID else {
                return false
            }
            source = WebAppKeyboardPlaybackCommandBuilder.previousTrackScript(bundleID: bundleID)
            #endif
        case .safariMedia:
            #if APP_STORE
            return false
            #else
            if nowPlayingController.previousTrack() {
                return true
            }
            return mediaKeyController.previousTrack()
            #endif
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

    public func nextTrack(for process: AudioProcess) -> Bool {
        let source: String?
        switch process.playbackCapability {
        case .scripted:
            guard let bundleID = process.bundleID else {
                return false
            }
            source = ScriptPlaybackCommandBuilder.nextTrackScript(bundleID: bundleID)
        case .webAppKeyboard:
            #if APP_STORE
            return false
            #else
            guard let bundleID = process.volumeControlID ?? process.bundleID else {
                return false
            }
            source = WebAppKeyboardPlaybackCommandBuilder.nextTrackScript(bundleID: bundleID)
            #endif
        case .safariMedia:
            #if APP_STORE
            return false
            #else
            if nowPlayingController.nextTrack() {
                return true
            }
            return mediaKeyController.nextTrack()
            #endif
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

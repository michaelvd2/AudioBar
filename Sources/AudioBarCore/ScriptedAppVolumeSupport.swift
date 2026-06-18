import Foundation

public enum ScriptedAppVolumeSupport {
    public static let unsupportedReason = "No public per-app volume control"

    public static func capability(for bundleID: String?) -> VolumeCapability {
        if bundleID == "com.apple.Safari" {
            return .safariMedia
        }
        guard let bundleID, supportedBundleIDs.contains(bundleID) else {
            return .unavailable(reason: unsupportedReason)
        }
        return .scripted
    }

    public static func supports(_ bundleID: String?) -> Bool {
        capability(for: bundleID) == .scripted
    }

    private static let supportedBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.spotify.client"
    ]
}

public enum SafariMediaVolumeCommandBuilder {
    public static func setVolumeScript(volume: Int) -> String {
        let clamped = min(100, max(0, volume))
        let mediaVolume = String(format: "%.2f", Double(clamped) / 100)
        let javascript = """
        (function() {
            const mediaItems = Array.from(document.querySelectorAll('audio,video'));
            if (mediaItems.length === 0) { return false; }
            mediaItems.forEach(function(media) { media.volume = \(mediaVolume); });
            return true;
        })();
        """

        return safariAllTabsScript(javascript: javascript)
    }
}

public enum SafariMediaEQCommandBuilder {
    public static func applyEQScript(settings: EQSettings) -> String {
        let bands = EQBand.classic.map { band in
            "{ frequency: \(band.frequencyHz), gain: \(String(format: "%.2f", settings.gain(for: band.frequencyHz))) }"
        }.joined(separator: ", ")
        let preampDB = String(format: "%.2f", EQSettings.clamp(settings.preampDB))
        let isBypassed = settings.isBypassed ? "true" : "false"
        let javascript = """
        (function() {
            const settings = { isBypassed: \(isBypassed), preampDB: \(preampDB), bands: [\(bands)] };
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;
            if (!AudioContextClass) { return false; }
            const mediaItems = Array.from(document.querySelectorAll('audio,video'));
            if (mediaItems.length === 0) { return false; }
            mediaItems.forEach(function(media) {
                const state = media.__audioBarEQ || {};
                state.context = state.context || new AudioContextClass();
                if (!state.source) {
                    state.source = state.context.createMediaElementSource(media);
                }
                try { state.source.disconnect(); } catch (_) {}
                if (state.preamp) { try { state.preamp.disconnect(); } catch (_) {} }
                if (state.filters) {
                    state.filters.forEach(function(filter) {
                        try { filter.disconnect(); } catch (_) {}
                    });
                }
                if (settings.isBypassed) {
                    state.source.connect(state.context.destination);
                    state.filters = [];
                    state.preamp = null;
                    media.__audioBarEQ = state;
                    if (state.context.state === 'suspended') { state.context.resume(); }
                    return;
                }
                state.filters = settings.bands.map(function(band) {
                    const filter = state.context.createBiquadFilter();
                    filter.type = 'peaking';
                    filter.frequency.value = band.frequency;
                    filter.Q.value = 1.414;
                    filter.gain.value = band.gain;
                    return filter;
                });
                const preamp = state.context.createGain();
                preamp.gain.value = Math.pow(10, settings.preampDB / 20);
                state.preamp = preamp;
                state.source.connect(state.filters[0]);
                for (let index = 0; index < state.filters.length - 1; index += 1) {
                    state.filters[index].connect(state.filters[index + 1]);
                }
                state.filters[state.filters.length - 1].connect(preamp);
                preamp.connect(state.context.destination);
                media.__audioBarEQ = state;
                if (state.context.state === 'suspended') { state.context.resume(); }
            });
            return true;
        })();
        """

        return safariAllTabsScript(javascript: javascript)
    }
}

private func safariAllTabsScript(javascript: String) -> String {
    """
    tell application id "com.apple.Safari"
        if (count of windows) is 0 then return false
        set didApply to false
        repeat with safariWindow in windows
            repeat with safariTab in tabs of safariWindow
                try
                    set tabResult to do JavaScript "\(javascript.escapedForAppleScript)" in safariTab
                    if tabResult is true or tabResult is "true" then set didApply to true
                end try
            end repeat
        end repeat
        return didApply
    end tell
    """
}

private extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
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
        case "com.apple.Safari":
            return """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return ""
                repeat with safariWindow in windows
                    repeat with safariTab in tabs of safariWindow
                        try
                            set mediaPlaying to do JavaScript "Array.from(document.querySelectorAll('audio,video')).some(function(m){return !m.paused && !m.ended && m.currentTime > 0;})" in safariTab
                            if mediaPlaying is true or mediaPlaying is "true" then return (name of safariTab)
                        end try
                    end repeat
                end repeat
                try
                    return (name of current tab of front window)
                end try
                return ""
            end tell
            """
        default:
            return nil
        }
    }
}

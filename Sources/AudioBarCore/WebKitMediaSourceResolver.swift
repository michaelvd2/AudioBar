import Foundation

public struct WebAppDescriptor: Equatable, Sendable {
    public let bundleID: String
    public let displayName: String
    public let windowTitle: String?

    public init(bundleID: String, displayName: String, windowTitle: String?) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.windowTitle = windowTitle
    }
}

public enum WebKitMediaSourceResolver {
    public static func resolve(
        helperAudioObjectID: UInt32,
        helperPID: Int32,
        helperBundleID: String?,
        helperName: String?,
        webApps: [WebAppDescriptor],
        nowPlayingMetadata: NowPlayingMetadata? = nil
    ) -> AudioProcess? {
        guard helperBundleID == "com.apple.WebKit.GPU" else {
            return nil
        }
        guard let helperName, helperName.hasSuffix(" Graphics and Media") else {
            return nil
        }

        let helperDisplayName = String(helperName.dropLast(" Graphics and Media".count))
        guard let webApp = webApps.first(where: { app in
            app.displayName.localizedCaseInsensitiveCompare(helperDisplayName) == .orderedSame
        }) else {
            return fallbackBrowserSource(
                helperAudioObjectID: helperAudioObjectID,
                helperPID: helperPID,
                displayName: helperDisplayName
            )
        }

        return AudioProcess(
            audioObjectID: helperAudioObjectID,
            pid: helperPID,
            bundleID: webApp.bundleID,
            appName: webApp.displayName,
            trackTitle: normalizedTrackTitle(webApp.windowTitle, appName: webApp.displayName)
                ?? nowPlayingTrackTitle(nowPlayingMetadata, webApp: webApp),
            currentVolume: 100,
            volumeCapability: .webAppKeyboard,
            volumeControlID: webApp.bundleID
        )
    }

    private static func fallbackBrowserSource(
        helperAudioObjectID: UInt32,
        helperPID: Int32,
        displayName: String
    ) -> AudioProcess {
        let bundleID = browserBundleID(for: displayName)
        let volumeCapability = ScriptedAppVolumeSupport.capability(for: bundleID)
        let isAdjustable = volumeCapability.isAdjustable
        return AudioProcess(
            audioObjectID: helperAudioObjectID,
            pid: helperPID,
            bundleID: bundleID,
            appName: displayName,
            trackTitle: nil,
            currentVolume: isAdjustable ? 100 : nil,
            volumeCapability: volumeCapability,
            volumeControlID: isAdjustable ? bundleID : nil
        )
    }

    private static func browserBundleID(for displayName: String) -> String? {
        switch displayName.lowercased() {
        case "safari":
            return "com.apple.Safari"
        default:
            return nil
        }
    }

    private static func normalizedTrackTitle(_ windowTitle: String?, appName: String) -> String? {
        guard let windowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !windowTitle.isEmpty
        else {
            return nil
        }

        let suffix = " - \(appName)"
        if windowTitle.hasSuffix(suffix) {
            let title = String(windowTitle.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return windowTitle
    }

    private static func nowPlayingTrackTitle(_ metadata: NowPlayingMetadata?, webApp: WebAppDescriptor) -> String? {
        guard webApp.displayName.localizedCaseInsensitiveCompare("YouTube") == .orderedSame else {
            return nil
        }
        if let sourceBundleID = metadata?.sourceBundleID,
           sourceBundleID != webApp.bundleID,
           !sourceBundleID.hasPrefix("com.apple.Safari") {
            return nil
        }
        return metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

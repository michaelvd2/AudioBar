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
        webApps: [WebAppDescriptor]
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
            return nil
        }

        return AudioProcess(
            audioObjectID: helperAudioObjectID,
            pid: helperPID,
            bundleID: webApp.bundleID,
            appName: webApp.displayName,
            trackTitle: normalizedTrackTitle(webApp.windowTitle, appName: webApp.displayName),
            currentVolume: 50,
            volumeCapability: .webAppKeyboard,
            volumeControlID: webApp.bundleID
        )
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
}

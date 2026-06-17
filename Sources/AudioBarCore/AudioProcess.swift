import Foundation

public enum VolumeCapability: Equatable, Sendable {
    case systemRoute
    case scripted
    case webAppKeyboard
    case safariMedia
    case unavailable(reason: String)

    public var isAdjustable: Bool {
        switch self {
        case .systemRoute, .scripted, .webAppKeyboard, .safariMedia:
            return true
        case .unavailable:
            return false
        }
    }
}

public enum PlaybackCapability: Equatable, Sendable {
    case scripted
    case webAppKeyboard
    case safariMedia
    case unavailable(reason: String)

    public var isControllable: Bool {
        switch self {
        case .scripted, .webAppKeyboard, .safariMedia:
            return true
        case .unavailable:
            return false
        }
    }
}

public struct AudioProcess: Equatable, Identifiable, Sendable {
    public let audioObjectID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let appName: String
    public var trackTitle: String?
    public var currentVolume: Int?
    public let volumeCapability: VolumeCapability
    public let volumeControlID: String?
    public let isActiveOutput: Bool

    public var id: String {
        "\(pid)-\(audioObjectID)"
    }

    public var stableSourceID: String {
        volumeControlID
            ?? bundleID
            ?? "\(pid)-\(appName)"
    }

    public var shouldRemainVisibleWhenPaused: Bool {
        switch volumeCapability {
        case .scripted, .webAppKeyboard, .safariMedia:
            return true
        case .systemRoute, .unavailable:
            break
        }

        if isSystemSoundsSource {
            return true
        }

        guard let bundleID else {
            return false
        }
        return bundleID == "com.apple.Safari"
            || bundleID.hasPrefix("com.apple.Safari.WebApp.")
    }

    public var playbackCapability: PlaybackCapability {
        switch volumeCapability {
        case .scripted:
            guard ScriptedAppPlaybackSupport.supports(bundleID) else {
                return .unavailable(reason: ScriptedAppPlaybackSupport.unsupportedReason)
            }
            return .scripted
        case .webAppKeyboard:
            return .webAppKeyboard
        case .safariMedia:
            return .safariMedia
        case .systemRoute, .unavailable:
            return .unavailable(reason: ScriptedAppPlaybackSupport.unsupportedReason)
        }
    }

    public init(
        audioObjectID: UInt32,
        pid: Int32,
        bundleID: String?,
        appName: String,
        trackTitle: String?,
        currentVolume: Int?,
        volumeCapability: VolumeCapability,
        volumeControlID: String? = nil,
        isActiveOutput: Bool = true
    ) {
        self.audioObjectID = audioObjectID
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.trackTitle = trackTitle
        self.currentVolume = currentVolume
        self.volumeCapability = volumeCapability
        self.volumeControlID = volumeControlID
        self.isActiveOutput = isActiveOutput
    }

    public var displayTitle: String {
        if isSafariWebAppSource {
            return displayAppName
        }
        guard !normalizedTrackTitle.isEmpty else {
            return displayAppName
        }
        return normalizedTrackTitle
    }

    public var displaySubtitle: String {
        guard isActiveOutput else {
            return "Paused"
        }
        if isSafariWebAppSource, !normalizedTrackTitle.isEmpty {
            return normalizedTrackTitle
        }
        if !normalizedTrackTitle.isEmpty {
            return displayAppName
        }
        if let sourceKind = humanReadableSourceKind {
            return sourceKind
        }
        return "PID \(pid)"
    }

    private var normalizedTrackTitle: String {
        trackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var displayAppName: String {
        if isSystemSoundsSource {
            return "System Sounds"
        }
        guard appName == bundleID else {
            return appName
        }
        return humanReadableName(fromBundleID: appName) ?? appName
    }

    private var humanReadableSourceKind: String? {
        guard let bundleID, !bundleID.isEmpty else {
            return nil
        }
        if isSafariWebAppSource {
            return "Safari web app"
        }
        if isSystemSoundsSource {
            return "System audio"
        }
        return "App audio"
    }

    private var isSafariWebAppSource: Bool {
        bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true
    }

    private var isSystemSoundsSource: Bool {
        bundleID == "systemsoundserverd" || appName == "systemsoundserverd"
    }

    private func humanReadableName(fromBundleID bundleID: String) -> String? {
        bundleID
            .split(separator: ".")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    public func markingActiveOutput(_ isActiveOutput: Bool) -> AudioProcess {
        AudioProcess(
            audioObjectID: audioObjectID,
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            trackTitle: trackTitle,
            currentVolume: currentVolume,
            volumeCapability: volumeCapability,
            volumeControlID: volumeControlID,
            isActiveOutput: isActiveOutput
        )
    }

    public func withCurrentVolume(_ currentVolume: Int?) -> AudioProcess {
        AudioProcess(
            audioObjectID: audioObjectID,
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            trackTitle: trackTitle,
            currentVolume: currentVolume,
            volumeCapability: volumeCapability,
            volumeControlID: volumeControlID,
            isActiveOutput: isActiveOutput
        )
    }

    public static func sortedForDisplay(_ processes: [AudioProcess]) -> [AudioProcess] {
        processes.sorted { left, right in
            if left.isActiveOutput != right.isActiveOutput {
                return left.isActiveOutput
            }
            if left.volumeCapability.isAdjustable != right.volumeCapability.isAdjustable {
                return left.volumeCapability.isAdjustable
            }
            return left.appName.localizedCaseInsensitiveCompare(right.appName) == .orderedAscending
        }
    }

    public static func visibleUserSources(_ processes: [AudioProcess], currentPID: pid_t) -> [AudioProcess] {
        sortedForDisplay(processes.filter { $0.pid != currentPID })
    }
}

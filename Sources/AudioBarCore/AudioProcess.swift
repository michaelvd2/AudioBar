import Foundation

public enum VolumeCapability: Equatable, Sendable {
    case scripted
    case webAppKeyboard
    case unavailable(reason: String)

    public var isAdjustable: Bool {
        switch self {
        case .scripted, .webAppKeyboard:
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

    public var id: String {
        "\(pid)-\(audioObjectID)"
    }

    public init(
        audioObjectID: UInt32,
        pid: Int32,
        bundleID: String?,
        appName: String,
        trackTitle: String?,
        currentVolume: Int?,
        volumeCapability: VolumeCapability,
        volumeControlID: String? = nil
    ) {
        self.audioObjectID = audioObjectID
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.trackTitle = trackTitle
        self.currentVolume = currentVolume
        self.volumeCapability = volumeCapability
        self.volumeControlID = volumeControlID
    }

    public var displayTitle: String {
        guard !normalizedTrackTitle.isEmpty else {
            return displayAppName
        }
        return normalizedTrackTitle
    }

    public var displaySubtitle: String {
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
        guard appName == bundleID else {
            return appName
        }
        return humanReadableName(fromBundleID: appName) ?? appName
    }

    private var humanReadableSourceKind: String? {
        guard let bundleID, !bundleID.isEmpty else {
            return nil
        }
        if bundleID.hasPrefix("com.apple.Safari.WebApp.") {
            return "Safari web app"
        }
        return "App audio"
    }

    private func humanReadableName(fromBundleID bundleID: String) -> String? {
        bundleID
            .split(separator: ".")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    public static func sortedForDisplay(_ processes: [AudioProcess]) -> [AudioProcess] {
        processes.sorted { left, right in
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

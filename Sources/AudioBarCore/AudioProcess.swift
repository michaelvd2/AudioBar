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
        guard let trackTitle, !trackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return appName
        }
        return trackTitle
    }

    public var displaySubtitle: String {
        if displayTitle != appName {
            return appName
        }
        if let bundleID, !bundleID.isEmpty {
            return bundleID
        }
        return "PID \(pid)"
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

import CoreAudio
import Foundation

public struct BPMSourceSetGate: Sendable {
    public let settleInterval: TimeInterval

    private var appliedSources: [AudioObjectID] = []
    private var pendingSources: [AudioObjectID]?
    private var pendingSince: Date?

    public init(settleInterval: TimeInterval) {
        self.settleInterval = max(0, settleInterval)
    }

    @discardableResult
    public mutating func reset(appliedSources sources: [AudioObjectID] = []) -> [AudioObjectID] {
        let sources = Self.normalized(sources)
        appliedSources = sources
        pendingSources = nil
        pendingSince = nil
        return sources
    }

    public mutating func nextAppliedSources(
        observed sources: [AudioObjectID],
        now: Date = Date()
    ) -> [AudioObjectID]? {
        let sources = Self.normalized(sources)
        guard sources != appliedSources else {
            pendingSources = nil
            pendingSince = nil
            return nil
        }

        guard pendingSources == sources, let pendingSince else {
            pendingSources = sources
            pendingSince = now
            return settleInterval == 0 ? applyPendingSources(sources) : nil
        }

        guard now.timeIntervalSince(pendingSince) >= settleInterval else {
            return nil
        }
        return applyPendingSources(sources)
    }

    public static func normalized(_ sources: [AudioObjectID]) -> [AudioObjectID] {
        Array(Set(sources.filter { $0 != kAudioObjectUnknown })).sorted()
    }

    private mutating func applyPendingSources(_ sources: [AudioObjectID]) -> [AudioObjectID] {
        appliedSources = sources
        pendingSources = nil
        pendingSince = nil
        return sources
    }
}

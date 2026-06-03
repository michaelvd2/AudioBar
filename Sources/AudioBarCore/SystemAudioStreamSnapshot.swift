import Foundation

public struct SystemAudioStreamSnapshot: Equatable, Sendable {
    public let isActive: Bool
    public let sampleRate: Double
    public let channelCount: Int
    public let inputLevelDB: Double
    public let outputLevelDB: Double

    public static let inactive = SystemAudioStreamSnapshot(
        isActive: false,
        sampleRate: 0,
        channelCount: 0,
        inputLevelDB: -120,
        outputLevelDB: -120
    )

    public static func active(
        sampleRate: Double,
        channelCount: Int,
        inputLevelDB: Double = -120,
        outputLevelDB: Double = -120
    ) -> SystemAudioStreamSnapshot {
        SystemAudioStreamSnapshot(
            isActive: true,
            sampleRate: sampleRate,
            channelCount: max(1, channelCount),
            inputLevelDB: inputLevelDB,
            outputLevelDB: outputLevelDB
        )
    }

    public var title: String {
        "System Stream"
    }

    public var subtitle: String {
        guard isActive else {
            return "No stream"
        }

        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return "\(channelCount)ch \(Int(kilohertz)) kHz"
        }
        return "\(channelCount)ch \(String(format: "%.1f", kilohertz)) kHz"
    }

    public var levelFraction: Double {
        guard isActive else {
            return 0
        }
        return min(1, max(0, (outputLevelDB + 60) / 60))
    }
}

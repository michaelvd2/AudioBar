import Foundation

public struct EQBand: Equatable, Identifiable, Codable, Sendable {
    public let frequencyHz: Int
    public let label: String

    public var id: Int {
        frequencyHz
    }

    public static let classic: [EQBand] = [
        EQBand(frequencyHz: 31, label: "31"),
        EQBand(frequencyHz: 62, label: "62"),
        EQBand(frequencyHz: 125, label: "125"),
        EQBand(frequencyHz: 250, label: "250"),
        EQBand(frequencyHz: 500, label: "500"),
        EQBand(frequencyHz: 1_000, label: "1k"),
        EQBand(frequencyHz: 2_000, label: "2k"),
        EQBand(frequencyHz: 4_000, label: "4k"),
        EQBand(frequencyHz: 8_000, label: "8k"),
        EQBand(frequencyHz: 16_000, label: "16k")
    ]
}

public enum EQPreset: String, CaseIterable, Codable, Sendable {
    case flat = "Flat"
    case bassBoost = "Bass"
    case vocalLift = "Vocal"
    case bright = "Bright"

    public var gains: [Int: Double] {
        switch self {
        case .flat:
            return EQBand.classic.reduce(into: [:]) { $0[$1.frequencyHz] = 0 }
        case .bassBoost:
            return [
                31: 6,
                62: 5,
                125: 3,
                250: 1,
                500: 0,
                1_000: 0,
                2_000: 0,
                4_000: 0,
                8_000: 0,
                16_000: 0
            ]
        case .vocalLift:
            return [
                31: -2,
                62: -1,
                125: 0,
                250: 1,
                500: 2,
                1_000: 4,
                2_000: 4,
                4_000: 2,
                8_000: 0,
                16_000: 0
            ]
        case .bright:
            return [
                31: 0,
                62: 0,
                125: 0,
                250: 0,
                500: 0,
                1_000: 1,
                2_000: 2,
                4_000: 4,
                8_000: 5,
                16_000: 4
            ]
        }
    }
}

public struct EQSettings: Equatable, Codable, Sendable {
    public var bandGainsDB: [Int: Double]
    public var preampDB: Double
    public var isBypassed: Bool

    public static let gainRange: ClosedRange<Double> = -12...12

    public static var flat: EQSettings {
        EQSettings(
            bandGainsDB: EQPreset.flat.gains,
            preampDB: 0,
            isBypassed: false
        )
    }

    public static func applying(_ preset: EQPreset) -> EQSettings {
        var settings = EQSettings.flat
        settings.apply(preset)
        return settings
    }

    public mutating func setGain(_ gain: Double, for frequencyHz: Int) {
        guard EQBand.classic.contains(where: { $0.frequencyHz == frequencyHz }) else {
            return
        }
        bandGainsDB[frequencyHz] = Self.clamp(gain)
    }

    public func gain(for frequencyHz: Int) -> Double {
        bandGainsDB[frequencyHz] ?? 0
    }

    public mutating func apply(_ preset: EQPreset) {
        bandGainsDB = preset.gains.mapValues(Self.clamp)
    }

    public mutating func reset() {
        self = .flat
    }

    public static func clamp(_ gain: Double) -> Double {
        min(gainRange.upperBound, max(gainRange.lowerBound, gain))
    }
}

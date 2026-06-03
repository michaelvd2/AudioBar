import Foundation

public final class EQProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Double
    private var channelCount: Int
    private var settings: EQSettings
    private var preampLinear: Float
    private var filtersByChannel: [[BiquadFilter]]

    public init(sampleRate: Double, channelCount: Int, settings: EQSettings = .flat) {
        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.settings = settings
        self.preampLinear = Self.linearGain(settings.preampDB)
        self.filtersByChannel = Self.makeFilters(
            sampleRate: sampleRate,
            channelCount: max(1, channelCount),
            settings: settings
        )
    }

    public func update(settings: EQSettings) {
        lock.lock()
        defer { lock.unlock() }

        self.settings = settings
        preampLinear = Self.linearGain(settings.preampDB)
        filtersByChannel = Self.makeFilters(
            sampleRate: sampleRate,
            channelCount: channelCount,
            settings: settings
        )
    }

    public func reset(sampleRate: Double, channelCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        filtersByChannel = Self.makeFilters(
            sampleRate: sampleRate,
            channelCount: self.channelCount,
            settings: settings
        )
    }

    public func processInterleaved(
        input: [Float32],
        output: inout [Float32],
        frameCount: Int,
        channelCount: Int
    ) {
        precondition(output.count >= frameCount * channelCount)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                guard let inputBase = inputBuffer.baseAddress,
                      let outputBase = outputBuffer.baseAddress
                else {
                    return
                }
                processInterleaved(
                    input: inputBase,
                    output: outputBase,
                    frameCount: frameCount,
                    channelCount: channelCount
                )
            }
        }
    }

    public func processInterleaved(
        input: UnsafePointer<Float32>,
        output: UnsafeMutablePointer<Float32>,
        frameCount: Int,
        channelCount: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        let channelCount = max(1, channelCount)
        ensureChannelCapacity(channelCount)

        if settings.isBypassed {
            output.update(from: input, count: frameCount * channelCount)
            return
        }

        for frame in 0..<frameCount {
            let frameOffset = frame * channelCount
            for channel in 0..<channelCount {
                let index = frameOffset + channel
                var sample = input[index] * preampLinear
                for filterIndex in filtersByChannel[channel].indices {
                    sample = filtersByChannel[channel][filterIndex].process(sample)
                }
                output[index] = sample
            }
        }
    }

    private func ensureChannelCapacity(_ requestedChannelCount: Int) {
        guard requestedChannelCount > filtersByChannel.count else {
            return
        }

        let extra = requestedChannelCount - filtersByChannel.count
        filtersByChannel.append(contentsOf: Self.makeFilters(
            sampleRate: sampleRate,
            channelCount: extra,
            settings: settings
        ))
    }

    private static func makeFilters(
        sampleRate: Double,
        channelCount: Int,
        settings: EQSettings
    ) -> [[BiquadFilter]] {
        let filters = EQBand.classic.map { band in
            BiquadFilter.peakingEQ(
                sampleRate: sampleRate,
                frequency: Double(band.frequencyHz),
                q: 1.0,
                gainDB: settings.gain(for: band.frequencyHz)
            )
        }
        return Array(repeating: filters, count: channelCount)
    }

    private static func linearGain(_ gainDB: Double) -> Float {
        Float(pow(10, gainDB / 20))
    }
}

private struct BiquadFilter {
    var b0: Double
    var b1: Double
    var b2: Double
    var a1: Double
    var a2: Double
    var z1: Double = 0
    var z2: Double = 0

    mutating func process(_ sample: Float32) -> Float32 {
        let input = Double(sample)
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return Float32(output)
    }

    static func peakingEQ(
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gainDB: Double
    ) -> BiquadFilter {
        guard gainDB != 0, sampleRate > 0, frequency > 0, q > 0 else {
            return BiquadFilter(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
        }

        let nyquist = sampleRate / 2
        let clampedFrequency = min(frequency, nyquist * 0.95)
        let omega = 2 * Double.pi * clampedFrequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let amplitude = pow(10, gainDB / 40)

        let b0 = 1 + alpha * amplitude
        let b1 = -2 * cosine
        let b2 = 1 - alpha * amplitude
        let a0 = 1 + alpha / amplitude
        let a1 = -2 * cosine
        let a2 = 1 - alpha / amplitude

        return BiquadFilter(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

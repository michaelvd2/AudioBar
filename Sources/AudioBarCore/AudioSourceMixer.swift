import Foundation

enum AudioSourceMixer {
    static func mixInterleaved(
        sources: [(samples: [Float32], gain: Float32)],
        output: inout [Float32]
    ) {
        output = Array(repeating: 0, count: output.count)

        for source in sources {
            let count = min(output.count, source.samples.count)
            guard count > 0 else {
                continue
            }

            let gain = max(0, min(1, source.gain))
            if gain == 0 {
                continue
            }

            for index in 0..<count {
                output[index] += source.samples[index] * gain
            }
        }
    }

    static func mixInterleaved(
        sources: [(pointer: UnsafePointer<Float32>, sampleCount: Int, gain: Float32)],
        output: UnsafeMutablePointer<Float32>,
        sampleCount: Int
    ) {
        guard sampleCount > 0 else {
            return
        }

        for index in 0..<sampleCount {
            output[index] = 0
        }

        for source in sources {
            let count = min(sampleCount, source.sampleCount)
            guard count > 0 else {
                continue
            }

            let gain = max(0, min(1, source.gain))
            if gain == 0 {
                continue
            }

            for index in 0..<count {
                output[index] += source.pointer[index] * gain
            }
        }
    }

    static func mixInterleaved(
        sources: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int, gain: Float32)],
        output: UnsafeMutablePointer<Float32>,
        frameCount: Int,
        channelCount: Int
    ) {
        mixInterleaved(
            sources: sources.map {
                (
                    pointer: $0.pointer,
                    frameCount: $0.frameCount,
                    channelCount: $0.channelCount,
                    gain: $0.gain,
                    balance: Float32(0)
                )
            },
            output: output,
            frameCount: frameCount,
            channelCount: channelCount
        )
    }

    static func mixInterleaved(
        sources: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int, gain: Float32, balance: Float32)],
        output: UnsafeMutablePointer<Float32>,
        frameCount: Int,
        channelCount: Int
    ) {
        mixInterleaved(
            sources: sources.map {
                (
                    pointer: $0.pointer,
                    frameCount: $0.frameCount,
                    channelCount: $0.channelCount,
                    gain: $0.gain,
                    balance: $0.balance,
                    isMono: false
                )
            },
            output: output,
            frameCount: frameCount,
            channelCount: channelCount
        )
    }

    static func mixInterleaved(
        sources: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int, gain: Float32, balance: Float32, isMono: Bool)],
        output: UnsafeMutablePointer<Float32>,
        frameCount: Int,
        channelCount: Int
    ) {
        let channelCount = max(1, channelCount)
        let sampleCount = frameCount * channelCount
        guard sampleCount > 0 else {
            return
        }

        for index in 0..<sampleCount {
            output[index] = 0
        }

        for source in sources {
            let sourceChannelCount = max(1, source.channelCount)
            let sourceFrameCount = min(frameCount, source.frameCount)
            guard sourceFrameCount > 0 else {
                continue
            }

            let gain = max(0, min(1, source.gain))
            if gain == 0 {
                continue
            }
            let balance = max(-1, min(1, source.balance))
            let leftGain = gain * min(1, 1 - balance)
            let rightGain = gain * min(1, 1 + balance)

            for frame in 0..<sourceFrameCount {
                let sourceFrameOffset = frame * sourceChannelCount
                let outputFrameOffset = frame * channelCount

                if source.isMono || (channelCount == 1 && sourceChannelCount > 1) {
                    var monoSample: Float32 = 0
                    for sourceChannel in 0..<sourceChannelCount {
                        monoSample += source.pointer[sourceFrameOffset + sourceChannel]
                    }
                    monoSample /= Float32(sourceChannelCount)

                    if channelCount == 1 {
                        output[outputFrameOffset] += monoSample * gain
                    } else {
                        for outputChannel in 0..<channelCount {
                            let channelGain: Float32
                            if outputChannel == 0 {
                                channelGain = leftGain
                            } else if outputChannel == 1 {
                                channelGain = rightGain
                            } else if sourceChannelCount == 1 {
                                channelGain = gain
                            } else {
                                continue
                            }
                            output[outputFrameOffset + outputChannel] += monoSample * channelGain
                        }
                    }
                } else {
                    for outputChannel in 0..<channelCount {
                        let channelGain = outputChannel == 0 ? leftGain : rightGain
                        if outputChannel < sourceChannelCount {
                            output[outputFrameOffset + outputChannel] += source.pointer[sourceFrameOffset + outputChannel] * channelGain
                        } else if sourceChannelCount == 1 {
                            output[outputFrameOffset + outputChannel] += source.pointer[sourceFrameOffset] * channelGain
                        }
                    }
                }
            }
        }
    }

}

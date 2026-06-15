import XCTest
@testable import AudioBarCore

final class AudioSourceMixerTests: XCTestCase {
    func testMixerSumsSourcesWithPerSourceGain() {
        var output = Array<Float32>(repeating: -1, count: 4)

        AudioSourceMixer.mixInterleaved(
            sources: [
                (samples: [1, 0.5, -1, -0.5], gain: 0.5),
                (samples: [0.25, 0.25, 0.25, 0.25], gain: 0.25)
            ],
            output: &output
        )

        XCTAssertEqual(output[0], 0.5625, accuracy: 0.0001)
        XCTAssertEqual(output[1], 0.3125, accuracy: 0.0001)
        XCTAssertEqual(output[2], -0.4375, accuracy: 0.0001)
        XCTAssertEqual(output[3], -0.1875, accuracy: 0.0001)
    }

    func testMixerClampsSourceGain() {
        var output = Array<Float32>(repeating: 0, count: 2)

        AudioSourceMixer.mixInterleaved(
            sources: [
                (samples: [1, 1], gain: 2),
                (samples: [1, 1], gain: -1)
            ],
            output: &output
        )

        XCTAssertEqual(output, [1, 1])
    }

    func testChannelAwareMixerPreservesStereoTapChannelsForSplitSpeakerOutput() {
        let source: [Float32] = [
            0.1, 0.9,
            0.2, 0.8,
            0.3, 0.7
        ]
        var output = Array<Float32>(repeating: 0, count: source.count)

        source.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioSourceMixer.mixInterleaved(
                    sources: [(
                        pointer: sourceBuffer.baseAddress!,
                        frameCount: 3,
                        channelCount: 2,
                        gain: 1
                    )],
                    output: outputBuffer.baseAddress!,
                    frameCount: 3,
                    channelCount: 2
                )
            }
        }

        XCTAssertEqual(output, source)
    }

    func testChannelAwareMixerAppliesPerSourceStereoBalance() {
        let source: [Float32] = [
            0.1, 0.9,
            0.2, 0.8
        ]
        var output = Array<Float32>(repeating: 0, count: source.count)

        source.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioSourceMixer.mixInterleaved(
                    sources: [(
                        pointer: sourceBuffer.baseAddress!,
                        frameCount: 2,
                        channelCount: 2,
                        gain: 1,
                        balance: -1
                    )],
                    output: outputBuffer.baseAddress!,
                    frameCount: 2,
                    channelCount: 2
                )
            }
        }

        XCTAssertEqual(output, [
            0.1, 0,
            0.2, 0
        ])
    }

    func testChannelAwareMixerDownmixesStereoTapForMonoOutputBuffer() {
        let source: [Float32] = [
            0.1, 0.9,
            0.2, 0.8,
            0.3, 0.7
        ]
        var output = Array<Float32>(repeating: 0, count: 3)

        source.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioSourceMixer.mixInterleaved(
                    sources: [(
                        pointer: sourceBuffer.baseAddress!,
                        frameCount: 3,
                        channelCount: 2,
                        gain: 1
                    )],
                    output: outputBuffer.baseAddress!,
                    frameCount: 3,
                    channelCount: 1
                )
            }
        }

        XCTAssertEqual(output[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(output[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(output[2], 0.5, accuracy: 0.0001)
    }

    func testChannelAwareMixerLeavesExtraMultichannelOutputsSilentForStereoTap() {
        let source: [Float32] = [
            0.1, 0.9,
            0.2, 0.8
        ]
        var output = Array<Float32>(repeating: -1, count: 8)

        source.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioSourceMixer.mixInterleaved(
                    sources: [(
                        pointer: sourceBuffer.baseAddress!,
                        frameCount: 2,
                        channelCount: 2,
                        gain: 1
                    )],
                    output: outputBuffer.baseAddress!,
                    frameCount: 2,
                    channelCount: 4
                )
            }
        }

        XCTAssertEqual(output, [
            0.1, 0.9, 0, 0,
            0.2, 0.8, 0, 0
        ])
    }

    func testChannelAwareMixerFansMonoSourceOutToStereoOutput() {
        let source: [Float32] = [0.25, 0.5]
        var output = Array<Float32>(repeating: 0, count: 4)

        source.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioSourceMixer.mixInterleaved(
                    sources: [(
                        pointer: sourceBuffer.baseAddress!,
                        frameCount: 2,
                        channelCount: 1,
                        gain: 1
                    )],
                    output: outputBuffer.baseAddress!,
                    frameCount: 2,
                    channelCount: 2
                )
            }
        }

        XCTAssertEqual(output, [0.25, 0.25, 0.5, 0.5])
    }
}

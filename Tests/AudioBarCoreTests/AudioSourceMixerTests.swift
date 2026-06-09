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
}

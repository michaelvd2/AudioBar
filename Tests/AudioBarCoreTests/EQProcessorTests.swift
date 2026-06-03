import XCTest
@testable import AudioBarCore

final class EQProcessorTests: XCTestCase {
    func testBypassCopiesInputWithoutFiltering() {
        var settings = EQSettings.applying(.bright)
        settings.preampDB = 6
        settings.isBypassed = true
        let processor = EQProcessor(sampleRate: 48_000, channelCount: 2)
        processor.update(settings: settings)

        let input: [Float32] = [0.1, -0.2, 0.3, -0.4, 0.5, -0.6]
        var output = [Float32](repeating: 0, count: input.count)

        processor.processInterleaved(
            input: input,
            output: &output,
            frameCount: 3,
            channelCount: 2
        )

        XCTAssertEqual(output, input)
    }

    func testFlatSettingsPreserveSignalWithinSmallTolerance() {
        let processor = EQProcessor(sampleRate: 48_000, channelCount: 1)
        processor.update(settings: .flat)
        let input = sineWave(frequency: 1_000, sampleRate: 48_000, frameCount: 512)
        var output = [Float32](repeating: 0, count: input.count)

        processor.processInterleaved(
            input: input,
            output: &output,
            frameCount: input.count,
            channelCount: 1
        )

        for (actual, expected) in zip(output, input) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testBoostingOneKilohertzBandIncreasesOneKilohertzRMS() {
        var boostedSettings = EQSettings.flat
        boostedSettings.setGain(12, for: 1_000)

        let input = sineWave(frequency: 1_000, sampleRate: 48_000, frameCount: 4_096)
        var flatOutput = [Float32](repeating: 0, count: input.count)
        var boostedOutput = [Float32](repeating: 0, count: input.count)

        let flatProcessor = EQProcessor(sampleRate: 48_000, channelCount: 1)
        flatProcessor.update(settings: .flat)
        flatProcessor.processInterleaved(
            input: input,
            output: &flatOutput,
            frameCount: input.count,
            channelCount: 1
        )

        let boostedProcessor = EQProcessor(sampleRate: 48_000, channelCount: 1)
        boostedProcessor.update(settings: boostedSettings)
        boostedProcessor.processInterleaved(
            input: input,
            output: &boostedOutput,
            frameCount: input.count,
            channelCount: 1
        )

        XCTAssertGreaterThan(rms(boostedOutput.dropFirst(512)), rms(flatOutput.dropFirst(512)) * 1.5)
    }

    private func sineWave(frequency: Double, sampleRate: Double, frameCount: Int) -> [Float32] {
        (0..<frameCount).map { frame in
            Float32(sin((Double(frame) / sampleRate) * frequency * 2 * .pi) * 0.25)
        }
    }

    private func rms<S: Sequence>(_ samples: S) -> Double where S.Element == Float32 {
        let values = Array(samples)
        let sum = values.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        }
        return sqrt(sum / Double(values.count))
    }
}

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

}

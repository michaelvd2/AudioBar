import CoreAudio
import Foundation

enum SystemEQInputBufferMap {
    static func processObjectID(
        inputIndex: Int,
        inputBufferCount: Int,
        tapProcessObjectIDs: [AudioObjectID?]
    ) -> AudioObjectID? {
        guard inputIndex >= 0, inputBufferCount > 0, !tapProcessObjectIDs.isEmpty else {
            return nil
        }

        let tapCount = tapProcessObjectIDs.count
        let extraInputBufferCount = inputBufferCount % tapCount
        let tapBufferCount = inputBufferCount - extraInputBufferCount
        let buffersPerTap = max(1, tapBufferCount / tapCount)
        let tapStartIndex = extraInputBufferCount
        let tapIndex = inputIndex - tapStartIndex
        guard tapIndex >= 0, tapIndex < tapBufferCount else {
            return nil
        }
        return tapProcessObjectIDs[tapIndex / buffersPerTap]
    }
}

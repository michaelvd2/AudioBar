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

        let tapStartIndex = max(0, inputBufferCount - tapProcessObjectIDs.count)
        let tapIndex = inputIndex - tapStartIndex
        guard tapIndex >= 0, tapIndex < tapProcessObjectIDs.count else {
            return nil
        }
        return tapProcessObjectIDs[tapIndex]
    }
}

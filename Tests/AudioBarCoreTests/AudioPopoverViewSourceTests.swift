import Foundation
import XCTest

final class AudioPopoverViewSourceTests: XCTestCase {
    func testEQPanelKeepsOneSwitchControl() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("Toggle(\"Bypass\""))
        XCTAssertFalse(eqPanel.contains("store.stopEQEngine()"))
        XCTAssertFalse(eqPanel.contains("store.startEQEngine()"))
    }

    private func audioPopoverViewURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/Views/AudioPopoverView.swift")
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }

        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}

import Foundation
import XCTest

final class AudioPopoverViewSourceTests: XCTestCase {
    func testEQPanelKeepsOneSwitchControl() throws {
        let source = try String(contentsOf: audioPopoverViewURL(), encoding: .utf8)
        let eqPanel = try XCTUnwrap(source.slice(
            from: "private struct EQPanelView",
            to: "private struct AudioStreamMeter"
        ))

        XCTAssertTrue(eqPanel.contains("Label(\"EQ\""))
        XCTAssertTrue(eqPanel.contains("Toggle(\"On\""))
        XCTAssertTrue(eqPanel.contains("get: { !store.eqSettings.isBypassed }"))
        XCTAssertTrue(eqPanel.contains("set: { store.setEQBypassed(!$0) }"))
        XCTAssertFalse(eqPanel.contains("store.eqEngineStatus.displayText"))
        XCTAssertFalse(eqPanel.contains("Toggle(\"EQ On\""))
        XCTAssertFalse(eqPanel.contains("Toggle(\"Bypass\""))
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

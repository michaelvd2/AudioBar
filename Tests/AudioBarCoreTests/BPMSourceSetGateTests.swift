import CoreAudio
import XCTest
@testable import AudioBarCore

final class BPMSourceSetGateTests: XCTestCase {
    func testNormalizesAppliedSources() {
        var gate = BPMSourceSetGate(settleInterval: 1)

        let applied = gate.reset(appliedSources: [44, 12, 44, kAudioObjectUnknown])

        XCTAssertEqual(applied, [12, 44])
    }

    func testWaitsForSourceSetToStayStableBeforeApplying() {
        var gate = BPMSourceSetGate(settleInterval: 1)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        _ = gate.reset(appliedSources: [10])

        XCTAssertNil(gate.nextAppliedSources(observed: [30, 20, 20], now: start))
        XCTAssertNil(gate.nextAppliedSources(observed: [20, 30], now: start.addingTimeInterval(0.5)))
        XCTAssertEqual(
            gate.nextAppliedSources(observed: [30, 20], now: start.addingTimeInterval(1.0)),
            [20, 30]
        )
    }

    func testFlickerBackToAppliedSourcesCancelsPendingChange() {
        var gate = BPMSourceSetGate(settleInterval: 1)
        let start = Date(timeIntervalSinceReferenceDate: 200)
        _ = gate.reset(appliedSources: [10])

        XCTAssertNil(gate.nextAppliedSources(observed: [10, 20], now: start))
        XCTAssertNil(gate.nextAppliedSources(observed: [10], now: start.addingTimeInterval(0.25)))
        XCTAssertNil(gate.nextAppliedSources(observed: [10, 20], now: start.addingTimeInterval(0.5)))
        XCTAssertNil(gate.nextAppliedSources(observed: [10, 20], now: start.addingTimeInterval(1.25)))
        XCTAssertEqual(
            gate.nextAppliedSources(observed: [20, 10], now: start.addingTimeInterval(1.5)),
            [10, 20]
        )
    }
}

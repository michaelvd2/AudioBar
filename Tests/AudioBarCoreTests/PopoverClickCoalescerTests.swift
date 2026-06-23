import XCTest
@testable import AudioBarCore

final class PopoverClickCoalescerTests: XCTestCase {
    private let coalescer = PopoverClickCoalescer(window: 0.2)
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testFirstClickWhenClosedOpens() {
        XCTAssertEqual(
            coalescer.resolve(intendedOpen: false, lastInteraction: nil, now: t0),
            .open
        )
    }

    func testFirstClickWhenOpenCloses() {
        XCTAssertEqual(
            coalescer.resolve(intendedOpen: true, lastInteraction: nil, now: t0),
            .close
        )
    }

    func testSecondHandlerWithinWindowIsIgnored() {
        // One physical click fires two handlers (the button action and the OS
        // expanded-interface session). The second must not re-toggle.
        let secondHandler = t0.addingTimeInterval(0.01)
        XCTAssertEqual(
            coalescer.resolve(intendedOpen: true, lastInteraction: t0, now: secondHandler),
            .ignore
        )
    }

    func testRaceCannotCloseAFreshlyOpenedPopover() {
        // Regression for the intermittent "won't open": the OS session (onBegin)
        // opened the popover microseconds ago, flipping intent to open. The
        // button action firing later in the SAME click must be ignored, not read
        // the now-open intent and close what was just opened.
        let buttonActionAfterOnBegin = t0.addingTimeInterval(0.005)
        XCTAssertEqual(
            coalescer.resolve(intendedOpen: true, lastInteraction: t0, now: buttonActionAfterOnBegin),
            .ignore
        )
    }

    func testDeliberateClickAfterWindowActs() {
        let laterClick = t0.addingTimeInterval(0.3)
        XCTAssertEqual(
            coalescer.resolve(intendedOpen: true, lastInteraction: t0, now: laterClick),
            .close
        )
    }
}

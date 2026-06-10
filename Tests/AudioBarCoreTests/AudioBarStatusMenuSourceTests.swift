import Foundation
import XCTest

final class AudioBarStatusMenuSourceTests: XCTestCase {
    func testAudioBarUsesStatusItemControllerInsteadOfMenuBarExtraOnly() throws {
        let source = try String(contentsOf: audioBarAppURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private var statusBarController: AudioBarStatusBarController?"))
        XCTAssertTrue(source.contains("AudioBarStatusBarController(store: store)"))
        XCTAssertFalse(source.contains("MenuBarExtra("))
    }

    func testStatusItemRightClickMenuOnlyExposesQuitBecauseSettingsLiveInLeftClickPanel() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("button.sendAction(on: [.leftMouseDown, .rightMouseDown])"))
        XCTAssertTrue(source.contains("event.type == .rightMouseDown"))
        XCTAssertTrue(source.contains("showContextMenu(for: sender)"))
        XCTAssertTrue(source.contains("NSMenuItem(title: \"Quit\""))
        XCTAssertFalse(source.contains("NSMenuItem(title: \"Settings...\""))
        XCTAssertFalse(source.contains("#selector(showSettingsFromMenu)"))
    }

    func testPopoverStaysOpenDuringAutomatedVolumeChanges() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("popover.behavior = .applicationDefined"))
        XCTAssertFalse(source.contains("popover.behavior = .transient"))
    }

    private func audioBarAppURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/App/AudioBarApp.swift")
    }

    private func statusBarControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/App/AudioBarStatusBarController.swift")
    }
}

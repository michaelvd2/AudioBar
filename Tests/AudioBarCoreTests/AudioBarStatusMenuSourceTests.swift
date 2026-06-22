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

    func testPopoverStartsBPMAnalysisAfterShowing() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("store.startBPMAnalysis()"))
        XCTAssertFalse(source.contains("// store.startBPMAnalysis()"))
    }

    func testStatusItemIconReflectsEffectiveEQOutputState() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("import Combine"))
        XCTAssertTrue(source.contains("private var cancellables: Set<AnyCancellable> = []"))
        XCTAssertTrue(source.contains("observeEQStatusIcon()"))
        XCTAssertTrue(source.contains("store.$eqEngineStatus"))
        XCTAssertTrue(source.contains("store.$eqSettings"))
        XCTAssertTrue(source.contains("Publishers.CombineLatest(store.$eqEngineStatus, store.$eqSettings)"))
        XCTAssertTrue(source.contains("updateStatusIcon(status: status, settings: settings)"))
        XCTAssertTrue(source.contains("updateStatusIcon(status: store.eqEngineStatus, settings: store.eqSettings)"))
        XCTAssertTrue(source.contains("static func isEQAudible(status: SystemEQEngineStatus, settings: EQSettings) -> Bool"))
        XCTAssertTrue(source.contains("status == .active && !settings.isBypassed"))
        XCTAssertTrue(source.contains("static func statusIconSymbolName(status: SystemEQEngineStatus, settings: EQSettings) -> String"))
        XCTAssertTrue(source.contains("isEQAudible(status: status, settings: settings) ? \"speaker.wave.2.fill\" : \"speaker.wave.2\""))
        XCTAssertFalse(source.contains("button.image = NSImage(systemSymbolName: \"speaker.wave.2\", accessibilityDescription: \"AudioBar\")"))
    }

    func testPopoverClosesWhenAppMovesToBackground() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("NSApplication.didResignActiveNotification"))
        XCTAssertTrue(source.contains("#selector(closePopoverWhenAppResignsActive)"))
        XCTAssertTrue(source.contains("@objc private func closePopoverWhenAppResignsActive"))
        XCTAssertTrue(source.contains("popover.performClose(nil)"))
    }

    func testPopoverDoesNotCloseWhenAudioBarVolumeCommandMovesFocus() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Notification.Name.audioBarWillRunExternalFocusCommand"))
        XCTAssertTrue(source.contains("#selector(retainPopoverForExternalVolumeCommand)"))
        XCTAssertTrue(source.contains("private var suppressResignActiveCloseUntil"))
        XCTAssertTrue(source.contains("@objc private func retainPopoverForExternalVolumeCommand"))
        XCTAssertTrue(source.contains("suppressResignActiveCloseUntil = Date().addingTimeInterval(1.2)"))
        XCTAssertTrue(source.contains("if shouldSuppressResignActiveClose()"))
        XCTAssertTrue(source.contains("private func shouldSuppressResignActiveClose() -> Bool"))
    }

    func testPopoverClosesWhenClickingOutsideStatusItemAndPopover() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("outsideClickMonitor"))
        XCTAssertTrue(source.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(source.contains("closePopoverIfClickIsOutside"))
        XCTAssertTrue(source.contains("popover.contentViewController?.view.window"))
        XCTAssertTrue(source.contains("button.window?.frame.contains"))
        XCTAssertTrue(source.contains("popoverWindow.frame.contains"))
        XCTAssertTrue(source.contains("popover.performClose(nil)"))
    }

    func testPopoverDoesNotCloseForClicksDeliveredInsideAudioBarWindows() throws {
        let source = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("eventWindow === popoverWindow"))
        XCTAssertTrue(source.contains("eventWindow === button.window"))
    }

    func testStatusItemUsesRuntimeExpandedInterfaceBridgeForMacOS27() throws {
        let controllerSource = try String(contentsOf: statusBarControllerURL(), encoding: .utf8)
        let bridgeSource = try String(contentsOf: statusItemBridgeURL(), encoding: .utf8)

        XCTAssertTrue(controllerSource.contains("private var expandedInterfaceBridge: StatusItemExpandedInterfaceBridge?"))
        XCTAssertTrue(controllerSource.contains("installExpandedInterfaceBridge()"))
        XCTAssertTrue(controllerSource.contains("expandedInterfaceBridge?.cancelSessionIfAvailable()"))
        XCTAssertTrue(bridgeSource.contains("setExpandedInterfaceDelegate:"))
        XCTAssertTrue(bridgeSource.contains("statusItem:didBeginExpandedInterfaceSession:"))
        XCTAssertTrue(bridgeSource.contains("statusItemDidEndExpandedInterfaceSession:animated:"))
        XCTAssertFalse(bridgeSource.contains("NSStatusItemExpandedInterfaceDelegate"))
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

    private func statusItemBridgeURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/App/StatusItemExpandedInterfaceBridge.swift")
    }
}

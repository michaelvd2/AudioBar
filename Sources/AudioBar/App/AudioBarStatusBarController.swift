import AppKit
import SwiftUI

@MainActor
final class AudioBarStatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: AudioProcessStore
    private let popover = NSPopover()

    init(store: AudioProcessStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configurePopover()
        observeAppDeactivation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "AudioBar")
        button.toolTip = "AudioBar"
        button.target = self
        button.action = #selector(handleStatusButtonAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 430, height: 560)
        popover.contentViewController = NSHostingController(rootView: AudioPopoverView(store: store))
    }

    private func observeAppDeactivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverWhenAppResignsActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleStatusButtonAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }

        if event.type == .rightMouseDown {
            showContextMenu(for: sender)
            return
        }

        guard event.type == .leftMouseDown else {
            return
        }

        togglePopover(relativeTo: sender)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        showSettings(relativeTo: button)
    }

    private func showContextMenu(for button: NSStatusBarButton) {
        popover.performClose(nil)

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func showSettings(relativeTo button: NSStatusBarButton) {
        popover.contentSize = NSSize(width: 430, height: 560)
        let anchorRect = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
        popover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showFirstUseSetup() {
        guard let button = statusItem.button else {
            return
        }

        showSettings(relativeTo: button)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func closePopoverWhenAppResignsActive() {
        popover.performClose(nil)
    }
}

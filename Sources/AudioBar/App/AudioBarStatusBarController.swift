import AppKit
import Combine
import SwiftUI

@MainActor
final class AudioBarStatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: AudioProcessStore
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var suppressResignActiveCloseUntil: Date?
    private var cancellables: Set<AnyCancellable> = []

    init(store: AudioProcessStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configurePopover()
        observeEQStatusIcon()
        observeAppDeactivation()
        observeVolumeCommandRetention()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        MainActor.assumeIsolated {
            removeOutsideClickMonitors()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        updateStatusIcon(isEQEnabled: !store.eqSettings.isBypassed)
        button.target = self
        button.action = #selector(handleStatusButtonAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    private func observeEQStatusIcon() {
        store.$eqSettings
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.updateStatusIcon(isEQEnabled: !settings.isBypassed)
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(isEQEnabled: Bool) {
        guard let button = statusItem.button else {
            return
        }

        let description = isEQEnabled ? "AudioBar EQ on" : "AudioBar EQ off"
        button.image = NSImage(
            systemSymbolName: Self.statusIconSymbolName(isEQEnabled: isEQEnabled),
            accessibilityDescription: description
        )
        button.toolTip = isEQEnabled ? "AudioBar: EQ On" : "AudioBar: EQ Off"
    }

    static func statusIconSymbolName(isEQEnabled: Bool) -> String {
        isEQEnabled ? "speaker.wave.2.fill" : "speaker.wave.2"
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

    private func observeVolumeCommandRetention() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(retainPopoverForExternalVolumeCommand),
            name: Notification.Name.audioBarWillRunExternalFocusCommand,
            object: store
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
            closePopover()
            return
        }

        showSettings(relativeTo: button)
    }

    private func showContextMenu(for button: NSStatusBarButton) {
        closePopover()

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
        installOutsideClickMonitors()
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
        if shouldSuppressResignActiveClose() {
            return
        }

        closePopover()
    }

    @objc private func retainPopoverForExternalVolumeCommand() {
        suppressResignActiveCloseUntil = Date().addingTimeInterval(1.2)
    }

    private func shouldSuppressResignActiveClose() -> Bool {
        guard let suppressResignActiveCloseUntil else {
            return false
        }
        if suppressResignActiveCloseUntil > Date() {
            return true
        }
        self.suppressResignActiveCloseUntil = nil
        return false
    }

    private func closePopover() {
        popover.performClose(nil)
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window,
              let button = statusItem.button
        else {
            return
        }

        if let eventWindow = event.window,
           eventWindow === popoverWindow || eventWindow === button.window
        {
            return
        }

        let screenPoint = event.locationInWindow
        let clickPoint: NSPoint
        if let eventWindow = event.window {
            clickPoint = eventWindow.convertPoint(toScreen: screenPoint)
        } else {
            clickPoint = screenPoint
        }

        if button.window?.frame.contains(clickPoint) == true {
            return
        }

        if popoverWindow.frame.contains(clickPoint) {
            return
        }

        closePopover()
    }
}

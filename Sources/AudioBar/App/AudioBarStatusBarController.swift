import AppKit
import AudioBarCore
import Combine
import SwiftUI

@MainActor
final class AudioBarStatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: AudioProcessStore
    private let popover = NSPopover()
    private var expandedInterfaceBridge: StatusItemExpandedInterfaceBridge?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var suppressResignActiveCloseUntil: Date?
    private var popoverIntendedOpen = false
    private var suppressExpandedBeginUntil: Date?
    private var cancellables: Set<AnyCancellable> = []

    init(store: AudioProcessStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configurePopover()
        installExpandedInterfaceBridge()
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

        updateStatusIcon(status: store.eqEngineStatus, settings: store.eqSettings)
        button.target = self
        button.action = #selector(handleStatusButtonAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    private func observeEQStatusIcon() {
        Publishers.CombineLatest(store.$eqEngineStatus, store.$eqSettings)
            .sink { [weak self] status, settings in
                Task { @MainActor in
                    self?.updateStatusIcon(status: status, settings: settings)
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(status: SystemEQEngineStatus, settings: EQSettings) {
        guard let button = statusItem.button else {
            return
        }

        let isEQEnabled = Self.isEQAudible(status: status, settings: settings)
        let description = isEQEnabled ? "AudioBar EQ on" : "AudioBar EQ off"
        button.image = NSImage(
            systemSymbolName: Self.statusIconSymbolName(status: status, settings: settings),
            accessibilityDescription: description
        )
        button.toolTip = isEQEnabled ? "AudioBar: EQ On" : "AudioBar: EQ Off"
    }

    static func isEQAudible(status: SystemEQEngineStatus, settings: EQSettings) -> Bool {
        status == .active && !settings.isBypassed
    }

    static func statusIconSymbolName(status: SystemEQEngineStatus, settings: EQSettings) -> String {
        isEQAudible(status: status, settings: settings) ? "speaker.wave.2.fill" : "speaker.wave.2"
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = false
        let hostingController = NSHostingController(rootView: AudioPopoverView(store: store))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func installExpandedInterfaceBridge() {
        expandedInterfaceBridge = StatusItemExpandedInterfaceBridge(
            statusItem: statusItem,
            onBegin: { [weak self] in
                guard let self, let button = self.statusItem.button else {
                    return
                }

                // Don't let an OS session-begin re-open the popover right after a
                // deliberate close (rapid click-to-close race).
                if let until = self.suppressExpandedBeginUntil, until > Date() {
                    return
                }

                self.showSettingsIfNeeded(relativeTo: button)
            },
            onEnd: { [weak self] in
                self?.closePopoverFromExpandedInterfaceSession()
            }
        )
        expandedInterfaceBridge?.installIfAvailable()
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
        // Toggle on our own synchronous intent, not popover.isShown — the latter
        // lags behind show/close (and the OS expanded-interface session), so on
        // fast clicks it read stale and the popover could stay open.
        if popoverIntendedOpen {
            closePopover()
            return
        }

        showSettingsIfNeeded(relativeTo: button)
    }

    private func showContextMenu(for button: NSStatusBarButton) {
        closePopover()

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func showSettingsIfNeeded(relativeTo button: NSStatusBarButton) {
        popoverIntendedOpen = true
        guard !popover.isShown else {
            return
        }

        let anchorRect = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
        popover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
        installOutsideClickMonitors()
        NSApp.activate(ignoringOtherApps: true)
        store.startBPMAnalysis()
    }

    func showFirstUseSetup() {
        guard let button = statusItem.button else {
            return
        }

        showSettingsIfNeeded(relativeTo: button)
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
        expandedInterfaceBridge?.cancelSessionIfAvailable()
        closePopoverWithoutCancelingExpandedInterface()
    }

    private func closePopoverFromExpandedInterfaceSession() {
        closePopoverWithoutCancelingExpandedInterface()
    }

    private func closePopoverWithoutCancelingExpandedInterface() {
        popoverIntendedOpen = false
        // Briefly ignore an OS expanded-interface "begin" right after a deliberate
        // close, so a fast click-to-close isn't immediately undone by the bridge
        // re-opening the popover (the rapid-click "won't close" race).
        suppressExpandedBeginUntil = Date().addingTimeInterval(0.3)
        popover.performClose(nil)
        removeOutsideClickMonitors()
        store.stopBPMAnalysisIfNotBackground()
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

        // A click inside a child popover we present from the main popover (e.g.
        // the output/input device switcher) is not an "outside" click — keep the
        // main popover open so picking a device doesn't dismiss everything.
        if let eventWindow = event.window,
           String(describing: type(of: eventWindow)).contains("Popover")
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

import AppKit
import AudioBarCore
import Combine
import SwiftUI

@MainActor
final class AudioBarStatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let store: AudioProcessStore
    private let popover = NSPopover()
    private var expandedInterfaceBridge: StatusItemExpandedInterfaceBridge?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var suppressResignActiveCloseUntil: Date?
    private var popoverIntendedOpen = false
    /// One physical status-item click is seen by both the button action and the
    /// OS expanded-interface session, in a non-deterministic order. Coalesce
    /// them so a single click resolves to exactly one open/close.
    private let clickCoalescer = PopoverClickCoalescer(window: 0.2)
    private var lastInteractionTime: Date?
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
        popover.delegate = self
        let hostingController = NSHostingController(rootView: AudioPopoverView(store: store))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    /// Fires on ANY popover close (ours, an OS-initiated close, app hide, etc.).
    /// Resync the intent flag so a close that bypassed our own teardown can't
    /// leave the toggle thinking it's still open — the recurring "can't reopen".
    func popoverDidClose(_ notification: Notification) {
        popoverIntendedOpen = false
        removeOutsideClickMonitors()
    }

    private func installExpandedInterfaceBridge() {
        expandedInterfaceBridge = StatusItemExpandedInterfaceBridge(
            statusItem: statusItem,
            onBegin: { [weak self] in
                guard let self, let button = self.statusItem.button else {
                    return
                }

                // Same entry point as the button action — the coalescer decides
                // open vs close once per click regardless of which path fires.
                self.togglePopover(relativeTo: button)
            },
            onEnd: { [weak self] in
                self?.handleExpandedInterfaceSessionEnd()
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
        // The button action and the OS expanded-interface session both call here
        // for one physical click. Coalesce: the first handler in a fresh window
        // decides (from our synchronous intent, not the laggy popover.isShown),
        // and any later handler for the same click is ignored — so the OS session
        // can't open the popover only for the button action to immediately close
        // it (the intermittent "won't open on click").
        let now = Date()
        switch clickCoalescer.resolve(
            intendedOpen: popoverIntendedOpen,
            lastInteraction: lastInteractionTime,
            now: now
        ) {
        case .ignore:
            return
        case .open:
            lastInteractionTime = now
            showSettingsIfNeeded(relativeTo: button)
        case .close:
            lastInteractionTime = now
            closePopover()
        }
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
        // BPM analysis is intentionally decoupled from the popover lifecycle —
        // opening/closing must not start or stop it. Driving it from here churned
        // CoreAudio aggregates and wedged this toggle. It is controlled solely by
        // the explicit toggle in the store.
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

    /// The OS ended the expanded-interface session — often the same click that
    /// is closing the popover. Claim the click cycle so a trailing button action
    /// for that click is coalesced away and can't reopen what this just closed.
    private func handleExpandedInterfaceSessionEnd() {
        lastInteractionTime = Date()
        closePopoverFromExpandedInterfaceSession()
    }

    private func closePopoverFromExpandedInterfaceSession() {
        closePopoverWithoutCancelingExpandedInterface()
    }

    private func closePopoverWithoutCancelingExpandedInterface() {
        popoverIntendedOpen = false
        popover.performClose(nil)
        removeOutsideClickMonitors()
        // BPM analysis is intentionally NOT tied to the popover lifecycle — it
        // runs only via the explicit toggle. Starting/stopping it on every
        // open/close churned CoreAudio aggregates and wedged this toggle.
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

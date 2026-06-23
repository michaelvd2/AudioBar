import AppKit
import SwiftUI

@main
@MainActor
struct AudioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AudioProcessStore?
    private var statusBarController: AudioBarStatusBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit's tooltip manager waits ~1.5s before showing a `.help` tooltip.
        // It reads this delay (in milliseconds) from user defaults, so set it
        // before any view appears to make tooltips show quickly. Registered (not
        // written) so a user override would still win.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AudioProcessStore()
        self.store = store
        statusBarController = AudioBarStatusBarController(store: store)
        store.startAutoRefresh()
        if store.needsFirstUseSetup {
            statusBarController?.showFirstUseSetup()
        }
    }
}

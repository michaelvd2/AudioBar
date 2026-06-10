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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AudioProcessStore()
        self.store = store
        statusBarController = AudioBarStatusBarController(store: store)
        store.startAutoRefresh()
    }
}

import AppKit
import SwiftUI

@main
@MainActor
struct AudioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AudioProcessStore()

    var body: some Scene {
        MenuBarExtra("Audio", systemImage: "speaker.wave.2") {
            AudioPopoverView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

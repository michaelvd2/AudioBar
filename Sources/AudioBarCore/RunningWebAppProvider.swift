import AppKit
import ApplicationServices
import Foundation

public struct RunningWebAppProvider {
    public init() {}

    public func runningWebApps() -> [WebAppDescriptor] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  bundleID.hasPrefix("com.apple.Safari.WebApp."),
                  let displayName = Self.displayName(localizedName: app.localizedName, bundleURL: app.bundleURL)
            else {
                return nil
            }

            return WebAppDescriptor(
                bundleID: bundleID,
                displayName: displayName,
                windowTitle: windowTitle(forPID: app.processIdentifier)
            )
        }
    }

    static func displayName(localizedName: String?, bundleURL: URL?) -> String? {
        let bundleName = bundleURL?
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        if let bundleName, bundleName != "Web App" {
            return bundleName
        }
        return localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private func windowTitle(forPID pid: pid_t) -> String? {
        #if APP_STORE
        return nil
        #else
        if let title = accessibilityWindowTitle(forPID: pid) {
            return title
        }
        return appleScriptWindowTitle(forPID: pid)
        #endif
    }

    private func accessibilityWindowTitle(forPID pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement],
              let firstWindow = windows.first
        else {
            return nil
        }

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            firstWindow,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else {
            return nil
        }
        return (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private func appleScriptWindowTitle(forPID pid: pid_t) -> String? {
        let script = """
        tell application "System Events"
            tell (first process whose unix id is \(pid))
                if (count of windows) is 0 then return ""
                return name of window 1
            end tell
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }
        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }
        return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

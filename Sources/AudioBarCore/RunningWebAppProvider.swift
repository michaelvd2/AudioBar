import AppKit
import Foundation

public struct RunningWebAppProvider {
    public init() {}

    public func runningWebApps() -> [WebAppDescriptor] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  bundleID.hasPrefix("com.apple.Safari.WebApp."),
                  let displayName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty
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

    private func windowTitle(forPID pid: pid_t) -> String? {
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

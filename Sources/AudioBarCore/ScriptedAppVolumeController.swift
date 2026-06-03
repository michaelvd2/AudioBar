import Foundation

public protocol AppVolumeControlling {
    func currentVolume(for bundleID: String?) -> Int?
    func setVolume(_ volume: Int, for bundleID: String?) -> Bool
    func currentTrackTitle(for bundleID: String?) -> String?
}

public final class ScriptedAppVolumeController: AppVolumeControlling {
    public init() {}

    public func currentVolume(for bundleID: String?) -> Int? {
        guard let bundleID, ScriptedAppVolumeSupport.supports(bundleID) else {
            return nil
        }
        guard let descriptor = run(ScriptVolumeCommandBuilder.getVolumeScript(bundleID: bundleID)) else {
            return nil
        }
        return Int(descriptor.int32Value)
    }

    public func setVolume(_ volume: Int, for bundleID: String?) -> Bool {
        guard let bundleID, ScriptedAppVolumeSupport.supports(bundleID) else {
            return false
        }
        let script = ScriptVolumeCommandBuilder.setVolumeScript(bundleID: bundleID, volume: volume)
        return run(script) != nil
    }

    public func currentTrackTitle(for bundleID: String?) -> String? {
        guard
            let bundleID,
            ScriptedAppVolumeSupport.supports(bundleID),
            let script = ScriptVolumeCommandBuilder.currentTrackScript(bundleID: bundleID),
            let descriptor = run(script)
        else {
            return nil
        }
        return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        return error == nil ? descriptor : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

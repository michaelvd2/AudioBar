import Foundation

public final class SafariMediaVolumeController {
    public init() {}

    public func setVolume(_ volume: Int) -> Bool {
        let source = SafariMediaVolumeCommandBuilder.setVolumeScript(volume: volume)
        guard let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

public final class SafariMediaEQController: @unchecked Sendable {
    public init() {}

    public func apply(settings: EQSettings) -> Bool {
        run(SafariMediaEQCommandBuilder.applyEQScript(settings: settings))
    }

    public func reset() -> Bool {
        var settings = EQSettings.flat
        settings.isBypassed = true
        return apply(settings: settings)
    }

    private func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

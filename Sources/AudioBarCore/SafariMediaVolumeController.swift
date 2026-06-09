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

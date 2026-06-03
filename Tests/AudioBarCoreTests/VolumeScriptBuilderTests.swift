import XCTest
@testable import AudioBarCore

final class VolumeScriptBuilderTests: XCTestCase {
    func testSetVolumeScriptClampsMusicVolumeAndUsesApplicationID() {
        let script = ScriptVolumeCommandBuilder.setVolumeScript(
            bundleID: "com.apple.Music",
            volume: 134
        )

        XCTAssertEqual(
            script,
            """
            tell application id "com.apple.Music"
                set sound volume to 100
            end tell
            """
        )
    }

    func testGetVolumeScriptTargetsSpotifyApplicationID() {
        let script = ScriptVolumeCommandBuilder.getVolumeScript(bundleID: "com.spotify.client")

        XCTAssertEqual(
            script,
            """
            tell application id "com.spotify.client"
                sound volume
            end tell
            """
        )
    }

    func testOnlyKnownScriptableAppsAreAdjustable() {
        XCTAssertEqual(
            ScriptedAppVolumeSupport.capability(for: "com.apple.Music"),
            .scripted
        )
        XCTAssertEqual(
            ScriptedAppVolumeSupport.capability(for: "com.spotify.client"),
            .scripted
        )
        XCTAssertEqual(
            ScriptedAppVolumeSupport.capability(for: "com.apple.Safari"),
            .unavailable(reason: "No public per-app volume control")
        )
    }
}

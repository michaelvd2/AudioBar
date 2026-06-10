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
            .safariMedia
        )
    }

    func testSafariMediaVolumeScriptSetsMediaElementsInFrontTab() {
        let script = SafariMediaVolumeCommandBuilder.setVolumeScript(volume: 37)

        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("current tab of front window"))
        XCTAssertTrue(script.contains("media.volume = 0.37"))
        XCTAssertTrue(script.contains("audio,video"))
    }

    func testYouTubeWebAppKeyboardVolumeScriptSetsVolumeFromZero() {
        let script = WebAppKeyboardVolumeCommandBuilder.setYouTubeVolumeScript(
            bundleID: "com.apple.Safari.WebApp.example",
            volume: 37
        )

        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari.WebApp.example\" to activate"))
        XCTAssertTrue(script.contains("repeat 20 times"))
        XCTAssertTrue(script.contains("key code 125"))
        XCTAssertTrue(script.contains("repeat 7 times"))
        XCTAssertTrue(script.contains("key code 126"))
    }

    func testScriptedPlaybackToggleUsesApplicationID() {
        let script = ScriptPlaybackCommandBuilder.togglePlaybackScript(bundleID: "com.spotify.client")

        XCTAssertEqual(
            script,
            """
            tell application id "com.spotify.client"
                playpause
            end tell
            """
        )
    }

    func testScriptedPlaybackRewindUsesApplicationIDAndPlayerPosition() {
        let script = ScriptPlaybackCommandBuilder.rewind15SecondsScript(bundleID: "com.spotify.client")

        XCTAssertTrue(script.contains("tell application id \"com.spotify.client\""))
        XCTAssertTrue(script.contains("set player position to ((player position) - 15)"))
        XCTAssertTrue(script.contains("return true"))
    }

    func testSafariPlaybackToggleScriptTogglesMediaElementsInFrontTab() {
        let script = SafariMediaPlaybackCommandBuilder.togglePlaybackScript()

        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("current tab of front window"))
        XCTAssertTrue(script.contains("document.querySelectorAll('audio,video')"))
        XCTAssertTrue(script.contains("target.pause()"))
        XCTAssertTrue(script.contains("target.play()"))
    }

    func testSafariPlaybackRewindScriptMovesMediaBackFifteenSeconds() {
        let script = SafariMediaPlaybackCommandBuilder.rewind15SecondsScript()

        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("current tab of front window"))
        XCTAssertTrue(script.contains("document.querySelectorAll('audio,video')"))
        XCTAssertTrue(script.contains("target.currentTime = Math.max(0, target.currentTime - 15)"))
    }

}

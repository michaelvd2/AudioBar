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

    func testSafariMediaEQScriptBuildsWebAudioFilterChain() {
        var settings = EQSettings.flat
        settings.preampDB = 3
        settings.setGain(6, for: 31)
        settings.setGain(-4, for: 16_000)

        let script = SafariMediaEQCommandBuilder.applyEQScript(settings: settings)

        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("current tab of front window"))
        XCTAssertTrue(script.contains("createMediaElementSource"))
        XCTAssertTrue(script.contains("createBiquadFilter"))
        XCTAssertTrue(script.contains("filter.type = 'peaking'"))
        XCTAssertTrue(script.contains("{ frequency: 31, gain: 6.00 }"))
        XCTAssertTrue(script.contains("{ frequency: 16000, gain: -4.00 }"))
        XCTAssertTrue(script.contains("preampDB: 3.00"))
        XCTAssertTrue(script.contains("filter.frequency.value = band.frequency"))
        XCTAssertTrue(script.contains("preamp.gain.value = Math.pow(10, settings.preampDB / 20)"))
    }

    func testSafariMediaEQBypassScriptKeepsMediaAudibleThroughDirectWebAudioConnection() {
        var settings = EQSettings.flat
        settings.isBypassed = true

        let script = SafariMediaEQCommandBuilder.applyEQScript(settings: settings)

        XCTAssertTrue(script.contains("state.source.connect(state.context.destination)"))
        XCTAssertTrue(script.contains("settings.isBypassed"))
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

    func testYouTubeWebAppKeyboardTrackScriptsUseStandardShortcuts() {
        let previousScript = WebAppKeyboardPlaybackCommandBuilder.previousTrackScript(
            bundleID: "com.apple.Safari.WebApp.example"
        )
        let nextScript = WebAppKeyboardPlaybackCommandBuilder.nextTrackScript(
            bundleID: "com.apple.Safari.WebApp.example"
        )

        XCTAssertTrue(previousScript.contains("tell application id \"com.apple.Safari.WebApp.example\" to activate"))
        XCTAssertTrue(previousScript.contains("keystroke \"p\" using {shift down}"))
        XCTAssertTrue(nextScript.contains("tell application id \"com.apple.Safari.WebApp.example\" to activate"))
        XCTAssertTrue(nextScript.contains("keystroke \"n\" using {shift down}"))
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

    func testScriptedTrackNavigationUsesApplicationID() {
        let previousScript = ScriptPlaybackCommandBuilder.previousTrackScript(bundleID: "com.spotify.client")
        let nextScript = ScriptPlaybackCommandBuilder.nextTrackScript(bundleID: "com.spotify.client")

        XCTAssertEqual(
            previousScript,
            """
            tell application id "com.spotify.client"
                previous track
            end tell
            """
        )
        XCTAssertEqual(
            nextScript,
            """
            tell application id "com.spotify.client"
                next track
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

import XCTest
@testable import AudioBarCore

final class AudioProcessDisplayTests: XCTestCase {
    func testDisplayTitlePrefersTrackTitleWhenAvailable() {
        let process = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.spotify.client",
            appName: "Spotify",
            trackTitle: "The Track - The Artist",
            currentVolume: 71,
            volumeCapability: .scripted
        )

        XCTAssertEqual(process.displayTitle, "The Track - The Artist")
        XCTAssertEqual(process.displaySubtitle, "Spotify")
    }

    func testDisplaySubtitleFallsBackToPIDWhenBundleIsMissing() {
        let process = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: nil,
            appName: "Unknown Audio Client",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )

        XCTAssertEqual(process.displayTitle, "Unknown Audio Client")
        XCTAssertEqual(process.displaySubtitle, "PID 345")
    }

    func testDisplaySubtitleUsesHumanReadableSourceKindInsteadOfBundleID() {
        let webApp = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .webAppKeyboard
        )
        let safari = AudioProcess(
            audioObjectID: 13,
            pid: 346,
            bundleID: "com.apple.Safari",
            appName: "Safari",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )

        XCTAssertEqual(webApp.displaySubtitle, "Safari web app")
        XCTAssertEqual(safari.displaySubtitle, "App audio")
        XCTAssertFalse(webApp.displaySubtitle.contains("com.apple"))
        XCTAssertFalse(safari.displaySubtitle.contains("com.apple"))
    }

    func testDisplayTitleUsesHumanReadableBundleNameWhenOnlyBundleIDIsAvailable() {
        let process = AudioProcess(
            audioObjectID: 14,
            pid: 347,
            bundleID: "com.example.Clean.Player",
            appName: "com.example.Clean.Player",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )

        XCTAssertEqual(process.displayTitle, "Player")
        XCTAssertEqual(process.displaySubtitle, "App audio")
    }

    func testSortedForDisplayPutsAdjustableAppsFirstThenNames() {
        let safari = AudioProcess(
            audioObjectID: 1,
            pid: 20,
            bundleID: "com.apple.Safari",
            appName: "Safari",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )
        let music = AudioProcess(
            audioObjectID: 2,
            pid: 10,
            bundleID: "com.apple.Music",
            appName: "Music",
            trackTitle: "Song",
            currentVolume: 55,
            volumeCapability: .scripted
        )
        let browser = AudioProcess(
            audioObjectID: 3,
            pid: 30,
            bundleID: "org.mozilla.firefox",
            appName: "Firefox",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )

        XCTAssertEqual(
            AudioProcess.sortedForDisplay([safari, music, browser]).map(\.appName),
            ["Music", "Firefox", "Safari"]
        )
    }

    func testVisibleUserSourcesExcludeCurrentAudioBarProcess() {
        let youtube = AudioProcess(
            audioObjectID: 1,
            pid: 100,
            bundleID: "com.apple.Safari.WebApp.abc",
            appName: "YouTube",
            trackTitle: "A Stream",
            currentVolume: 50,
            volumeCapability: .webAppKeyboard
        )
        let audioBar = AudioProcess(
            audioObjectID: 2,
            pid: 200,
            bundleID: "com.michaelvandijk.AudioBar",
            appName: "AudioBar",
            trackTitle: nil,
            currentVolume: nil,
            volumeCapability: .unavailable(reason: "No public per-app volume control")
        )

        XCTAssertEqual(
            AudioProcess.visibleUserSources([audioBar, youtube], currentPID: 200).map(\.appName),
            ["YouTube"]
        )
    }
}

import XCTest
@testable import AudioBarCore

final class AudioProcessListCacheTests: XCTestCase {
    func testCacheKeepsMissingPreviouslySeenSourceAsPaused() {
        var cache = AudioProcessListCache()
        let youtube = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
        )

        XCTAssertEqual(cache.merge(activeProcesses: [youtube]).map(\.displayTitle), ["YouTube"])

        let merged = cache.merge(activeProcesses: [])

        XCTAssertEqual(merged.map(\.displayTitle), ["YouTube"])
        XCTAssertEqual(merged.first?.displaySubtitle, "Paused")
        XCTAssertEqual(merged.first?.isActiveOutput, false)
    }

    func testCacheKeepsActiveSourcesBeforePausedSources() {
        var cache = AudioProcessListCache()
        let youtube = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
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

        _ = cache.merge(activeProcesses: [youtube])
        let merged = cache.merge(activeProcesses: [safari])

        XCTAssertEqual(merged.map(\.displayTitle), ["Safari", "YouTube"])
        XCTAssertEqual(merged.map(\.isActiveOutput), [true, false])
    }
}

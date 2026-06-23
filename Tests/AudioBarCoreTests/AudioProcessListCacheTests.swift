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

    func testCachePreservesCommittedWebAppVolumeAcrossRefreshes() {
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

        _ = cache.merge(activeProcesses: [youtube])
        cache.setCurrentVolume(37, forStableSourceID: youtube.stableSourceID)

        let refreshed = cache.merge(activeProcesses: [youtube])

        XCTAssertEqual(refreshed.first?.currentVolume, 37)
    }

    func testCacheLoadsPersistedVolumesForKnownSourceIDs() {
        var cache = AudioProcessListCache(persistedVolumes: [
            "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718": 24
        ])
        let youtube = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 100,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
        )

        let refreshed = cache.merge(activeProcesses: [youtube])

        XCTAssertEqual(refreshed.first?.currentVolume, 24)
    }

    func testCacheReturnsPersistedVolumeMapWhenVolumeChanges() {
        var cache = AudioProcessListCache(persistedVolumes: ["old": 10])
        let youtube = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 100,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
        )

        _ = cache.merge(activeProcesses: [youtube])
        cache.setCurrentVolume(37, forStableSourceID: youtube.stableSourceID)

        XCTAssertEqual(cache.persistedVolumes[youtube.stableSourceID], 37)
        XCTAssertEqual(cache.persistedVolumes["old"], 10)
    }

    func testCacheKeepsAnyPreviouslyAudibleAppSourceAsPausedUntilHidden() {
        var cache = AudioProcessListCache()
        let appCleaner = AudioProcess(
            audioObjectID: 99,
            pid: 456,
            bundleID: "net.freemacsoft.AppCleaner",
            appName: "AppCleaner",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .systemRoute
        )

        XCTAssertEqual(cache.merge(activeProcesses: [appCleaner]).map(\.displayTitle), ["AppCleaner"])

        let merged = cache.merge(activeProcesses: [])

        XCTAssertEqual(merged.map(\.displayTitle), ["AppCleaner"])
        XCTAssertEqual(merged.first?.displaySubtitle, "Paused")
        XCTAssertEqual(merged.first?.isActiveOutput, false)
    }

    func testRemoveEvictsPausedSourcePermanently() {
        var cache = AudioProcessListCache()
        let devSource = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
        )

        _ = cache.merge(activeProcesses: [devSource])
        cache.remove(stableSourceID: devSource.stableSourceID)

        // A dead source that won't return stays gone after removal.
        XCTAssertTrue(cache.merge(activeProcesses: []).isEmpty)
        XCTAssertNil(cache.persistedVolumes[devSource.stableSourceID])
    }

    func testRemovedSourceReappearsIfStillActive() {
        var cache = AudioProcessListCache()
        let liveSource = AudioProcess(
            audioObjectID: 12,
            pid: 345,
            bundleID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718",
            appName: "YouTube",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .webAppKeyboard,
            volumeControlID: "com.apple.Safari.WebApp.E95-B392-D57ECE8D1718"
        )

        _ = cache.merge(activeProcesses: [liveSource])
        cache.remove(stableSourceID: liveSource.stableSourceID)

        // A still-live source is re-discovered on the next refresh.
        XCTAssertEqual(cache.merge(activeProcesses: [liveSource]).map(\.displayTitle), ["YouTube"])
    }

    func testCacheKeepsSystemSoundsVisibleAfterNotificationAudioStops() {
        var cache = AudioProcessListCache()
        let systemSounds = AudioProcess(
            audioObjectID: 100,
            pid: 789,
            bundleID: "systemsoundserverd",
            appName: "systemsoundserverd",
            trackTitle: nil,
            currentVolume: 50,
            volumeCapability: .systemRoute
        )

        XCTAssertEqual(cache.merge(activeProcesses: [systemSounds]).map(\.displayTitle), ["System Sounds"])

        let merged = cache.merge(activeProcesses: [])

        XCTAssertEqual(merged.map(\.displayTitle), ["System Sounds"])
        XCTAssertEqual(merged.first?.displaySubtitle, "Paused")
    }
}

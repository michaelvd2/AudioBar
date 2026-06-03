import XCTest
@testable import AudioBarCore

final class AudioProcessResolverTests: XCTestCase {
    func testResolverAddsScriptedCapabilityAndKeepsMetadataForSupportedBundle() {
        let process = AudioProcessResolver.resolve(
            audioObjectID: 77,
            pid: 450,
            bundleID: "com.apple.Music",
            localizedAppName: "Music",
            trackTitle: "A Song",
            currentVolume: 64
        )

        XCTAssertEqual(process.appName, "Music")
        XCTAssertEqual(process.trackTitle, "A Song")
        XCTAssertEqual(process.currentVolume, 64)
        XCTAssertEqual(process.volumeCapability, .scripted)
    }

    func testResolverFallsBackToBundleIDWhenAppNameIsMissing() {
        let process = AudioProcessResolver.resolve(
            audioObjectID: 90,
            pid: 451,
            bundleID: "com.example.Player",
            localizedAppName: nil,
            trackTitle: nil,
            currentVolume: nil
        )

        XCTAssertEqual(process.appName, "com.example.Player")
        XCTAssertEqual(
            process.volumeCapability,
            .unavailable(reason: "No public per-app volume control")
        )
    }
}

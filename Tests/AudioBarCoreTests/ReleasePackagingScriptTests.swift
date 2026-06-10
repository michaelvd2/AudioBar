import Foundation
import XCTest

final class ReleasePackagingScriptTests: XCTestCase {
    func testReleasePackagingRequiresDeveloperIDAndNotarizationBeforeZip() throws {
        let source = try String(contentsOf: packageReleaseScriptURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("DEVELOPER_ID_APPLICATION"))
        XCTAssertTrue(source.contains("Developer ID Application"))
        XCTAssertTrue(source.contains("ENTITLEMENTS_PLIST"))
        XCTAssertTrue(source.contains("--entitlements"))
        XCTAssertTrue(source.contains("--options runtime"))
        XCTAssertTrue(source.contains("xcrun notarytool submit"))
        XCTAssertTrue(source.contains("xcrun stapler staple"))
        XCTAssertTrue(source.contains("spctl -a -vv"))
        XCTAssertTrue(source.contains("ditto -c -k --keepParent"))
        XCTAssertTrue(source.contains("AudioBar-notarized.zip"))
    }

    func testReleasePackagingIncludesSystemAudioPermissionAndRuntimeEntitlement() throws {
        let script = try String(contentsOf: packageReleaseScriptURL(), encoding: .utf8)
        let entitlements = try String(contentsOf: entitlementsURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("NSAudioCaptureUsageDescription"))
        XCTAssertTrue(script.contains("NSInputMonitoringUsageDescription"))
        XCTAssertTrue(script.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertTrue(entitlements.contains("<true/>"))
    }

    func testReleasePackagingCarriesCurrentBundleVersion() throws {
        let script = try String(contentsOf: packageReleaseScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("APP_VERSION=\"0.1.3\""))
        XCTAssertTrue(script.contains("BUILD_NUMBER=\"4\""))
        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("<string>$APP_VERSION</string>"))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("<string>$BUILD_NUMBER</string>"))
    }

    func testDownloadPageLinksToCurrentRelease() throws {
        let page = try String(contentsOf: docsIndexURL(), encoding: .utf8)

        XCTAssertTrue(page.contains("/releases/download/v0.1.3/AudioBar-notarized.zip"))
        XCTAssertFalse(page.contains("/releases/download/v0.1.2/AudioBar-notarized.zip"))
    }

    func testRunScriptIncludesGuidedPermissionUsageDescriptions() throws {
        let script = try String(contentsOf: buildRunScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("NSAudioCaptureUsageDescription"))
        XCTAssertTrue(script.contains("NSInputMonitoringUsageDescription"))
        XCTAssertTrue(script.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(script.contains("play/pause media key"))
    }

    private func packageReleaseScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/package_release.sh")
    }

    private func buildRunScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/build_and_run.sh")
    }

    private func docsIndexURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/index.html")
    }

    private func entitlementsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AudioBar.entitlements")
    }
}

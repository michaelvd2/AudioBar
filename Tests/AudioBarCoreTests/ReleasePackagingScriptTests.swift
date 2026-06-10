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
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertTrue(entitlements.contains("<true/>"))
    }

    private func packageReleaseScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/package_release.sh")
    }

    private func entitlementsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AudioBar.entitlements")
    }
}

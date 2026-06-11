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

        XCTAssertTrue(script.contains("APP_VERSION=\"0.1.7\""))
        XCTAssertTrue(script.contains("BUILD_NUMBER=\"8\""))
        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("<string>$APP_VERSION</string>"))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("<string>$BUILD_NUMBER</string>"))
    }

    func testDownloadPageLinksToCurrentRelease() throws {
        let page = try String(contentsOf: docsIndexURL(), encoding: .utf8)

        XCTAssertTrue(page.contains("/releases/download/v0.1.7/AudioBar-notarized.zip"))
        XCTAssertFalse(page.contains("/releases/download/v0.1.6/AudioBar-notarized.zip"))
    }

    func testRunScriptIncludesGuidedPermissionUsageDescriptions() throws {
        let script = try String(contentsOf: buildRunScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("NSAudioCaptureUsageDescription"))
        XCTAssertTrue(script.contains("NSInputMonitoringUsageDescription"))
        XCTAssertTrue(script.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(script.contains("play/pause media key"))
    }

    func testAppStorePackagingUsesSeparateSandboxedLane() throws {
        let script = try String(contentsOf: appStorePackageScriptURL(), encoding: .utf8)
        let entitlements = try String(contentsOf: appStoreEntitlementsURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("APP_STORE_APP_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("APP_STORE_INSTALLER_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("APP_STORE_PROVISIONING_PROFILE"))
        XCTAssertTrue(script.contains("Resources/AudioBar-AppStore.entitlements"))
        XCTAssertTrue(script.contains("--show-bin-path -Xswiftc -DAPP_STORE"))
        XCTAssertTrue(script.contains("productbuild"))
        XCTAssertTrue(script.contains("xcrun altool --validate-app"))
        XCTAssertFalse(script.contains("xcrun notarytool submit"))
        XCTAssertFalse(script.contains("xcrun stapler staple"))

        XCTAssertTrue(entitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertTrue(entitlements.contains("com.apple.security.automation.apple-events"))
        XCTAssertTrue(entitlements.contains("com.apple.security.temporary-exception.apple-events"))
        XCTAssertFalse(entitlements.contains("com.apple.systemevents"))
    }

    func testAppStorePackagingWritesSubmissionMetadata() throws {
        let script = try String(contentsOf: appStorePackageScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("APP_VERSION=\"${APP_VERSION:-0.1.7}\""))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("APP_BUILD=\"${APP_BUILD:-8}\""))
        XCTAssertTrue(script.contains("LSMinimumSystemVersion"))
        XCTAssertTrue(script.contains("MIN_SYSTEM_VERSION=\"14.2\""))
        XCTAssertTrue(script.contains("CFBundleDisplayName"))
        XCTAssertTrue(script.contains("CFBundleIconFile"))
        XCTAssertTrue(script.contains("docs/assets/audiobar-app-icon.png"))
        XCTAssertTrue(script.contains("AudioBar.icns"))
        XCTAssertTrue(script.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(script.contains("NSAudioCaptureUsageDescription"))
        XCTAssertTrue(script.contains("LSUIElement"))
    }

    func testAppStorePackagingDisablesBroadSystemEventsAutomation() throws {
        let script = try String(contentsOf: appStorePackageScriptURL(), encoding: .utf8)
        let source = try String(contentsOf: webAppKeyboardVolumeControllerURL(), encoding: .utf8)
        let playbackSource = try String(contentsOf: sourcePlaybackControllerURL(), encoding: .utf8)
        let webAppSource = try String(contentsOf: runningWebAppProviderURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("-DAPP_STORE"))
        XCTAssertTrue(source.contains("#if !APP_STORE"))
        XCTAssertTrue(source.contains("#if APP_STORE"))
        XCTAssertTrue(playbackSource.contains("#if APP_STORE"))
        XCTAssertTrue(webAppSource.contains("#if APP_STORE"))
        XCTAssertTrue(source.contains("return false"))
        XCTAssertTrue(playbackSource.contains("return false"))
        XCTAssertTrue(webAppSource.contains("return nil"))
    }

    func testPublicSubmissionPagesExistForAppStoreReview() throws {
        let privacy = try String(contentsOf: privacyPolicyURL(), encoding: .utf8)
        let support = try String(contentsOf: supportURL(), encoding: .utf8)
        let metadata = try String(contentsOf: appStoreSubmissionURL(), encoding: .utf8)
        let landingPage = try String(contentsOf: docsIndexURL(), encoding: .utf8)

        XCTAssertTrue(privacy.contains("AudioBar Privacy Policy"))
        XCTAssertTrue(privacy.contains("does not sell"))
        XCTAssertTrue(privacy.contains("does not record"))
        XCTAssertTrue(support.contains("AudioBar Support"))
        XCTAssertTrue(support.contains("System audio capture"))
        XCTAssertTrue(metadata.contains("App Review Notes"))
        XCTAssertTrue(metadata.contains("local-only"))
        XCTAssertTrue(landingPage.contains("support.html"))
        XCTAssertTrue(landingPage.contains("privacy.html"))
    }

    func testAppStorePreflightChecksAccountSideRequirements() throws {
        let script = try String(contentsOf: appStorePreflightScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("APP_STORE_PROVISIONING_PROFILE"))
        XCTAssertTrue(script.contains("APP_STORE_APP_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("APP_STORE_INSTALLER_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("APP_STORE_CONNECT_USERNAME"))
        XCTAssertTrue(script.contains("APP_STORE_CONNECT_PASSWORD"))
        XCTAssertTrue(script.contains("privacy.html"))
        XCTAssertTrue(script.contains("support.html"))
        XCTAssertTrue(script.contains("script/package_app_store.sh"))
        XCTAssertTrue(script.contains("xcrun altool --validate-app"))
    }

    func testLocalAppStoreSmokeScriptStagesSandboxedAppWithoutAccountCredentials() throws {
        let script = try String(contentsOf: localAppStoreSmokeScriptURL(), encoding: .utf8)

        XCTAssertTrue(script.contains("-DAPP_STORE"))
        XCTAssertTrue(script.contains("APP_VERSION=\"${APP_VERSION:-0.1.7}\""))
        XCTAssertTrue(script.contains("APP_BUILD=\"${APP_BUILD:-8}\""))
        XCTAssertTrue(script.contains("MIN_SYSTEM_VERSION=\"14.2\""))
        XCTAssertTrue(script.contains("Resources/AudioBar-AppStore.entitlements"))
        XCTAssertTrue(script.contains("docs/assets/audiobar-app-icon.png"))
        XCTAssertTrue(script.contains("codesign --force --sign -"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains("CFBundleIconFile"))
        XCTAssertTrue(script.contains("System Events|MediaRemote|MRMediaRemote|key code 49|key code 125|key code 126"))
        XCTAssertTrue(script.contains("launch"))
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

    private func appStorePackageScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/package_app_store.sh")
    }

    private func appStoreEntitlementsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AudioBar-AppStore.entitlements")
    }

    private func webAppKeyboardVolumeControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/WebAppKeyboardVolumeController.swift")
    }

    private func sourcePlaybackControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/SourcePlaybackController.swift")
    }

    private func runningWebAppProviderURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/RunningWebAppProvider.swift")
    }

    private func privacyPolicyURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/privacy.html")
    }

    private func supportURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/support.html")
    }

    private func appStoreSubmissionURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/app-store-submission.md")
    }

    private func appStorePreflightScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/preflight_app_store.sh")
    }

    private func localAppStoreSmokeScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/smoke_app_store_local.sh")
    }
}

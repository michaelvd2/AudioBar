import XCTest
@testable import AudioBarCore

final class WebKitMediaSourceResolverTests: XCTestCase {
    func testYouTubeGraphicsHelperResolvesToYouTubeWebAppSource() {
        let source = WebKitMediaSourceResolver.resolve(
            helperAudioObjectID: 44,
            helperPID: 83414,
            helperBundleID: "com.apple.WebKit.GPU",
            helperName: "YouTube Graphics and Media",
            webApps: [
                WebAppDescriptor(
                    bundleID: "com.apple.Safari.WebApp.abc",
                    displayName: "YouTube",
                    windowTitle: "Chris Liebing | Techno Live Set | SECTION. | May 2026 - YouTube"
                )
            ]
        )

        XCTAssertEqual(source?.bundleID, "com.apple.Safari.WebApp.abc")
        XCTAssertEqual(source?.appName, "YouTube")
        XCTAssertEqual(source?.trackTitle, "Chris Liebing | Techno Live Set | SECTION. | May 2026")
        XCTAssertEqual(source?.currentVolume, 50)
        XCTAssertEqual(source?.volumeCapability, .webAppKeyboard)
        XCTAssertEqual(source?.volumeControlID, "com.apple.Safari.WebApp.abc")
    }

    func testNonWebKitHelperDoesNotResolveAsWebAppSource() {
        let source = WebKitMediaSourceResolver.resolve(
            helperAudioObjectID: 44,
            helperPID: 83414,
            helperBundleID: "com.apple.Music",
            helperName: "Music",
            webApps: []
        )

        XCTAssertNil(source)
    }
}

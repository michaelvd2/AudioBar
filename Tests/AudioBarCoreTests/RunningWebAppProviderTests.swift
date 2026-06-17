import XCTest
@testable import AudioBarCore

final class RunningWebAppProviderTests: XCTestCase {
    func testDisplayNamePrefersInstalledWebAppBundleNameOverGenericProcessName() {
        let displayName = RunningWebAppProvider.displayName(
            localizedName: "Web App",
            bundleURL: URL(fileURLWithPath: "/Users/michaelvandijk/Applications/YouTube.app")
        )

        XCTAssertEqual(displayName, "YouTube")
    }

    func testDisplayNameFallsBackToLocalizedNameWhenBundleNameIsGeneric() {
        let displayName = RunningWebAppProvider.displayName(
            localizedName: "YouTube",
            bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Web App.app")
        )

        XCTAssertEqual(displayName, "YouTube")
    }
}

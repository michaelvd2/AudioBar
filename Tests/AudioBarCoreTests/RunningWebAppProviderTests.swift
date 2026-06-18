import CoreGraphics
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

    func testWindowTitleUsesVisibleWindowFallbackBeforeAppleScript() throws {
        let source = try String(contentsOf: runningWebAppProviderURL(), encoding: .utf8)
        let titleFunction = try XCTUnwrap(source.slice(
            from: "private func windowTitle(forPID pid: pid_t) -> String?",
            to: "private func accessibilityWindowTitle"
        ))
        let cgIndex = try XCTUnwrap(titleFunction.range(of: "cgWindowTitle(forPID: pid)")?.lowerBound)
        let scriptIndex = try XCTUnwrap(titleFunction.range(of: "appleScriptWindowTitle(forPID: pid)")?.lowerBound)

        XCTAssertLessThan(cgIndex, scriptIndex)
        XCTAssertTrue(source.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(source.contains("kCGWindowOwnerPID"))
        XCTAssertTrue(source.contains("kCGWindowName"))
    }

    func testAccessibilityTitleReaderRequestsTrustAtMostOnce() throws {
        let source = try String(contentsOf: runningWebAppProviderURL(), encoding: .utf8)
        let accessibilityReader = try XCTUnwrap(source.slice(
            from: "private func accessibilityWindowTitle(forPID pid: pid_t) -> String?",
            to: "private func cgWindowTitle"
        ))

        XCTAssertTrue(source.contains("private static let accessibilityPromptState = AccessibilityPromptState()"))
        XCTAssertTrue(accessibilityReader.contains("Self.isAccessibilityTrusted()"))
        XCTAssertTrue(source.contains("AXIsProcessTrustedWithOptions"))
        XCTAssertTrue(source.contains("Self.accessibilityPromptState.shouldRequestPrompt()"))
        XCTAssertTrue(source.contains("private final class AccessibilityPromptState: @unchecked Sendable"))
        XCTAssertTrue(source.contains("private var didRequest = false"))
    }

    func testVisibleWindowTitleUsesLayerZeroWindowForMatchingPID() {
        let title = RunningWebAppProvider.visibleWindowTitle(
            in: [
                [
                    kCGWindowOwnerPID as String: NSNumber(value: 123),
                    kCGWindowLayer as String: NSNumber(value: 1),
                    kCGWindowName as String: "Menu"
                ],
                [
                    kCGWindowOwnerPID as String: NSNumber(value: 456),
                    kCGWindowLayer as String: NSNumber(value: 0),
                    kCGWindowName as String: "Other Video - YouTube"
                ],
                [
                    kCGWindowOwnerPID as String: NSNumber(value: 123),
                    kCGWindowLayer as String: NSNumber(value: 0),
                    kCGWindowName as String: "Collabs 3000 [Speed] - YouTube"
                ]
            ],
            forPID: 123
        )

        XCTAssertEqual(title, "Collabs 3000 [Speed] - YouTube")
    }

    private func runningWebAppProviderURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBarCore/RunningWebAppProvider.swift")
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}

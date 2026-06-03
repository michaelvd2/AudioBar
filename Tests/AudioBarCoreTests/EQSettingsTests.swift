import XCTest
@testable import AudioBarCore

final class EQSettingsTests: XCTestCase {
    func testClassicBandsUseTenGraphicEQFrequencies() {
        XCTAssertEqual(
            EQBand.classic.map(\.frequencyHz),
            [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        )
        XCTAssertEqual(
            EQBand.classic.map(\.label),
            ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        )
    }

    func testSettingsClampBandGainToTwelveDbRange() {
        var settings = EQSettings.flat

        settings.setGain(18, for: 31)
        settings.setGain(-18, for: 16_000)

        XCTAssertEqual(settings.gain(for: 31), 12)
        XCTAssertEqual(settings.gain(for: 16_000), -12)
    }

    func testResetReturnsAllBandsAndPreampToFlat() {
        var settings = EQSettings.flat
        settings.preampDB = 5
        settings.setGain(6, for: 1_000)
        settings.isBypassed = true

        settings.reset()

        XCTAssertEqual(settings.preampDB, 0)
        XCTAssertEqual(settings.bandGainsDB.values.sorted(), Array(repeating: 0, count: 10))
        XCTAssertFalse(settings.isBypassed)
    }

    func testBassBoostPresetRaisesLowBandsAndCutsNothingAboveRange() {
        let settings = EQSettings.applying(.bassBoost)

        XCTAssertEqual(settings.gain(for: 31), 6)
        XCTAssertEqual(settings.gain(for: 62), 5)
        XCTAssertEqual(settings.gain(for: 125), 3)
        XCTAssertEqual(settings.gain(for: 16_000), 0)
    }
}

import XCTest
@testable import AudioBarCore

final class DefaultOutputBalanceControllerTests: XCTestCase {
    func testRightBalanceMutesLeftChannelAndKeepsRightChannelAtCurrentBaseVolume() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forBalance: 100,
            currentLeft: 0.43,
            currentRight: 0.43
        )

        XCTAssertEqual(volumes.left, 0, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0.43, accuracy: 0.0001)
    }

    func testLeftBalanceMutesRightChannelAndKeepsLeftChannelAtCurrentBaseVolume() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forBalance: -100,
            currentLeft: 0.43,
            currentRight: 0.43
        )

        XCTAssertEqual(volumes.left, 0.43, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0, accuracy: 0.0001)
    }

    func testCenterBalanceRestoresBothChannelsToTheLouderCurrentChannel() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forBalance: 0,
            currentLeft: 0,
            currentRight: 0.43
        )

        XCTAssertEqual(volumes.left, 0.43, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0.43, accuracy: 0.0001)
    }

    func testPartialRightBalanceDimsOnlyTheLeftChannel() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forBalance: 50,
            currentLeft: 0.8,
            currentRight: 0.8
        )

        XCTAssertEqual(volumes.left, 0.4, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0.8, accuracy: 0.0001)
    }

    func testOutputVolumeKeepsCenteredChannelsEqual() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forVolume: 37,
            balance: 0
        )

        XCTAssertEqual(volumes.left, 0.37, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0.37, accuracy: 0.0001)
    }

    func testOutputVolumePreservesRightOnlyBalance() {
        let volumes = DefaultOutputBalanceController.channelVolumes(
            forVolume: 37,
            balance: 100
        )

        XCTAssertEqual(volumes.left, 0, accuracy: 0.0001)
        XCTAssertEqual(volumes.right, 0.37, accuracy: 0.0001)
    }
}

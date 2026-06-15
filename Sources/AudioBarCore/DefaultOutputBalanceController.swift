import CoreAudio
import Foundation
import OSLog

private let defaultOutputBalanceLogger = Logger(
    subsystem: "com.michaelvandijk.AudioBar",
    category: "DefaultOutputBalance"
)

public final class DefaultOutputBalanceController: @unchecked Sendable {
    public init() {}

    @discardableResult
    public func apply(balance: Int) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else {
            defaultOutputBalanceLogger.error("Default output balance failed: output device unavailable")
            return false
        }
        guard canSetChannelVolume(deviceID: deviceID, channel: 1),
              canSetChannelVolume(deviceID: deviceID, channel: 2),
              let currentVolumes = readChannelVolumes(deviceID: deviceID)
        else {
            defaultOutputBalanceLogger.error("Default output balance failed: stereo channel volume unavailable")
            return false
        }

        let nextVolumes = Self.channelVolumes(
            forBalance: balance,
            currentLeft: currentVolumes.left,
            currentRight: currentVolumes.right
        )
        guard setChannelVolume(nextVolumes.left, deviceID: deviceID, channel: 1),
              setChannelVolume(nextVolumes.right, deviceID: deviceID, channel: 2)
        else {
            defaultOutputBalanceLogger.error("Default output balance failed: channel write failed")
            return false
        }
        defaultOutputBalanceLogger.info("Default output balance applied: \(balance)")
        return true
    }

    static func channelVolumes(
        forBalance balance: Int,
        currentLeft: Float32,
        currentRight: Float32
    ) -> (left: Float32, right: Float32) {
        let clampedBalance = max(-100, min(100, balance))
        let normalizedBalance = Float32(clampedBalance) / 100
        let baseVolume = max(clampVolume(currentLeft), clampVolume(currentRight))
        let leftGain = min(1, 1 - normalizedBalance)
        let rightGain = min(1, 1 + normalizedBalance)

        return (
            left: clampVolume(baseVolume * leftGain),
            right: clampVolume(baseVolume * rightGain)
        )
    }

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.stride)
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func readChannelVolumes(deviceID: AudioObjectID) -> (left: Float32, right: Float32)? {
        guard let left = readChannelVolume(deviceID: deviceID, channel: 1),
              let right = readChannelVolume(deviceID: deviceID, channel: 2)
        else {
            return nil
        }
        return (left, right)
    }

    private func readChannelVolume(deviceID: AudioObjectID, channel: UInt32) -> Float32? {
        var address = propertyAddress(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: channel
        )
        var dataSize = UInt32(MemoryLayout<Float32>.stride)
        var value: Float32 = 0
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? Self.clampVolume(value) : nil
    }

    private func canSetChannelVolume(deviceID: AudioObjectID, channel: UInt32) -> Bool {
        var address = propertyAddress(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func setChannelVolume(_ volume: Float32, deviceID: AudioObjectID, channel: UInt32) -> Bool {
        var address = propertyAddress(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: channel
        )
        var value = Self.clampVolume(volume)
        let dataSize = UInt32(MemoryLayout<Float32>.stride)
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            dataSize,
            &value
        )
        return status == noErr
    }

    private static func clampVolume(_ volume: Float32) -> Float32 {
        max(0, min(1, volume))
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
}

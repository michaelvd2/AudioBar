import CoreAudio
import Foundation

/// A selectable system audio device (output or input).
public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String

    public init(id: AudioDeviceID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public struct AudioOutputFormat: Equatable, Sendable {
    public let sampleRate: Double
    public let channels: Int

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public enum AudioDeviceScope {
    case output
    case input

    var coreAudioScope: AudioObjectPropertyScope {
        switch self {
        case .output: return kAudioDevicePropertyScopeOutput
        case .input: return kAudioDevicePropertyScopeInput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        case .input: return kAudioHardwarePropertyDefaultInputDevice
        }
    }
}

/// Enumerates audio devices and reads/sets the system default output/input
/// device using only public Core Audio APIs (App Store safe).
public enum AudioDeviceController {
    private static var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    /// Devices that expose at least one channel in the given scope, excluding
    /// AudioBar's own internal routing device.
    public static func devices(for scope: AudioDeviceScope) -> [AudioDevice] {
        allDeviceIDs().compactMap { id -> AudioDevice? in
            guard channelCount(of: id, scope: scope.coreAudioScope) > 0 else {
                return nil
            }
            guard let name = stringProperty(id, kAudioObjectPropertyName),
                  !name.localizedCaseInsensitiveContains("AudioBar")
            else {
                return nil
            }
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? ""
            return AudioDevice(id: id, uid: uid, name: name)
        }
    }

    /// The currently-present device matching a stable UID, if any.
    public static func device(withUID uid: String, for scope: AudioDeviceScope) -> AudioDevice? {
        devices(for: scope).first { $0.uid == uid }
    }

    /// Current operating format of the default output device. The sample rate +
    /// channel count reveal real fidelity (e.g. Bluetooth A2DP 48 kHz stereo vs
    /// the degraded ~16 kHz mono call/headset profile).
    public static func currentOutputFormat() -> AudioOutputFormat? {
        guard let id = defaultDeviceID(for: .output) else {
            return nil
        }
        let channels = channelCount(of: id, scope: kAudioDevicePropertyScopeOutput)
        guard let rate = nominalSampleRate(of: id), channels > 0 else {
            return nil
        }
        return AudioOutputFormat(sampleRate: rate, channels: channels)
    }

    private static func nominalSampleRate(of id: AudioDeviceID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        guard AudioObjectHasProperty(id, &addr) else {
            return nil
        }
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    public static func defaultDeviceID(for scope: AudioDeviceScope) -> AudioDeviceID? {
        var address = address(scope.defaultDeviceSelector)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutableBytes(of: &deviceID) {
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    public static func setDefaultDevice(_ id: AudioDeviceID, for scope: AudioDeviceScope) -> Bool {
        var address = address(scope.defaultDeviceSelector)
        var deviceID = id
        let status = AudioObjectSetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        return status == noErr
    }

    // MARK: - Helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer {
            AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    private static func channelCount(of id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        guard AudioObjectHasProperty(id, &addr) else {
            return nil
        }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard status == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}

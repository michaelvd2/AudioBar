import CoreAudio
import Foundation
import OSLog

private let systemEQLogger = Logger(
    subsystem: "com.michaelvandijk.AudioBar",
    category: "SystemEQ"
)

public enum SystemEQEngineStatus: Equatable, Sendable {
    case stopped
    case starting
    case probing
    case ready
    case active
    case failed(message: String)

    public var displayText: String {
        switch self {
        case .stopped:
            return "EQ stopped"
        case .starting:
            return "Starting EQ"
        case .probing:
            return "Checking system audio"
        case .ready:
            return "System tap ready"
        case .active:
            return "EQ active"
        case let .failed(message):
            return message
        }
    }

    public var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

public final class SystemEQEngine: @unchecked Sendable {
    public private(set) var status: SystemEQEngineStatus = .stopped

    private let lock = NSRecursiveLock()
    private let processor = EQProcessor(sampleRate: 48_000, channelCount: 2)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    public init() {}

    deinit {
        stop()
    }

    @discardableResult
    public func start(settings: EQSettings) -> SystemEQEngineStatus {
        lock.lock()
        defer { lock.unlock() }

        if status == .active {
            processor.update(settings: settings)
            return status
        }

        stopLocked(updateStatus: false)
        status = .starting
        systemEQLogger.info("Starting system EQ route")

        guard #available(macOS 14.2, *) else {
            return failLocked("Requires macOS 14.2+")
        }

        guard NSClassFromString("CATapDescription") != nil else {
            return failLocked("Audio tap unavailable")
        }

        let excludedProcesses = currentProcessObjectID().map { [$0] } ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.name = "AudioBar System EQ Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior(rawValue: 2) ?? tapDescription.muteBehavior

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var operationStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard operationStatus == noErr else {
            return failLocked("Tap failed (\(operationStatus))")
        }
        tapID = newTapID

        guard let tapUID = readString(objectID: tapID, selector: kAudioTapPropertyUID) else {
            return failLocked("Tap UID unavailable")
        }

        guard let outputDeviceID = defaultOutputDeviceID(),
              let outputDeviceUID = readString(objectID: outputDeviceID, selector: kAudioDevicePropertyDeviceUID)
        else {
            return failLocked("Output device unavailable")
        }

        guard let tapFormat = readStreamDescription(objectID: tapID, selector: kAudioTapPropertyFormat) else {
            return failLocked("Tap format unavailable")
        }

        guard isFloat32LinearPCM(tapFormat) else {
            return failLocked("Unsupported tap format \(formatSummary(tapFormat))")
        }

        processor.reset(
            sampleRate: tapFormat.mSampleRate,
            channelCount: Int(max(1, tapFormat.mChannelsPerFrame))
        )
        processor.update(settings: settings)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioBar System EQ",
            kAudioAggregateDeviceUIDKey: "com.michaelvandijk.AudioBar.SystemEQ.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        operationStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard operationStatus == noErr else {
            return failLocked("Route failed (\(operationStatus))")
        }
        aggregateID = newAggregateID

        var newIOProcID: AudioDeviceIOProcID?
        operationStatus = AudioDeviceCreateIOProcID(
            aggregateID,
            systemEQIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &newIOProcID
        )
        guard operationStatus == noErr, let newIOProcID else {
            return failLocked("IO setup failed (\(operationStatus))")
        }
        ioProcID = newIOProcID

        operationStatus = AudioDeviceStart(aggregateID, newIOProcID)
        guard operationStatus == noErr else {
            return failLocked("IO start failed (\(operationStatus))")
        }

        status = .active
        systemEQLogger.info("System EQ route active")
        return status
    }

    public func update(settings: EQSettings) {
        processor.update(settings: settings)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        stopLocked(updateStatus: true)
    }

    public func probe() -> SystemEQEngineStatus {
        guard #available(macOS 14.2, *) else {
            return .failed(message: "Requires macOS 14.2+")
        }

        guard NSClassFromString("CATapDescription") != nil else {
            return .failed(message: "Audio tap unavailable")
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "AudioBar EQ Probe"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 0) ?? description.muteBehavior

        var probeTapID = AudioObjectID(kAudioObjectUnknown)
        let createStatus = AudioHardwareCreateProcessTap(description, &probeTapID)
        guard createStatus == noErr else {
            return .failed(message: "Tap probe failed (\(createStatus))")
        }

        let destroyStatus = AudioHardwareDestroyProcessTap(probeTapID)
        guard destroyStatus == noErr else {
            return .failed(message: "Tap cleanup failed (\(destroyStatus))")
        }

        return .ready
    }

    fileprivate func process(
        inputData: UnsafePointer<AudioBufferList>?,
        outputData: UnsafeMutablePointer<AudioBufferList>?
    ) {
        guard let inputData, let outputData else {
            return
        }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)

        for outputIndex in 0..<outputBuffers.count {
            guard outputIndex < inputBuffers.count,
                  let inputPointer = inputBuffers[outputIndex].mData?.assumingMemoryBound(to: Float32.self),
                  let outputPointer = outputBuffers[outputIndex].mData?.assumingMemoryBound(to: Float32.self)
            else {
                if let outputData = outputBuffers[outputIndex].mData {
                    memset(outputData, 0, Int(outputBuffers[outputIndex].mDataByteSize))
                }
                continue
            }

            let channelCount = max(1, Int(inputBuffers[outputIndex].mNumberChannels))
            let byteCount = min(inputBuffers[outputIndex].mDataByteSize, outputBuffers[outputIndex].mDataByteSize)
            let frameCount = Int(byteCount) / (MemoryLayout<Float32>.stride * channelCount)

            processor.processInterleaved(
                input: inputPointer,
                output: outputPointer,
                frameCount: frameCount,
                channelCount: channelCount
            )
            outputBuffers[outputIndex].mDataByteSize = UInt32(
                frameCount * channelCount * MemoryLayout<Float32>.stride
            )
        }
    }

    private func failLocked(_ message: String) -> SystemEQEngineStatus {
        stopLocked(updateStatus: false)
        status = .failed(message: message)
        systemEQLogger.error("System EQ route failed: \(message, privacy: .public)")
        return status
    }

    private func stopLocked(updateStatus: Bool) {
        if let ioProcID {
            if aggregateID != kAudioObjectUnknown {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            self.ioProcID = nil
        }

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        if updateStatus {
            status = .stopped
        }
    }

    private func currentProcessObjectID() -> AudioObjectID? {
        var pid = getpid()
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.stride)
        var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.stride),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }
        return status == noErr && processObjectID != kAudioObjectUnknown ? processObjectID : nil
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

    private func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector)
        var dataSize = UInt32(MemoryLayout<CFString>.stride)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                valuePointer
            )
        }
        return status == noErr ? value as String : nil
    }

    private func readStreamDescription(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> AudioStreamBasicDescription? {
        var address = propertyAddress(selector)
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var value = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func isFloat32LinearPCM(_ description: AudioStreamBasicDescription) -> Bool {
        description.mFormatID == kAudioFormatLinearPCM
            && description.mBitsPerChannel == 32
            && (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    }

    private func formatSummary(_ description: AudioStreamBasicDescription) -> String {
        "format=\(description.mFormatID) flags=\(description.mFormatFlags) bits=\(description.mBitsPerChannel) channels=\(description.mChannelsPerFrame) rate=\(description.mSampleRate)"
    }
}

private let systemEQIOProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    guard let clientData else {
        return noErr
    }

    let engine = Unmanaged<SystemEQEngine>.fromOpaque(clientData).takeUnretainedValue()
    engine.process(inputData: inputData, outputData: outputData)
    return noErr
}

private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

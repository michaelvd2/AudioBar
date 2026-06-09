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
    private var tapIDs: [AudioObjectID] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var currentStreamSnapshot = SystemAudioStreamSnapshot.inactive
    private var sourceProcessObjectIDs: [AudioObjectID] = []
    private var sourceVolumeByProcessObjectID: [AudioObjectID: Float32] = [:]
    private var inputBufferProcessObjectIDs: [AudioObjectID?] = [nil]

    public init() {}

    deinit {
        stop()
    }

    public var streamSnapshot: SystemAudioStreamSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return currentStreamSnapshot
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

        var excludedProcesses = currentProcessObjectID().map { [$0] } ?? []
        excludedProcesses.append(contentsOf: sourceProcessObjectIDs)
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.name = "AudioBar System EQ Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior(rawValue: 2) ?? tapDescription.muteBehavior

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var operationStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard operationStatus == noErr else {
            return failLocked("Tap failed (\(operationStatus))")
        }
        tapIDs = [newTapID]
        inputBufferProcessObjectIDs = [nil]

        for processObjectID in sourceProcessObjectIDs {
            let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
            tapDescription.name = "AudioBar Source \(processObjectID) Tap"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = CATapMuteBehavior(rawValue: 2) ?? tapDescription.muteBehavior

            var sourceTapID = AudioObjectID(kAudioObjectUnknown)
            operationStatus = AudioHardwareCreateProcessTap(tapDescription, &sourceTapID)
            guard operationStatus == noErr else {
                return failLocked("Source tap failed (\(operationStatus))")
            }
            tapIDs.append(sourceTapID)
            inputBufferProcessObjectIDs.append(processObjectID)
        }

        let tapUIDs = tapIDs.compactMap {
            readString(objectID: $0, selector: kAudioTapPropertyUID)
        }
        guard tapUIDs.count == tapIDs.count else {
            return failLocked("Tap UID unavailable")
        }

        guard let outputDeviceID = defaultOutputDeviceID(),
              let outputDeviceUID = readString(objectID: outputDeviceID, selector: kAudioDevicePropertyDeviceUID)
        else {
            return failLocked("Output device unavailable")
        }

        guard let tapFormat = readStreamDescription(objectID: tapIDs[0], selector: kAudioTapPropertyFormat) else {
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
        currentStreamSnapshot = .active(
            sampleRate: tapFormat.mSampleRate,
            channelCount: Int(max(1, tapFormat.mChannelsPerFrame))
        )

        let aggregateDescription = SystemEQRouteDescription.makeAggregate(
            aggregateUID: "com.michaelvandijk.AudioBar.SystemEQ.\(UUID().uuidString)",
            outputDeviceUID: outputDeviceUID,
            tapUIDs: tapUIDs
        )

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
        systemEQLogger.info("System EQ route active; output-clocked with zero extra latency")
        return status
    }

    public func update(settings: EQSettings) {
        processor.update(settings: settings)
    }

    public func setSourceProcesses(_ processes: [AudioProcess]) {
        lock.lock()
        defer { lock.unlock() }

        let nextIDs = processes
            .filter(\.isActiveOutput)
            .map(\.audioObjectID)
            .filter { $0 != kAudioObjectUnknown }

        guard nextIDs != sourceProcessObjectIDs else {
            return
        }

        sourceProcessObjectIDs = nextIDs
        if status == .active {
            let settings = processor.currentSettings
            stopLocked(updateStatus: false)
            _ = start(settings: settings)
        }
    }

    public func setSourceVolume(_ volume: Int, for processObjectID: UInt32) {
        lock.lock()
        defer { lock.unlock() }

        sourceVolumeByProcessObjectID[AudioObjectID(processObjectID)] = Float32(min(100, max(0, volume))) / 100
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
            let sampleCount = frameCount * channelCount
            let inputLevelDB = levelDB(samples: inputPointer, count: sampleCount)

            processor.processInterleaved(
                input: inputPointer,
                output: outputPointer,
                frameCount: frameCount,
                channelCount: channelCount
            )
            let gain = gainForInputBuffer(outputIndex)
            if gain != 1 {
                for sampleIndex in 0..<sampleCount {
                    outputPointer[sampleIndex] *= gain
                }
            }
            let outputLevelDB = levelDB(samples: outputPointer, count: sampleCount)
            updateStreamLevels(inputLevelDB: inputLevelDB, outputLevelDB: outputLevelDB)
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

        if #available(macOS 14.2, *) {
            for tapID in tapIDs where tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
        tapIDs = []
        inputBufferProcessObjectIDs = [nil]

        if updateStatus {
            status = .stopped
        }
        currentStreamSnapshot = .inactive
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

    private func levelDB(samples: UnsafePointer<Float32>, count: Int) -> Double {
        guard count > 0 else {
            return -120
        }

        var sum = 0.0
        for index in 0..<count {
            let sample = Double(samples[index])
            sum += sample * sample
        }

        let rms = sqrt(sum / Double(count))
        guard rms > 0 else {
            return -120
        }
        return max(-120, min(0, 20 * log10(rms)))
    }

    private func updateStreamLevels(inputLevelDB: Double, outputLevelDB: Double) {
        guard lock.try() else {
            return
        }
        defer { lock.unlock() }

        guard currentStreamSnapshot.isActive else {
            return
        }

        currentStreamSnapshot = .active(
            sampleRate: currentStreamSnapshot.sampleRate,
            channelCount: currentStreamSnapshot.channelCount,
            inputLevelDB: inputLevelDB,
            outputLevelDB: outputLevelDB
        )
    }

    private func gainForInputBuffer(_ index: Int) -> Float32 {
        guard index < inputBufferProcessObjectIDs.count,
              let processObjectID = inputBufferProcessObjectIDs[index]
        else {
            return 1
        }
        return sourceVolumeByProcessObjectID[processObjectID] ?? 1
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

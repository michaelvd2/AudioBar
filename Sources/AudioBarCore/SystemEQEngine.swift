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
    private var availableSourceProcessObjectIDs: [AudioObjectID] = []
    private var sourceProcessObjectIDs: [AudioObjectID] = []
    private var sourceVolumeByProcessObjectID: [AudioObjectID: Float32] = [:]
    private var sourceBalanceByProcessObjectID: [AudioObjectID: Float32] = [:]
    private var sourceMonoByProcessObjectID: Set<AudioObjectID> = []
    private var inputBufferProcessObjectIDs: [AudioObjectID?] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var currentStreamSnapshot = SystemAudioStreamSnapshot.inactive
    private var didLogIOBufferLayout = false
    private var defaultOutputDeviceChangeToken: AudioObjectPropertyListenerBlock?

    public init() {
        registerDefaultOutputDeviceListener()
    }

    deinit {
        unregisterDefaultOutputDeviceListener()
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

        guard let outputDeviceID = defaultOutputDeviceID(),
              let outputDeviceUID = readString(objectID: outputDeviceID, selector: kAudioDevicePropertyDeviceUID)
        else {
            return failLocked("Output device unavailable")
        }

        let muteBehavior = tapMuteBehavior(forOutputDeviceID: outputDeviceID)
        var processObjectIDsForInputBuffers: [AudioObjectID?] = []
        let excludedProcesses = Array(Set((currentProcessObjectID().map { [$0] } ?? []) + sourceProcessObjectIDs))
        let fallbackTapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        fallbackTapDescription.name = "AudioBar System EQ Fallback Tap"
        fallbackTapDescription.isPrivate = true
        fallbackTapDescription.muteBehavior = muteBehavior

        guard let fallbackTapID = createProcessTap(fallbackTapDescription) else {
            return failLocked("Fallback tap failed")
        }
        tapIDs.append(fallbackTapID)
        processObjectIDsForInputBuffers.append(nil)

        for processObjectID in sourceProcessObjectIDs {
            let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
            tapDescription.name = "AudioBar Source Tap \(processObjectID)"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = muteBehavior

            guard let sourceTapID = createProcessTap(tapDescription) else {
                return failLocked("Source tap failed (\(processObjectID))")
            }
            tapIDs.append(sourceTapID)
            processObjectIDsForInputBuffers.append(processObjectID)
        }

        let tapUIDs = tapIDs.compactMap { readString(objectID: $0, selector: kAudioTapPropertyUID) }
        guard tapUIDs.count == tapIDs.count else {
            return failLocked("Tap UID unavailable")
        }
        inputBufferProcessObjectIDs = processObjectIDsForInputBuffers

        guard let firstTapID = tapIDs.first,
              let tapFormat = readStreamDescription(objectID: firstTapID, selector: kAudioTapPropertyFormat)
        else {
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
        var operationStatus = AudioHardwareCreateAggregateDevice(
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
        systemEQLogger.info("System EQ route active; outputDevice=\(outputDeviceUID, privacy: .public) tapCount=\(tapUIDs.count) tapFormat=\(self.formatSummary(tapFormat), privacy: .public)")
        return status
    }

    public func update(settings: EQSettings) {
        processor.update(settings: settings)
    }

    public func setSourceProcesses(_ processes: [AudioProcess]) {
        lock.lock()
        defer { lock.unlock() }

        let nextAvailableIDs = Array(Set(processes
            .filter { $0.isActiveOutput || $0.shouldRemainVisibleWhenPaused }
            .map { AudioObjectID($0.audioObjectID) }
            .filter { $0 != kAudioObjectUnknown }
        )).sorted()

        availableSourceProcessObjectIDs = nextAvailableIDs
        sourceVolumeByProcessObjectID = sourceVolumeByProcessObjectID.filter { nextAvailableIDs.contains($0.key) }
        sourceBalanceByProcessObjectID = sourceBalanceByProcessObjectID.filter { nextAvailableIDs.contains($0.key) }
        sourceMonoByProcessObjectID = Set(sourceMonoByProcessObjectID.filter { nextAvailableIDs.contains($0) })
        updateDedicatedSourceProcessesLocked()
    }

    public func setSourceVolume(_ volume: Int, for processObjectID: AudioObjectID) {
        lock.lock()
        defer { lock.unlock() }

        let clamped = max(0, min(100, volume))
        if clamped >= 99 {
            sourceVolumeByProcessObjectID.removeValue(forKey: processObjectID)
        } else {
            sourceVolumeByProcessObjectID[processObjectID] = Float32(clamped) / 100
        }
        updateDedicatedSourceProcessesLocked()
    }

    public func setSourceBalance(_ balance: Int, for processObjectID: UInt32) {
        lock.lock()
        defer { lock.unlock() }

        let clamped = max(-100, min(100, balance))
        let processObjectID = AudioObjectID(processObjectID)
        if abs(clamped) <= 8 {
            sourceBalanceByProcessObjectID.removeValue(forKey: processObjectID)
        } else {
            sourceBalanceByProcessObjectID[processObjectID] = Float32(clamped) / 100
        }
        updateDedicatedSourceProcessesLocked()
    }

    public func setSourceMono(_ isMono: Bool, for processObjectID: UInt32) {
        lock.lock()
        defer { lock.unlock() }

        let processObjectID = AudioObjectID(processObjectID)
        if isMono {
            sourceMonoByProcessObjectID.insert(processObjectID)
        } else {
            sourceMonoByProcessObjectID.remove(processObjectID)
        }
        updateDedicatedSourceProcessesLocked()
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
        logIOBufferLayoutOnce(inputBuffers: inputBuffers, outputBuffers: outputBuffers)

        let outputChannelCount = renderedOutputChannelCount(outputBuffers: outputBuffers)
        let frameCount = renderedFrameCount(outputBuffers: outputBuffers, channelCount: outputChannelCount)
        guard frameCount > 0 else {
            clearOutputBuffers(outputBuffers)
            return
        }

        var sources: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int, gain: Float32, balance: Float32, isMono: Bool)] = []
        for inputIndex in 0..<inputBuffers.count {
            guard let inputPointer = inputBuffers[inputIndex].mData?.assumingMemoryBound(to: Float32.self) else {
                continue
            }
            let inputChannelCount = max(1, Int(inputBuffers[inputIndex].mNumberChannels))
            let inputSampleCount = Int(inputBuffers[inputIndex].mDataByteSize) / MemoryLayout<Float32>.stride
            let inputFrameCount = inputSampleCount / inputChannelCount
            guard inputFrameCount > 0 else {
                continue
            }
            let controls = controlsForInputBuffer(at: inputIndex, inputBufferCount: inputBuffers.count)
            sources.append((
                pointer: UnsafePointer(inputPointer),
                frameCount: inputFrameCount,
                channelCount: inputChannelCount,
                gain: controls.gain,
                balance: controls.balance,
                isMono: controls.isMono
            ))
        }

        let sampleCount = frameCount * outputChannelCount
        withUnsafeTemporaryAllocation(of: Float32.self, capacity: sampleCount) { mixedBuffer in
            withUnsafeTemporaryAllocation(of: Float32.self, capacity: sampleCount) { processedBuffer in
                guard let mixedBase = mixedBuffer.baseAddress,
                      let processedBase = processedBuffer.baseAddress
                else {
                    return
                }
                AudioSourceMixer.mixInterleaved(
                    sources: sources,
                    output: mixedBase,
                    frameCount: frameCount,
                    channelCount: outputChannelCount
                )
                let inputLevelDB = levelDB(samples: mixedBase, count: sampleCount)

                processor.processInterleaved(
                    input: mixedBase,
                    output: processedBase,
                    frameCount: frameCount,
                    channelCount: outputChannelCount
                )
                writeInterleaved(processedBase, frameCount: frameCount, channelCount: outputChannelCount, to: outputBuffers)
                let outputLevelDB = levelDB(samples: processedBase, count: sampleCount)
                updateStreamLevels(inputLevelDB: inputLevelDB, outputLevelDB: outputLevelDB)
            }
        }
    }

    private func renderedOutputChannelCount(outputBuffers: UnsafeMutableAudioBufferListPointer) -> Int {
        guard outputBuffers.count > 0 else {
            return 1
        }

        if outputBuffers.count == 1 {
            return max(1, Int(outputBuffers[0].mNumberChannels))
        }

        let totalChannels = outputBuffers.reduce(0) { $0 + max(1, Int($1.mNumberChannels)) }
        return max(1, totalChannels)
    }

    private func renderedFrameCount(
        outputBuffers: UnsafeMutableAudioBufferListPointer,
        channelCount: Int
    ) -> Int {
        guard outputBuffers.count > 0 else {
            return 0
        }

        if outputBuffers.count == 1 {
            let outputChannelCount = max(1, Int(outputBuffers[0].mNumberChannels))
            return Int(outputBuffers[0].mDataByteSize) / (MemoryLayout<Float32>.stride * outputChannelCount)
        }

        return outputBuffers.map { buffer in
            Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.stride * max(1, Int(buffer.mNumberChannels)))
        }.min() ?? 0
    }

    private func clearOutputBuffers(_ outputBuffers: UnsafeMutableAudioBufferListPointer) {
        for outputIndex in 0..<outputBuffers.count {
            if let outputData = outputBuffers[outputIndex].mData {
                memset(outputData, 0, Int(outputBuffers[outputIndex].mDataByteSize))
            }
            outputBuffers[outputIndex].mDataByteSize = 0
        }
    }

    private func writeInterleaved(
        _ source: UnsafePointer<Float32>,
        frameCount: Int,
        channelCount: Int,
        to outputBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        let channelCount = max(1, channelCount)
        guard frameCount > 0 else {
            clearOutputBuffers(outputBuffers)
            return
        }

        if outputBuffers.count == 1 {
            let outputChannelCount = max(1, Int(outputBuffers[0].mNumberChannels))
            let outputFrameCount = min(
                frameCount,
                Int(outputBuffers[0].mDataByteSize) / (MemoryLayout<Float32>.stride * outputChannelCount)
            )
            if let outputPointer = outputBuffers[0].mData?.assumingMemoryBound(to: Float32.self) {
                for frame in 0..<outputFrameCount {
                    for outputChannel in 0..<outputChannelCount {
                        let sourceChannel = min(outputChannel, channelCount - 1)
                        outputPointer[frame * outputChannelCount + outputChannel] = source[frame * channelCount + sourceChannel]
                    }
                }
                outputBuffers[0].mDataByteSize = UInt32(
                    outputFrameCount * outputChannelCount * MemoryLayout<Float32>.stride
                )
            }
            return
        }

        var outputChannelOffset = 0
        for outputIndex in 0..<outputBuffers.count {
            let outputChannelCount = max(1, Int(outputBuffers[outputIndex].mNumberChannels))
            let outputFrameCount = min(
                frameCount,
                Int(outputBuffers[outputIndex].mDataByteSize) / (MemoryLayout<Float32>.stride * outputChannelCount)
            )

            guard let outputPointer = outputBuffers[outputIndex].mData?.assumingMemoryBound(to: Float32.self) else {
                outputChannelOffset += outputChannelCount
                continue
            }

            for frame in 0..<outputFrameCount {
                for localChannel in 0..<outputChannelCount {
                    let sourceChannel = min(outputChannelOffset + localChannel, channelCount - 1)
                    outputPointer[frame * outputChannelCount + localChannel] = source[frame * channelCount + sourceChannel]
                }
            }
            outputBuffers[outputIndex].mDataByteSize = UInt32(
                outputFrameCount * outputChannelCount * MemoryLayout<Float32>.stride
            )
            outputChannelOffset += outputChannelCount
        }
    }

    private func logIOBufferLayoutOnce(
        inputBuffers: UnsafeMutableAudioBufferListPointer,
        outputBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        guard lock.try() else {
            return
        }
        defer { lock.unlock() }

        guard !didLogIOBufferLayout else {
            return
        }
        didLogIOBufferLayout = true

        let inputLayout = (0..<inputBuffers.count)
            .map { "\(inputBuffers[$0].mNumberChannels)ch/\(inputBuffers[$0].mDataByteSize)b" }
            .joined(separator: ",")
        let outputLayout = (0..<outputBuffers.count)
            .map { "\(outputBuffers[$0].mNumberChannels)ch/\(outputBuffers[$0].mDataByteSize)b" }
            .joined(separator: ",")

        systemEQLogger.info("System EQ IO layout input=[\(inputLayout, privacy: .public)] output=[\(outputLayout, privacy: .public)]")
    }

    private func controlsForInputBuffer(at inputIndex: Int, inputBufferCount: Int) -> (gain: Float32, balance: Float32, isMono: Bool) {
        guard lock.try() else {
            return (1, 0, false)
        }
        defer { lock.unlock() }

        guard let processObjectID = SystemEQInputBufferMap.processObjectID(
            inputIndex: inputIndex,
            inputBufferCount: inputBufferCount,
            tapProcessObjectIDs: inputBufferProcessObjectIDs
        )
        else {
            return (1, 0, false)
        }
        return (
            sourceVolumeByProcessObjectID[processObjectID] ?? 1,
            sourceBalanceByProcessObjectID[processObjectID] ?? 0,
            sourceMonoByProcessObjectID.contains(processObjectID)
        )
    }

    private func updateDedicatedSourceProcessesLocked() {
        let nextIDs = availableSourceProcessObjectIDs.filter { sourceNeedsDedicatedTap($0) }
        guard nextIDs != sourceProcessObjectIDs else {
            return
        }

        sourceProcessObjectIDs = nextIDs
        if status == .active {
            let settings = processor.currentSettings
            _ = restartLocked(settings: settings)
        }
    }

    private func sourceNeedsDedicatedTap(_ processObjectID: AudioObjectID) -> Bool {
        if let volume = sourceVolumeByProcessObjectID[processObjectID], volume < 0.99 {
            return true
        }
        if let balance = sourceBalanceByProcessObjectID[processObjectID], abs(balance) > 0.08 {
            return true
        }
        return sourceMonoByProcessObjectID.contains(processObjectID)
    }

    private func tapMuteBehavior(forOutputDeviceID outputDeviceID: AudioObjectID) -> CATapMuteBehavior {
        let transportType = readUInt32(objectID: outputDeviceID, selector: kAudioDevicePropertyTransportType)
        if transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE {
            systemEQLogger.info("Bluetooth output detected; leaving tapped hardware playback unmuted")
            return CATapMuteBehavior(rawValue: 0) ?? CATapMuteBehavior(rawValue: 2)!
        }
        return CATapMuteBehavior(rawValue: 2) ?? CATapMuteBehavior(rawValue: 0)!
    }

    @available(macOS 14.2, *)
    private func createProcessTap(_ tapDescription: CATapDescription) -> AudioObjectID? {
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let operationStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard operationStatus == noErr else {
            systemEQLogger.error("Process tap failed: \(operationStatus)")
            return nil
        }
        return newTapID
    }

    private func restartLocked(settings: EQSettings) -> SystemEQEngineStatus {
        stopLocked(updateStatus: false)
        status = .stopped
        return start(settings: settings)
    }

    private func restartAfterDefaultOutputDeviceChange() {
        lock.lock()
        defer { lock.unlock() }

        guard status == .active else {
            return
        }

        let settings = processor.currentSettings
        systemEQLogger.info("Default output device changed; restarting system EQ route")
        _ = restartLocked(settings: settings)
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
        inputBufferProcessObjectIDs = []
        didLogIOBufferLayout = false

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

    private func registerDefaultOutputDeviceListener() {
        guard defaultOutputDeviceChangeToken == nil else {
            return
        }

        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let token: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartAfterDefaultOutputDeviceChange()
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            token
        )

        guard status == noErr else {
            systemEQLogger.error("Default output listener failed: \(status)")
            return
        }
        defaultOutputDeviceChangeToken = token
    }

    private func unregisterDefaultOutputDeviceListener() {
        guard let defaultOutputDeviceChangeToken else {
            return
        }

        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultOutputDeviceChangeToken
        )
        self.defaultOutputDeviceChangeToken = nil
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

    private func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = propertyAddress(selector)
        var dataSize = UInt32(MemoryLayout<UInt32>.stride)
        var value: UInt32 = 0
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

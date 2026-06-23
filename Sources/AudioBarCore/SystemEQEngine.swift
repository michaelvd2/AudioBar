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
    case unavailable(message: String)
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
        case let .unavailable(message):
            return message
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

    public var isUnavailable: Bool {
        if case .unavailable = self {
            return true
        }
        return false
    }
}

/// Test seam for route activation.
///
/// Production leaves the engine's activator nil, so `start()` builds the real
/// CoreAudio aggregate-device + process-tap route. Tests inject a fake instead,
/// so route engagement is deterministic and never creates — or mutes — real
/// system audio. The behavior under test is the engine's *decision* logic (when
/// to engage, when to rebuild), not CoreAudio plumbing the host may or may not
/// be able (or permitted) to perform.
protocol SystemEQRouteActivating: AnyObject {
    /// Produce the status the engine should adopt for a requested activation.
    /// Implementations may read engine state but must not assume any real
    /// CoreAudio objects were created.
    func activateRoute(for engine: SystemEQEngine, settings: EQSettings) -> SystemEQEngineStatus
}

public final class SystemEQEngine: @unchecked Sendable {
    private static let ioSetupRetryCount = 2
    private static let ioSetupRetryDelaySeconds = 0.08
    /// Target IO buffer for the EQ aggregate — small enough to keep A/V lip-sync
    /// drift below the perceptual threshold, large enough to avoid dropouts.
    /// Raised 256 → 512 after constant playback breakup: 256 left no headroom for
    /// CPU bursts (the IOProc would miss its deadline → xruns/crackle). 512 (~11ms
    /// at 48k) restores margin; the extra latency is well under the sync threshold.
    private static let targetBufferFrameSize: UInt32 = 512

    public private(set) var status: SystemEQEngineStatus = .stopped

    /// Test seam — see `SystemEQRouteActivating`. Nil in production, so `start()`
    /// builds the real CoreAudio route; tests assign a fake to make activation
    /// deterministic without creating or muting real system audio.
    var routeActivatorForTesting: SystemEQRouteActivating?

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

    // Liveness watchdog. The global tap mutes the system's real audio and relies
    // on our IOProc to play the replacement back. If the IOProc dies (e.g. a
    // default-output-device change leaves the aggregate broken), the route still
    // reports `.active`, so the whole system stays silent until relaunch. We
    // stamp every IOProc callback; if callbacks stop arriving while we claim to
    // be active, we tear the route down (which un-mutes the system) and rebuild.
    private static let stallThresholdSeconds = 1.0
    private static let maxStallRecoveryAttempts = 3
    private static let stallBackoffResetSeconds = 5.0
    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private var lastIOProcMachTime: UInt64 = 0
    private var lastStallRestartMachTime: UInt64 = 0
    private var stallRecoveryAttempts = 0

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

        // Test seam: when a fake activator is injected, adopt its verdict instead
        // of touching real CoreAudio. Nil in production — the real route below
        // runs unchanged. Reached only after the `.active` short-circuit above, so
        // a redundant `start()` on an already-active route still no-ops (the fake
        // sees no spurious activation), exactly as the real route does.
        if let routeActivatorForTesting {
            let resolved = routeActivatorForTesting.activateRoute(for: self, settings: settings)
            status = resolved
            return resolved
        }

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

        updateDedicatedSourceProcessesLocked()

        guard hasActiveProcessing(settings) else {
            // Nothing to process: don't install the global muting tap at all, so
            // the system's audio path is entirely untouched. The route is built
            // on demand the moment EQ or a per-source control becomes active.
            currentStreamSnapshot = .inactive
            status = .stopped
            systemEQLogger.info("System EQ idle — flat/bypassed, no source adjustments; not intercepting system audio")
            return status
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
        systemEQLogger.info("System EQ settings applied: \(self.settingsSummary(settings), privacy: .public)")
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

        let ioSetup = createIOProcIDWithRetry(for: aggregateID)
        operationStatus = ioSetup.status
        let newIOProcID = ioSetup.ioProcID
        guard operationStatus == noErr, let newIOProcID else {
            return failLocked("IO setup failed (\(operationStatus))")
        }
        ioProcID = newIOProcID

        // Shrink the IO buffer before starting, to cut the capture→re-play delay
        // that shows up as A/V lip-sync drift when EQ is on (the player can't see
        // this added latency). No-op if the device won't go below its current size.
        applyLowLatencyBufferLocked(to: aggregateID)

        operationStatus = AudioDeviceStart(aggregateID, newIOProcID)
        guard operationStatus == noErr else {
            return failLocked("IO start failed (\(operationStatus))")
        }

        // Seed liveness so the watchdog doesn't fire before the first callback.
        lastIOProcMachTime = mach_absolute_time()
        status = .active
        systemEQLogger.info("System EQ route active; outputDevice=\(outputDeviceUID, privacy: .public) tapCount=\(tapUIDs.count) tapFormat=\(self.formatSummary(tapFormat), privacy: .public)")
        return status
    }

    public func update(settings: EQSettings) {
        lock.lock()
        defer { lock.unlock() }

        processor.update(settings: settings)

        // Engage or release the route as the need for processing changes — so
        // turning EQ off (or flattening it) tears the muting tap down and hands
        // audio straight back to the system, and turning it on rebuilds it.
        if hasActiveProcessing(settings) {
            if status != .active, status != .starting {
                _ = start(settings: settings)
                return
            }
        } else if status == .active {
            stopLocked(updateStatus: true)
        }

        systemEQLogger.info("System EQ settings updated: \(self.settingsSummary(settings), privacy: .public)")
    }

    public func setSourceProcesses(_ processes: [AudioProcess]) {
        lock.lock()
        defer { lock.unlock() }

        let nextAvailableIDs = Array(Set(processes
            .filter(\.isActiveOutput)
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
        // Liveness heartbeat for the watchdog (plain 64-bit store; the benign
        // race with the reader is fine for a coarse staleness check).
        lastIOProcMachTime = mach_absolute_time()
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
            _ = restartLocked(settings: processor.currentSettings)
        } else if status == .stopped, !nextIDs.isEmpty {
            // A source now needs per-app processing while we were idle — engage.
            // (Guarded to `.stopped` so this never re-enters during start()'s own
            // setup, where status is `.starting`.)
            _ = start(settings: processor.currentSettings)
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

    /// True when the route actually has work to do — EQ is shaping audio, or a
    /// source needs per-app volume/balance/mono. When false, we leave the system
    /// audio completely untouched (no tap, no muting), so AudioBar can't affect
    /// or silence playback at all unless you're genuinely using it.
    private func hasActiveProcessing(_ settings: EQSettings) -> Bool {
        if !sourceProcessObjectIDs.isEmpty {
            return true
        }
        guard !settings.isBypassed else {
            return false
        }
        if abs(settings.preampDB) > 0.01 {
            return true
        }
        return settings.bandGainsDB.values.contains { abs($0) > 0.01 }
    }

    private func tapMuteBehavior(forOutputDeviceID outputDeviceID: AudioObjectID) -> CATapMuteBehavior {
        if isBluetoothOutputDevice(outputDeviceID) {
            systemEQLogger.info("Bluetooth output detected; using muted replacement route")
        }
        return CATapMuteBehavior(rawValue: 2) ?? CATapMuteBehavior(rawValue: 1)!
    }

    private func createIOProcIDWithRetry(
        for aggregateID: AudioObjectID
    ) -> (status: OSStatus, ioProcID: AudioDeviceIOProcID?) {
        var lastStatus: OSStatus = noErr

        for attempt in 0...Self.ioSetupRetryCount {
            var newIOProcID: AudioDeviceIOProcID?
            lastStatus = AudioDeviceCreateIOProcID(
                aggregateID,
                systemEQIOProc,
                Unmanaged.passUnretained(self).toOpaque(),
                &newIOProcID
            )
            if lastStatus == noErr, let newIOProcID {
                return (lastStatus, newIOProcID)
            }

            guard attempt < Self.ioSetupRetryCount else {
                break
            }
            systemEQLogger.info("System EQ IO setup retry \(attempt + 1, privacy: .public) after status \(lastStatus, privacy: .public)")
            Thread.sleep(forTimeInterval: Self.ioSetupRetryDelaySeconds)
        }

        return (lastStatus, nil)
    }

    private func isBluetoothOutputDevice(_ outputDeviceID: AudioObjectID) -> Bool {
        let transportType = readUInt32(objectID: outputDeviceID, selector: kAudioDevicePropertyTransportType)
        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
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

        switch status {
        case .active, .unavailable:
            break
        default:
            return
        }

        let settings = processor.currentSettings
        systemEQLogger.info("Default output device changed; restarting system EQ route")
        _ = restartLocked(settings: settings)
    }

    /// Watchdog, driven off the audio thread by the host on a short timer. If the
    /// route still claims `.active` but our IOProc has gone silent, the system's
    /// real audio is muted with nothing replacing it — recover by tearing the
    /// route down (which immediately un-mutes the system) and rebuilding, backing
    /// off to native passthrough if rebuilds keep failing so audio is never lost.
    public func recoverIfRouteStalled() {
        lock.lock()
        defer { lock.unlock() }

        guard status == .active else {
            return
        }

        guard elapsedSeconds(since: lastIOProcMachTime) > Self.stallThresholdSeconds else {
            // Healthy — but only clear the backoff once we've been healthy a
            // while, so a route that dies again right after a rebuild still
            // counts toward giving up instead of flapping forever.
            if elapsedSeconds(since: lastStallRestartMachTime) > Self.stallBackoffResetSeconds {
                stallRecoveryAttempts = 0
            }
            return
        }

        guard stallRecoveryAttempts < Self.maxStallRecoveryAttempts else {
            systemEQLogger.error("System EQ route stalled repeatedly; falling back to direct output")
            stopLocked(updateStatus: false)
            status = .unavailable(message: "System audio route lost — using direct output")
            currentStreamSnapshot = .inactive
            return
        }

        stallRecoveryAttempts += 1
        lastStallRestartMachTime = mach_absolute_time()
        systemEQLogger.error("System EQ route stalled without IO; rebuilding (attempt \(self.stallRecoveryAttempts, privacy: .public))")
        _ = restartLocked(settings: processor.currentSettings)
    }

    private func elapsedSeconds(since machTime: UInt64) -> Double {
        guard machTime != 0 else {
            return .greatestFiniteMagnitude
        }
        let now = mach_absolute_time()
        guard now > machTime else {
            return 0
        }
        let nanos = (now - machTime) &* UInt64(Self.machTimebase.numer) / UInt64(Self.machTimebase.denom)
        return Double(nanos) / 1_000_000_000
    }

    private func failLocked(_ message: String) -> SystemEQEngineStatus {
        stopLocked(updateStatus: false)
        status = .failed(message: message)
        systemEQLogger.error("System EQ route failed: \(message, privacy: .public)")
        return status
    }

    private func pauseLocked(_ message: String) -> SystemEQEngineStatus {
        stopLocked(updateStatus: false)
        status = .unavailable(message: message)
        currentStreamSnapshot = .inactive
        systemEQLogger.info("System EQ route paused: \(message, privacy: .public)")
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

    private func readValueRange(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> AudioValueRange? {
        var address = propertyAddress(selector)
        var dataSize = UInt32(MemoryLayout<AudioValueRange>.stride)
        var value = AudioValueRange()
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

    @discardableResult
    private func writeUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        value: UInt32
    ) -> OSStatus {
        var address = propertyAddress(selector)
        var newValue = value
        let dataSize = UInt32(MemoryLayout<UInt32>.stride)
        return AudioObjectSetPropertyData(objectID, &address, 0, nil, dataSize, &newValue)
    }

    /// Reduce the aggregate's IO buffer toward `Self.targetBufferFrameSize`,
    /// clamped to what the device supports. Smaller buffer = less capture→re-play
    /// latency = less A/V lip-sync drift while EQ is engaged. Leaves the buffer
    /// alone if it's already at/below the target (don't risk dropouts for nothing).
    private func applyLowLatencyBufferLocked(to aggregateID: AudioObjectID) {
        let current = readUInt32(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSize)
        guard let range = readValueRange(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSizeRange) else {
            return
        }
        let lowerBound = UInt32(max(1, range.mMinimum.rounded()))
        let upperBound = UInt32(max(range.mMaximum.rounded(), Double(lowerBound)))
        let desired = min(max(Self.targetBufferFrameSize, lowerBound), upperBound)

        if let current, current <= desired {
            systemEQLogger.info("System EQ buffer already tight: \(current, privacy: .public) frames (target \(desired, privacy: .public))")
            return
        }

        let status = writeUInt32(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSize, value: desired)
        let currentText = current.map(String.init) ?? "unknown"
        systemEQLogger.info("System EQ buffer frame size: \(currentText, privacy: .public) → \(desired, privacy: .public) (range \(lowerBound, privacy: .public)–\(upperBound, privacy: .public), status \(status, privacy: .public))")
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

    private func settingsSummary(_ settings: EQSettings) -> String {
        let activeBands = settings.bandGainsDB
            .filter { abs($0.value) > 0.001 }
            .keys
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        return "bypassed=\(settings.isBypassed) preamp=\(settings.preampDB) activeBands=\(activeBands.isEmpty ? "none" : activeBands)"
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

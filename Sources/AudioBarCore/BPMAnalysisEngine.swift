import CoreAudio
import Foundation
import OSLog

private let bpmAnalysisLogger = Logger(
    subsystem: "com.michaelvandijk.AudioBar",
    category: "BPMAnalysis"
)

@MainActor
public final class BPMAnalysisEngine {
    public private(set) var readings: [AudioObjectID: BPMReading] = [:]

    private var core: BPMAnalysisCore!

    public init() {
        core = BPMAnalysisCore { [weak self] readings in
            Task { @MainActor in
                self?.readings = readings
            }
        }
    }

    deinit {
        core.stop()
    }

    /// Begin analyzing the given actively-playing source processes.
    public func start(sources: [AudioObjectID], sampleRateHint: Double?) {
        core.start(sources: sources, sampleRateHint: sampleRateHint)
    }

    /// Update the set of analyzed sources as sources come and go.
    public func setSources(_ sources: [AudioObjectID]) {
        core.setSources(sources)
    }

    /// Stop all analysis and tear down taps, aggregate, and IOProc.
    public func stop() {
        core.stop()
        readings = [:]
    }
}

private final class BPMAnalysisCore: @unchecked Sendable {
    private enum Work: Sendable {
        case start(sources: [AudioObjectID], sampleRateHint: Double?)
        case setSources([AudioObjectID])
        case stop(publishEmptyReadings: Bool)
    }

    private static let ioSetupRetryCount = 2
    private static let ioSetupRetryDelaySeconds = 0.08
    private static let publishIntervalSeconds = 1.0
    private static let targetAnalysisBufferFrameSize: UInt32 = 2048
    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private let workQueue = DispatchQueue(label: "com.michaelvandijk.AudioBar.BPMAnalysis.CoreAudio")
    private let lock = NSRecursiveLock()
    private let publishReadings: @Sendable ([AudioObjectID: BPMReading]) -> Void

    private var tapIDs: [AudioObjectID] = []
    private var sourceProcessObjectIDs: [AudioObjectID] = []
    private var inputBufferProcessObjectIDs: [AudioObjectID?] = []
    private var detectorsByProcessObjectID: [AudioObjectID: TempoDetector] = [:]
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var currentSampleRate: Double = 48_000
    private var lastPublishMachTime: UInt64 = 0

    init(publishReadings: @escaping @Sendable ([AudioObjectID: BPMReading]) -> Void) {
        self.publishReadings = publishReadings
    }

    deinit {
        stopSynchronously(publishEmptyReadings: false)
    }

    func start(sources: [AudioObjectID], sampleRateHint: Double?) {
        performCoreAudioWork(.start(sources: sources, sampleRateHint: sampleRateHint))
    }

    func setSources(_ sources: [AudioObjectID]) {
        performCoreAudioWork(.setSources(sources))
    }

    func stop() {
        performCoreAudioWork(BPMAnalysisCore.Work.stop(publishEmptyReadings: true))
    }

    private func performCoreAudioWork(_ work: Work) {
        workQueue.async {
            self.applyCoreAudioWork(work)
        }
    }

    private func applyCoreAudioWork(_ work: Work) {
        lock.lock()
        defer { lock.unlock() }

        switch work {
        case let .start(sources, sampleRateHint):
            startImmediately(sources: sources, sampleRateHint: sampleRateHint)
        case let .setSources(sources):
            setSourcesImmediately(sources)
        case let .stop(publishEmptyReadings):
            stopLocked(publishEmptyReadings: publishEmptyReadings)
        }
    }

    private func startImmediately(sources: [AudioObjectID], sampleRateHint: Double?) {
        let nextSources = normalizedSources(sources)
        let nextSampleRate = max(8_000, sampleRateHint ?? currentSampleRate)
        if isRunningLocked,
           nextSources == sourceProcessObjectIDs,
           abs(nextSampleRate - currentSampleRate) < 1 {
            return
        }

        stopLocked(publishEmptyReadings: false)
        startLocked(sources: nextSources, sampleRateHint: nextSampleRate)
    }

    private func setSourcesImmediately(_ sources: [AudioObjectID]) {
        let nextSources = normalizedSources(sources)
        guard nextSources != sourceProcessObjectIDs else {
            return
        }

        if isRunningLocked {
            stopLocked(publishEmptyReadings: false)
            startLocked(sources: nextSources, sampleRateHint: currentSampleRate)
        } else {
            sourceProcessObjectIDs = nextSources
            pruneDetectorsLocked(to: nextSources, sampleRate: currentSampleRate)
            publishCurrentReadingsLocked(force: true)
        }
    }

    private func stopSynchronously(publishEmptyReadings: Bool) {
        lock.lock()
        defer { lock.unlock() }

        stopLocked(publishEmptyReadings: publishEmptyReadings)
    }

    private func startLocked(sources: [AudioObjectID], sampleRateHint: Double?) {
        let sources = normalizedSources(sources)
        sourceProcessObjectIDs = sources
        currentSampleRate = max(8_000, sampleRateHint ?? currentSampleRate)
        guard !sources.isEmpty else {
            pruneDetectorsLocked(to: [], sampleRate: currentSampleRate)
            publishCurrentReadingsLocked(force: true)
            return
        }

        guard #available(macOS 14.2, *) else {
            bpmAnalysisLogger.error("BPM analysis requires macOS 14.2+")
            publishCurrentReadingsLocked(force: true)
            return
        }

        guard NSClassFromString("CATapDescription") != nil else {
            bpmAnalysisLogger.error("BPM analysis tap unavailable")
            publishCurrentReadingsLocked(force: true)
            return
        }

        guard let outputDeviceID = defaultOutputDeviceID(),
              let outputDeviceUID = readString(objectID: outputDeviceID, selector: kAudioDevicePropertyDeviceUID)
        else {
            bpmAnalysisLogger.error("BPM analysis output device unavailable")
            publishCurrentReadingsLocked(force: true)
            return
        }

        var processObjectIDsForInputBuffers: [AudioObjectID?] = []
        for processObjectID in sources {
            let tapDescription = CATapDescription(monoMixdownOfProcesses: [processObjectID])
            tapDescription.name = "AudioBar BPM Source Tap \(processObjectID)"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = CATapMuteBehavior(rawValue: 0) ?? tapDescription.muteBehavior

            guard let sourceTapID = createProcessTap(tapDescription) else {
                stopLocked(publishEmptyReadings: true)
                return
            }
            tapIDs.append(sourceTapID)
            processObjectIDsForInputBuffers.append(processObjectID)
        }

        let tapUIDs = tapIDs.compactMap { readString(objectID: $0, selector: kAudioTapPropertyUID) }
        guard tapUIDs.count == tapIDs.count else {
            bpmAnalysisLogger.error("BPM analysis tap UID unavailable")
            stopLocked(publishEmptyReadings: true)
            return
        }
        inputBufferProcessObjectIDs = processObjectIDsForInputBuffers

        if let firstTapID = tapIDs.first,
           let tapFormat = readStreamDescription(objectID: firstTapID, selector: kAudioTapPropertyFormat),
           isFloat32LinearPCM(tapFormat) {
            currentSampleRate = max(8_000, tapFormat.mSampleRate)
        }
        pruneDetectorsLocked(to: sources, sampleRate: currentSampleRate)

        let aggregateDescription = SystemEQRouteDescription.makeBPMAnalysisAggregate(
            aggregateUID: "com.michaelvandijk.AudioBar.BPMAnalysis.\(UUID().uuidString)",
            outputDeviceUID: outputDeviceUID,
            tapUIDs: tapUIDs
        )

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        var operationStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard operationStatus == noErr else {
            bpmAnalysisLogger.error("BPM analysis aggregate failed: \(operationStatus)")
            stopLocked(publishEmptyReadings: true)
            return
        }
        aggregateID = newAggregateID

        let ioSetup = createIOProcIDWithRetry(for: aggregateID)
        operationStatus = ioSetup.status
        guard operationStatus == noErr, let newIOProcID = ioSetup.ioProcID else {
            bpmAnalysisLogger.error("BPM analysis IO setup failed: \(operationStatus)")
            stopLocked(publishEmptyReadings: true)
            return
        }
        ioProcID = newIOProcID

        applyAnalysisBufferLocked(to: aggregateID)

        operationStatus = AudioDeviceStart(aggregateID, newIOProcID)
        guard operationStatus == noErr else {
            bpmAnalysisLogger.error("BPM analysis IO start failed: \(operationStatus)")
            stopLocked(publishEmptyReadings: true)
            return
        }

        lastPublishMachTime = mach_absolute_time()
        bpmAnalysisLogger.info("BPM analysis active; sourceCount=\(sources.count, privacy: .public) sampleRate=\(self.currentSampleRate, privacy: .public)")
    }

    fileprivate func process(inputData: UnsafePointer<AudioBufferList>?) {
        guard let inputData, lock.try() else {
            return
        }
        defer { lock.unlock() }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        var buffersByProcessObjectID: [AudioObjectID: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int)]] = [:]

        for inputIndex in 0..<inputBuffers.count {
            guard let processObjectID = SystemEQInputBufferMap.processObjectID(
                inputIndex: inputIndex,
                inputBufferCount: inputBuffers.count,
                tapProcessObjectIDs: inputBufferProcessObjectIDs
            ),
                let inputPointer = inputBuffers[inputIndex].mData?.assumingMemoryBound(to: Float32.self)
            else {
                continue
            }

            let channelCount = max(1, Int(inputBuffers[inputIndex].mNumberChannels))
            let sampleCount = Int(inputBuffers[inputIndex].mDataByteSize) / MemoryLayout<Float32>.stride
            let frameCount = sampleCount / channelCount
            guard frameCount > 0 else {
                continue
            }

            buffersByProcessObjectID[processObjectID, default: []].append((
                pointer: UnsafePointer(inputPointer),
                frameCount: frameCount,
                channelCount: channelCount
            ))
        }

        for (processObjectID, buffers) in buffersByProcessObjectID {
            guard let detector = detectorsByProcessObjectID[processObjectID] else {
                continue
            }
            let monoSamples = downmixToMono(buffers)
            guard !monoSamples.isEmpty else {
                continue
            }
            detector.append(monoSamples)
        }

        publishCurrentReadingsLocked(force: false)
    }

    private func downmixToMono(
        _ buffers: [(pointer: UnsafePointer<Float32>, frameCount: Int, channelCount: Int)]
    ) -> [Float] {
        guard let frameCount = buffers.map(\.frameCount).min(), frameCount > 0 else {
            return []
        }

        let totalChannels = buffers.reduce(0) { $0 + max(1, $1.channelCount) }
        guard totalChannels > 0 else {
            return []
        }

        var monoSamples = [Float]()
        monoSamples.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for buffer in buffers {
                for channel in 0..<buffer.channelCount {
                    sum += buffer.pointer[frame * buffer.channelCount + channel]
                }
            }
            monoSamples.append(sum / Float(totalChannels))
        }
        return monoSamples
    }

    private func publishCurrentReadingsLocked(force: Bool) {
        if !force {
            let now = mach_absolute_time()
            guard elapsedSeconds(from: lastPublishMachTime, to: now) >= Self.publishIntervalSeconds else {
                return
            }
            lastPublishMachTime = now
        }

        let confidentReadings = detectorsByProcessObjectID.compactMapValues { detector -> BPMReading? in
            guard let reading = detector.reading, reading.isConfident else {
                return nil
            }
            return reading
        }
        publishReadings(confidentReadings)
    }

    private func pruneDetectorsLocked(to sources: [AudioObjectID], sampleRate: Double) {
        let sourceSet = Set(sources)
        detectorsByProcessObjectID = detectorsByProcessObjectID.filter { sourceSet.contains($0.key) }
        for source in sources where detectorsByProcessObjectID[source] == nil {
            detectorsByProcessObjectID[source] = TempoDetector(sampleRate: sampleRate)
        }
    }

    private func stopLocked(publishEmptyReadings: Bool) {
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
        sourceProcessObjectIDs = []
        inputBufferProcessObjectIDs = []
        detectorsByProcessObjectID = [:]
        lastPublishMachTime = 0

        if publishEmptyReadings {
            publishReadings([:])
        }
    }

    private var isRunningLocked: Bool {
        aggregateID != kAudioObjectUnknown || ioProcID != nil || !tapIDs.isEmpty
    }

    private func normalizedSources(_ sources: [AudioObjectID]) -> [AudioObjectID] {
        Array(Set(sources.filter { $0 != kAudioObjectUnknown })).sorted()
    }

    private func createIOProcIDWithRetry(
        for aggregateID: AudioObjectID
    ) -> (status: OSStatus, ioProcID: AudioDeviceIOProcID?) {
        var lastStatus: OSStatus = noErr

        for attempt in 0...Self.ioSetupRetryCount {
            var newIOProcID: AudioDeviceIOProcID?
            lastStatus = AudioDeviceCreateIOProcID(
                aggregateID,
                bpmAnalysisIOProc,
                Unmanaged.passUnretained(self).toOpaque(),
                &newIOProcID
            )
            if lastStatus == noErr, let newIOProcID {
                return (lastStatus, newIOProcID)
            }

            guard attempt < Self.ioSetupRetryCount else {
                break
            }
            bpmAnalysisLogger.info("BPM analysis IO setup retry \(attempt + 1, privacy: .public) after status \(lastStatus, privacy: .public)")
            Thread.sleep(forTimeInterval: Self.ioSetupRetryDelaySeconds)
        }

        return (lastStatus, nil)
    }

    @available(macOS 14.2, *)
    private func createProcessTap(_ tapDescription: CATapDescription) -> AudioObjectID? {
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let operationStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard operationStatus == noErr else {
            bpmAnalysisLogger.error("BPM analysis process tap failed: \(operationStatus)")
            return nil
        }
        return newTapID
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

    private func applyAnalysisBufferLocked(to aggregateID: AudioObjectID) {
        let current = readUInt32(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSize)
        guard let range = readValueRange(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSizeRange) else {
            return
        }
        let lowerBound = UInt32(max(1, range.mMinimum.rounded()))
        let upperBound = UInt32(max(range.mMaximum.rounded(), Double(lowerBound)))
        let desired = min(max(Self.targetAnalysisBufferFrameSize, lowerBound), upperBound)

        guard current.map({ $0 < desired }) ?? true else {
            bpmAnalysisLogger.info("BPM analysis buffer already sufficient: \(current ?? 0, privacy: .public) frames (target \(desired, privacy: .public))")
            return
        }

        let status = writeUInt32(objectID: aggregateID, selector: kAudioDevicePropertyBufferFrameSize, value: desired)
        let currentText = current.map(String.init) ?? "unknown"
        bpmAnalysisLogger.info("BPM analysis buffer frame size: \(currentText, privacy: .public) → \(desired, privacy: .public) (range \(lowerBound, privacy: .public)–\(upperBound, privacy: .public), status \(status, privacy: .public))")
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

    private func elapsedSeconds(from start: UInt64, to end: UInt64) -> Double {
        guard start != 0, end > start else {
            return .greatestFiniteMagnitude
        }
        let nanos = (end - start) &* UInt64(Self.machTimebase.numer) / UInt64(Self.machTimebase.denom)
        return Double(nanos) / 1_000_000_000
    }
}

private let bpmAnalysisIOProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    silence(outputData: outputData)

    guard let clientData else {
        return noErr
    }

    let core = Unmanaged<BPMAnalysisCore>.fromOpaque(clientData).takeUnretainedValue()
    core.process(inputData: inputData)
    return noErr
}

private func silence(outputData: UnsafeMutablePointer<AudioBufferList>?) {
    guard let outputData else {
        return
    }

    let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
    for outputIndex in 0..<outputBuffers.count {
        guard let outputData = outputBuffers[outputIndex].mData else {
            continue
        }
        memset(outputData, 0, Int(outputBuffers[outputIndex].mDataByteSize))
    }
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

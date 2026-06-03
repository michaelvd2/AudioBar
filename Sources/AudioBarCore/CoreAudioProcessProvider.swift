import AppKit
import CoreAudio
import Foundation

public protocol AudioProcessProviding {
    func activeOutputProcesses() -> [AudioProcess]
}

public struct CoreAudioProcessProvider: AudioProcessProviding {
    private let volumeController: AppVolumeControlling
    private let webAppProvider: RunningWebAppProvider
    private let currentProcessID: pid_t

    public init(
        volumeController: AppVolumeControlling = ScriptedAppVolumeController(),
        webAppProvider: RunningWebAppProvider = RunningWebAppProvider(),
        currentProcessID: pid_t = getpid()
    ) {
        self.volumeController = volumeController
        self.webAppProvider = webAppProvider
        self.currentProcessID = currentProcessID
    }

    public func activeOutputProcesses() -> [AudioProcess] {
        let webApps = webAppProvider.runningWebApps()

        let processes = processObjectIDs().compactMap { processObjectID -> AudioProcess? in
            guard readUInt32(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) == 1 else {
                return nil
            }

            guard let pid = readPID(objectID: processObjectID) else {
                return nil
            }

            let bundleID = readRetainedString(
                objectID: processObjectID,
                selector: kAudioProcessPropertyBundleID
            )
            let runningApp = NSRunningApplication(processIdentifier: pid)
            if let webAppSource = WebKitMediaSourceResolver.resolve(
                helperAudioObjectID: processObjectID,
                helperPID: pid,
                helperBundleID: bundleID,
                helperName: runningApp?.localizedName,
                webApps: webApps
            ) {
                return webAppSource
            }

            let trackTitle = volumeController.currentTrackTitle(for: bundleID)
            let currentVolume = volumeController.currentVolume(for: bundleID)

            return AudioProcessResolver.resolve(
                audioObjectID: processObjectID,
                pid: pid,
                bundleID: bundleID,
                localizedAppName: runningApp?.localizedName,
                trackTitle: trackTitle,
                currentVolume: currentVolume
            )
        }

        return AudioProcess.visibleUserSources(processes, currentPID: currentProcessID)
    }

    private func processObjectIDs() -> [AudioObjectID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else {
            return []
        }

        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        let status = objectIDs.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }

        return status == noErr ? objectIDs : []
    }

    private func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.stride)
        let status = withUnsafeMutableBytes(of: &value) { rawBuffer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                rawBuffer.baseAddress!
            )
        }
        return status == noErr ? value : nil
    }

    private func readPID(objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value = pid_t(0)
        var dataSize = UInt32(MemoryLayout<pid_t>.stride)
        let status = withUnsafeMutableBytes(of: &value) { rawBuffer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                rawBuffer.baseAddress!
            )
        }
        return status == noErr ? value : nil
    }

    private func readRetainedString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                UnsafeMutableRawPointer(pointer)
            )
        }

        guard status == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}

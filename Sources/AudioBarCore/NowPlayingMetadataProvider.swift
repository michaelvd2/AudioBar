import Foundation

public struct NowPlayingMetadata: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let sourceBundleID: String?

    public init(title: String?, artist: String?, sourceBundleID: String?) {
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.sourceBundleID = sourceBundleID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public protocol NowPlayingMetadataProviding {
    func currentMetadata() -> NowPlayingMetadata?
}

#if APP_STORE
public final class NowPlayingMetadataProvider: NowPlayingMetadataProviding {
    public init() {}

    public func currentMetadata() -> NowPlayingMetadata? {
        nil
    }
}
#else
public final class NowPlayingMetadataProvider: NowPlayingMetadataProviding {
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void

    private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    public init() {}

    public func currentMetadata() -> NowPlayingMetadata? {
        guard
            let handle = dlopen(frameworkPath, RTLD_NOW),
            let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else {
            return nil
        }
        defer { dlclose(handle) }

        let getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
        let box = MetadataBox()
        let semaphore = DispatchSemaphore(value: 0)

        getNowPlayingInfo(.global(qos: .userInitiated)) { info in
            box.value = Self.metadata(from: info, handle: handle)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + .milliseconds(250))
        return box.value
    }

    private static func metadata(from info: CFDictionary?, handle: UnsafeMutableRawPointer) -> NowPlayingMetadata? {
        guard let dictionary = info as NSDictionary? else {
            return nil
        }

        let title = stringValue(
            in: dictionary,
            keys: [
                mediaRemoteConstant("kMRMediaRemoteNowPlayingInfoTitle", handle: handle),
                "kMRMediaRemoteNowPlayingInfoTitle",
                "title"
            ]
        )
        let artist = stringValue(
            in: dictionary,
            keys: [
                mediaRemoteConstant("kMRMediaRemoteNowPlayingInfoArtist", handle: handle),
                "kMRMediaRemoteNowPlayingInfoArtist",
                "artist"
            ]
        )
        let sourceBundleID = stringValue(
            in: dictionary,
            keys: [
                mediaRemoteConstant("kMRMediaRemoteNowPlayingInfoClientBundleIdentifier", handle: handle),
                mediaRemoteConstant("kMRMediaRemoteNowPlayingInfoClientPropertiesData", handle: handle),
                "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier",
                "bundleIdentifier"
            ]
        )

        let metadata = NowPlayingMetadata(title: title, artist: artist, sourceBundleID: sourceBundleID)
        guard metadata.title != nil || metadata.artist != nil else {
            return nil
        }
        return metadata
    }

    private static func stringValue(in dictionary: NSDictionary, keys: [String?]) -> String? {
        for key in keys.compactMap(\.self) {
            if let value = dictionary[key] as? String,
               let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return trimmed
            }
        }
        return nil
    }

    private static func mediaRemoteConstant(_ name: String, handle: UnsafeMutableRawPointer) -> String? {
        guard let symbol = dlsym(handle, name) else {
            return nil
        }
        return symbol.assumingMemoryBound(to: CFString.self).pointee as String
    }
}

private final class MetadataBox: @unchecked Sendable {
    var value: NowPlayingMetadata?
}
#endif

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

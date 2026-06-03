import CoreAudio
import Foundation

enum SystemEQRouteDescription {
    static func makeAggregate(
        aggregateUID: String,
        outputDeviceUID: String,
        tapUID: String
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "AudioBar System EQ",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID,
                kAudioSubDeviceExtraInputLatencyKey: 0,
                kAudioSubDeviceExtraOutputLatencyKey: 0
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapExtraInputLatencyKey: 0,
                kAudioSubTapExtraOutputLatencyKey: 0,
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapDriftCompensationQualityKey: Int(kAudioAggregateDriftCompensationHighQuality)
            ]]
        ]
    }
}

import CoreAudio
import Foundation

enum SystemEQRouteDescription {
    static func makeAggregate(
        aggregateUID: String,
        outputDeviceUID: String,
        tapUID: String
    ) -> [String: Any] {
        makeAggregate(
            aggregateUID: aggregateUID,
            outputDeviceUID: outputDeviceUID,
            tapUIDs: [tapUID]
        )
    }

    static func makeAggregate(
        aggregateUID: String,
        outputDeviceUID: String,
        tapUIDs: [String]
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "AudioBar System EQ",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID,
                kAudioSubDeviceExtraInputLatencyKey: 0,
                kAudioSubDeviceExtraOutputLatencyKey: 0
            ]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map { tapUID in [
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapExtraInputLatencyKey: 0,
                kAudioSubTapExtraOutputLatencyKey: 0,
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapDriftCompensationQualityKey: Int(kAudioAggregateDriftCompensationHighQuality)
            ] }
        ]
    }

    static func makeBPMAnalysisAggregate(
        aggregateUID: String,
        outputDeviceUID: String,
        tapUIDs: [String]
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "AudioBar BPM Analysis",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID,
                kAudioSubDeviceExtraInputLatencyKey: 0,
                kAudioSubDeviceExtraOutputLatencyKey: 0
            ]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map { tapUID in [
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapExtraInputLatencyKey: 0,
                kAudioSubTapExtraOutputLatencyKey: 0,
                kAudioSubTapDriftCompensationKey: false
            ] }
        ]
    }
}

import HealthKit

enum HealthSourceIdentity {
    static func sleepOrigin(_ sample: HKSample) -> HealthSleepOrigin {
        let device = sample.device
        return HealthSleepOrigin(sourceID: key(sample), appName: sample.sourceRevision.source.name,
            bundleIdentifier: sample.sourceRevision.source.bundleIdentifier, deviceName: device?.name,
            model: device?.model, manufacturer: device?.manufacturer, localIdentifier: device?.localIdentifier)
    }
    static func key(_ sample: HKSample) -> String {
        let source = sample.sourceRevision.source
        let device = sample.device
        // A model name alone cannot distinguish two devices of the same model.
        let identity = device?.localIdentifier ?? [device?.name, device?.manufacturer, device?.model, device?.hardwareVersion]
            .map { $0 ?? "" }.joined(separator: "|")
        let fields = [source.bundleIdentifier, identity]
        let encoded = (try? JSONEncoder().encode(fields)) ?? Data()
        return WearableVital.deviceKey(encoded.base64EncodedString())
    }
    static func describe(_ sample: HKSample) -> HealthDataSource {
        let device = sample.device
        let raw = device?.name ?? device?.model
        let name = raw.map(DevicePresentation.name) ?? "来源未标明设备"
        return HealthDataSource(id: key(sample), appName: DevicePresentation.name(sample.sourceRevision.source.name),
                                deviceName: name, hardwareIdentified: device?.localIdentifier != nil)
    }
    static func matches(_ first: HKSample, _ second: HKSample) -> Bool { key(first) == key(second) }
}

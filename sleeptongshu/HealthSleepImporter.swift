import HealthKit
import CryptoKit
import Combine

struct HealthSleepInterval {
    let id: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
}

enum HealthSleepNormalizer {
    // Overlapping HealthKit intervals are split at boundaries. Gaps remain unknown, never awake.
    static func segments(_ intervals: [HealthSleepInterval]) -> [SleepSegment] {
        let boundaries = Set(intervals.flatMap { [$0.start, $0.end] }).sorted()
        guard boundaries.count >= 2 else { return [] }
        return zip(boundaries, boundaries.dropFirst()).reduce(into: [SleepSegment]()) { result, pair in
            let active = intervals.filter { $0.start <= pair.0 && $0.end >= pair.1 }.map(\.stage)
            let known = Set(active.filter { $0 != .unobserved && $0 != .unspecified })
            let stage: SleepStage
            if known.count == 1 { stage = known.first! }
            else if known.count > 1 { stage = .unobserved }
            else if active.contains(.unspecified) { stage = .unspecified }
            else { stage = .unobserved }
            if result.last?.stage == stage { result[result.count - 1].end = pair.1 }
            else { result.append(SleepSegment(stage: stage, start: pair.0, end: pair.1)) }
        }
    }

    static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

@MainActor
final class HealthSleepImporter: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var providers: [String] = []
    @Published var selectedProvider = ""
    @Published var message: String?
    private let store = HKHealthStore()
    private var sleeps: [HKCategorySample] = []
    static var enabled: Bool { (Bundle.main.object(forInfoDictionaryKey: "SleepHealthKitEnabled") as? String)?.uppercased() == "YES" }
    private let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private var readTypes: Set<HKObjectType> {
        Set([sleep, HKObjectType.quantityType(forIdentifier: .heartRate)!,
             HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
             HKObjectType.quantityType(forIdentifier: .respiratoryRate)!])
    }

    func load() async {
        guard Self.enabled else {
            message = "此安装版本未启用系统健康读取。可直接使用手机监测或连接设备同步。"
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { message = "当前设备不支持系统健康读取，请在手机上使用。"; return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
            sleeps = try await samples(type: sleep, start: start, end: .now, limit: 10000).compactMap { $0 as? HKCategorySample }
            providers = Set(sleeps.map(providerKey)).sorted()
            if !providers.contains(selectedProvider) { selectedProvider = providers.first ?? "" }
            if providers.isEmpty { message = "没有读到最近 30 天的睡眠记录。请确认系统健康内已有记录，并允许读取；未授权和没有记录时均可能返回空数据。" }
        } catch { message = "健康读取失败：\(error.localizedDescription)" }
    }

    func importSelected() async throws -> [SleepPayload] {
        isLoading = true
        defer { isLoading = false }
        let selected = sleeps.filter { providerKey($0) == selectedProvider }
        // A noon boundary groups an overnight session; each source/device is imported independently.
        let groups = Dictionary(grouping: selected) { sample in
            Calendar.current.startOfDay(for: sample.endDate.addingTimeInterval(-12 * 3600))
        }
        var payloads: [SleepPayload] = []
        for (day, entries) in groups.sorted(by: { $0.key < $1.key }) {
            let intervals = entries.compactMap { sample -> HealthSleepInterval? in
                let stage: SleepStage
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepCore: stage = .light
                case .asleepDeep: stage = .deep
                case .asleepREM: stage = .rem
                case .awake: stage = .awake
                case .asleepUnspecified: stage = .unspecified
                default: return nil // In-bed intervals are not proof of sleep.
                }
                return HealthSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage)
            }
            let segments = HealthSleepNormalizer.segments(intervals)
            guard let start = segments.first?.start, let end = segments.last?.end,
                  end > start, end.timeIntervalSince(start) <= 24 * 3600,
                  segments.contains(where: { $0.stage != .awake && $0.stage != .unobserved }) else { continue }
            let heart = try await quantities(.heartRate, start: start, end: end, entries: entries, segments: segments)
            let oxygen = try await quantities(.oxygenSaturation, start: start, end: end, entries: entries, segments: segments)
            let breathing = try await quantities(.respiratoryRate, start: start, end: end, entries: entries, segments: segments)
            let hearts = heart.map { HeartSample(id: $0.uuid, date: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
            let key = "health-v2|\(selectedProvider)|\(Int(day.timeIntervalSince1970))"
            let payload = SleepPayload(id: HealthSleepNormalizer.stableID(key), start: start, end: end, source: .healthKit,
                                      segments: segments, heartSamples: hearts,
                                      averageHeartRate: average(hearts.map(\.bpm)),
                                      averageSpO2: average(oxygen.map { $0.quantity.doubleValue(for: .percent()) * 100 }),
                                      averageRespiratoryRate: average(breathing.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }),
                                      note: "来源：\(selectedProvider)。缺口及冲突区间保留为未记录；体征是已读取样本的算术平均。",
                                      metadata: SleepMetadata(externalSource: selectedProvider, externalID: key))
            try payload.validate()
            payloads.append(payload)
        }
        return payloads
    }

    private func providerKey(_ sample: HKSample) -> String {
        "\(sample.sourceRevision.source.name) · \(sample.sourceRevision.source.bundleIdentifier) · \(sample.device?.localIdentifier ?? sample.device?.model ?? "未标识设备")"
    }
    private func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    private func quantities(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date, entries: [HKCategorySample], segments: [SleepSegment]) async throws -> [HKQuantitySample] {
        let objects = try await samples(type: HKObjectType.quantityType(forIdentifier: identifier)!, start: start, end: end, limit: 20000)
        let sources = Set(entries.map { $0.sourceRevision.source.bundleIdentifier })
        let devices = Set(entries.compactMap { $0.device?.localIdentifier })
        return objects.compactMap { $0 as? HKQuantitySample }.filter {
            sample in
            sources.contains(sample.sourceRevision.source.bundleIdentifier)
            && (devices.isEmpty || sample.device?.localIdentifier.map { devices.contains($0) } == true)
            && segments.contains { segment in
                segment.stage != .awake && segment.stage != .unobserved && sample.startDate >= segment.start && sample.endDate <= segment.end
            }
        }
    }
    private func samples(type: HKSampleType, start: Date, end: Date, limit: Int) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}

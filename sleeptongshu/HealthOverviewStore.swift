import Foundation
import HealthKit
import Combine

extension HealthMetric {
    var quantityIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .sleep: nil
        case .heart: .heartRate
        case .restingHeart: .restingHeartRate
        case .hrv: .heartRateVariabilitySDNN
        case .oxygen: .oxygenSaturation
        case .respiration: .respiratoryRate
        case .steps: .stepCount
        case .exercise: .appleExerciseTime
        case .vo2: .vo2Max
        case .systolic: .bloodPressureSystolic
        case .diastolic: .bloodPressureDiastolic
        }
    }
    var healthUnit: HKUnit {
        switch self {
        case .sleep: .hour()
        case .heart, .restingHeart, .respiration: HKUnit.count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .oxygen: .percent()
        case .steps: .count()
        case .exercise: .minute()
        case .vo2: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .systolic, .diastolic: .millimeterOfMercury()
        }
    }
}

@MainActor
final class HealthOverviewStore: ObservableObject {
    @Published private(set) var snapshot: HealthOverviewSnapshot?
    @Published private(set) var selections: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var progress = ""
    @Published var message: String?
    @Published private(set) var storageError: String?
    private let health = HKHealthStore()
    private let url: URL?
    private var cache: [HealthMetric: [HealthDay]] = [:]
    private var failedToReadCache = false

    init(url: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("system-health-overview-v1.json")) {
        self.url = url
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-health") { loadFixture() }
            return
        }
        #endif
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let archive = try JSONDecoder().decode(HealthOverviewArchive.self, from: Data(contentsOf: url))
            snapshot = archive.snapshot; selections = archive.selections
        } catch { failedToReadCache = true; storageError = "本机健康快照未能打开，原文件已保留。可在数据来源中清空快照后重新读取。" }
    }

    func sources(for metric: HealthMetric) -> [HealthDataSource] {
        let ids = Set(snapshot?.observations.filter { $0.metric == metric }.map(\.sourceID) ?? [])
        return snapshot?.sources.filter { ids.contains($0.id) }.sorted { $0.selectionLabel < $1.selectionLabel } ?? []
    }
    func source(for metric: HealthMetric) -> HealthDataSource? { snapshot?.sources.first { $0.id == selections[metric.rawValue] } }
    func select(_ id: String, for metric: HealthMetric) {
        guard !isLoading else { return }
        guard id.isEmpty || sources(for: metric).contains(where: { $0.id == id }) else { return }
        selections[metric.rawValue] = id
        cache[metric] = nil
        persist()
    }
    func days(for metric: HealthMetric) -> [HealthDay] {
        if let cached = cache[metric] { return cached }
        guard let snapshot, !snapshot.truncatedMetrics.contains(metric), let id = selections[metric.rawValue], !id.isEmpty else { return [] }
        let result = HealthOverviewAnalysis.daily(snapshot.observations.filter { $0.sourceID == id }, metric: metric)
        cache[metric] = result
        return result
    }
    var latestDate: Date? { snapshot?.observations.map(\.end).max() }

    func refresh() async {
        guard !isLoading else { return }
        guard !failedToReadCache else { message = storageError; return }
        guard HealthSleepImporter.enabled, HKHealthStore.isHealthDataAvailable() else {
            message = "请在启用系统健康的 iPhone 版本中读取。"; return
        }
        isLoading = true
        defer { isLoading = false; progress = "" }
        do {
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let quantities = HealthMetric.allCases.compactMap { $0.quantityIdentifier.flatMap(HKObjectType.quantityType(forIdentifier:)) }
            var types = Set<HKObjectType>(quantities)
            types.insert(sleep)
            types.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
            types.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
            progress = "等待系统健康授权"
            try await health.requestAuthorization(toShare: [], read: types)
            let readAt = Date.now
            let start = Calendar.current.date(byAdding: .day, value: -90, to: Calendar.current.startOfDay(for: readAt))!
            var sources: [String: HealthDataSource] = [:]
            var observations: [HealthObservation] = []
            var truncated: [HealthMetric] = []
            for metric in HealthMetric.allCases {
                progress = "正在读取\(metric.title)"
                let type: HKSampleType = metric == .sleep ? sleep : HKObjectType.quantityType(forIdentifier: metric.quantityIdentifier!)!
                let samples = try await read(type: type, start: start, end: readAt)
                if samples.count >= 50_000 { truncated.append(metric) }
                for sample in samples { sources[HealthSourceIdentity.key(sample)] = HealthSourceIdentity.describe(sample) }
                if metric == .sleep {
                    let groups = Dictionary(grouping: samples.compactMap { $0 as? HKCategorySample }, by: HealthSourceIdentity.key)
                    for (id, values) in groups {
                        let intervals = values.compactMap { sample -> HealthSleepInterval? in
                            guard let stage = Self.stage(sample.value), sample.endDate > sample.startDate,
                                  sample.endDate.timeIntervalSince(sample.startDate) <= 24 * 3600 else { return nil }
                            return HealthSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage)
                        }
                        observations += HealthOverviewAnalysis.sleepObservations(intervals, sourceID: id)
                    }
                } else {
                    observations += samples.compactMap { sample in
                        guard let sample = sample as? HKQuantitySample else { return nil }
                        let value = sample.quantity.doubleValue(for: metric.healthUnit) * (metric == .oxygen ? 100 : 1)
                        guard metric.accepts(value), sample.endDate >= sample.startDate else { return nil }
                        return HealthObservation(id: sample.uuid.uuidString, metric: metric, sourceID: HealthSourceIdentity.key(sample),
                                                 start: sample.startDate, end: sample.endDate, value: value)
                    }
                }
            }
            let birth = try? health.dateOfBirthComponents()
            let age = birth.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
                .flatMap { Calendar.current.dateComponents([.year], from: $0, to: readAt).year }
            let sex = try? health.biologicalSex().biologicalSex
            let reference: HealthReferenceSex = sex == .female ? .female : sex == .male ? .male : .unspecified
            let next = HealthOverviewSnapshot(readAt: readAt, sources: Array(sources.values).sorted { $0.id < $1.id },
                                              observations: observations, age: age, referenceSex: reference, truncatedMetrics: truncated)
            var choices = selections
            for metric in HealthMetric.allCases where choices[metric.rawValue] == nil {
                let counts = Dictionary(grouping: observations.filter { $0.metric == metric }, by: \.sourceID)
                choices[metric.rawValue] = counts.keys.sorted { first, second in
                    if counts[first]!.count == counts[second]!.count { return first < second }
                    return counts[first]!.count > counts[second]!.count
                }.first ?? ""
            }
            // Save before publishing; an unsuccessful refresh leaves the previous snapshot intact.
            try write(HealthOverviewArchive(snapshot: next, selections: choices))
            snapshot = next; selections = choices; cache = [:]; storageError = nil
            if observations.isEmpty {
                message = "没有读到可用记录。请检查系统健康内是否已有数据，以及是否允许本 App 读取。系统不会告诉 App 某一项读取权限是否被拒绝。"
            }
        } catch { message = "读取未完成，保留上次快照：\(error.localizedDescription)" }
    }

    nonisolated static func stage(_ raw: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: raw) {
        case .asleepCore: .light; case .asleepDeep: .deep; case .asleepREM: .rem
        case .awake: .awake; case .asleepUnspecified: .unspecified; default: nil
        }
    }
    private func read(type: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate]),
                                      limit: 50_000, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }

    func clearSnapshot() throws {
        guard !isLoading else { return }
        if let url, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        snapshot = nil; selections = [:]; cache = [:]; storageError = nil; failedToReadCache = false
    }
    func export() throws -> Data { try JSONEncoder().encode(HealthOverviewArchive(snapshot: snapshot, selections: selections)) }
    private func persist() {
        guard !failedToReadCache else { return }
        do { try write(HealthOverviewArchive(snapshot: snapshot, selections: selections)); storageError = nil }
        catch { storageError = "选择已在当前页面生效，但未能保存：\(error.localizedDescription)" }
    }
    private func write(_ archive: HealthOverviewArchive) throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        #endif
        guard let url else { return }
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    #if DEBUG
    private func loadFixture() {
        let a = HealthDataSource(id: "test-device-a", appName: "系统健康来源", deviceName: "手表 A · 示例", hardwareIdentified: true)
        let b = HealthDataSource(id: "test-device-b", appName: "设备记录来源", deviceName: "戒指 B · 示例", hardwareIdentified: true)
        let today = Calendar.current.startOfDay(for: .now)
        var values: [HealthObservation] = []
        for metric in HealthMetric.allCases {
            for day in 1...80 {
                for source in [a, b] {
                    let date = Calendar.current.date(byAdding: .day, value: -day, to: today)!
                    let baseline: Double
                    switch metric {
                    case .sleep: baseline = source.id == a.id ? 7.3 : 6.6
                    case .restingHeart: baseline = day < 15 ? 58 : 62
                    case .hrv: baseline = day < 15 ? 49 : 44
                    case .heart: baseline = 70
                    case .oxygen: baseline = 97
                    case .respiration: baseline = 15
                    case .steps: baseline = source.id == a.id ? 7400 : 5300
                    case .exercise: baseline = 32
                    case .vo2: baseline = day < 31 ? 39 : 37
                    case .systolic: baseline = 116
                    case .diastolic: baseline = 75
                    }
                    let jitter = metric == .vo2 ? 0 : Double(day % 3) * (metric == .steps ? 120 : metric == .sleep ? 0.1 : 0.2)
                    values.append(HealthObservation(id: "\(metric.rawValue)-\(source.id)-\(day)", metric: metric, sourceID: source.id,
                                                    start: date, end: date, value: baseline + jitter))
                }
            }
            selections[metric.rawValue] = a.id
        }
        snapshot = HealthOverviewSnapshot(readAt: .now, sources: [a, b], observations: values, age: 42, referenceSex: .male)
    }
    #endif
}

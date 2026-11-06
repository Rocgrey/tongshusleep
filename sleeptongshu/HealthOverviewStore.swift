import Foundation
import HealthKit
import Combine
import SwiftData

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
    @Published private(set) var isLoading = false
    @Published private(set) var progress = ""
    @Published private(set) var progressValue: Double?
    @Published var message: String?
    @Published private(set) var messageIsError = false
    @Published private(set) var storageError: String?
    private let health = HKHealthStore()
    private let url: URL?
    private var cache: [HealthMetric: [HealthDay]] = [:]
    private var failedToReadCache = false
    private var lastAutomaticAttempt: Date?

    func refreshIfNeeded(in context: ModelContext? = nil) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        #endif
        guard let snapshot, Date.now.timeIntervalSince(snapshot.readAt) >= 15 * 60,
              lastAutomaticAttempt.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAutomaticAttempt = .now
        await refresh(in: context)
    }

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
            snapshot = archive.snapshot
        } catch { failedToReadCache = true; storageError = "本机健康快照未能打开，原文件已保留。可在健康设置中清空快照后重新读取。" }
    }

    func sourceSummary(for metric: HealthMetric) -> String {
        guard let snapshot, snapshot.observations.contains(where: { $0.metric == metric }) else { return "系统健康" }
        if metric.isCumulative { return "系统健康 · 每日统计" }
        if metric == .sleep { return "系统健康 · 每晚自动整理" }
        let count = Set(snapshot.observations.filter { $0.metric == metric }.map(\.sourceID)).count
        return count > 1 ? "系统健康 · \(count) 个记录来源" : "系统健康"
    }
    func days(for metric: HealthMetric) -> [HealthDay] {
        if let cached = cache[metric] { return cached }
        guard let snapshot, !snapshot.truncatedMetrics.contains(metric) else { return [] }
        let result = HealthOverviewAnalysis.daily(snapshot.observations, metric: metric)
        cache[metric] = result
        return result
    }
    var latestDate: Date? { snapshot?.observations.map(\.end).max() }

    func refresh(in context: ModelContext? = nil) async {
        guard !isLoading else { return }
        guard !failedToReadCache else { message = storageError; messageIsError = true; return }
        guard HealthSleepImporter.enabled, HKHealthStore.isHealthDataAvailable() else {
            message = "请在启用系统健康的 iPhone 版本中读取。"; messageIsError = true; return
        }
        isLoading = true
        message = nil
        messageIsError = false
        progressValue = nil
        defer { isLoading = false; progress = ""; progressValue = nil }
        do {
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let quantities = HealthMetric.allCases.compactMap { $0.quantityIdentifier.flatMap(HKObjectType.quantityType(forIdentifier:)) }
            var types = Set<HKObjectType>(quantities)
            types.insert(sleep)
            types.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
            types.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
            progress = "等待系统健康授权"
            let authorization = try await health.statusForAuthorizationRequest(toShare: [], read: types)
            if authorization != .unnecessary {
                try await health.requestAuthorization(toShare: [], read: types)
            }
            let readAt = Date.now
            let start = Calendar.current.date(byAdding: .day, value: -90, to: Calendar.current.startOfDay(for: readAt))!
            var sources: [String: HealthDataSource] = [:]
            var observations: [HealthObservation] = []
            var truncated: [HealthMetric] = []
            var candidates: [HealthSleepCandidate] = []
            var notices: [String] = []
            var completed = 0
            progressValue = 0
            for metric in HealthMetric.allCases {
                progress = "正在读取\(metric.title)（\(completed + 1)/\(HealthMetric.allCases.count)）"
                do {
                if metric.isCumulative {
                    let totals = try await readDailyTotals(metric: metric, start: start, end: readAt)
                    observations += totals.observations
                    for source in totals.sources { sources[source.id] = source }
                    completed += 1
                    progressValue = Double(completed) / Double(HealthMetric.allCases.count)
                    continue
                }
                let type: HKSampleType = metric == .sleep ? sleep : HKObjectType.quantityType(forIdentifier: metric.quantityIdentifier!)!
                let samples = try await read(type: type, start: start, end: readAt)
                completed += 1
                if samples.count >= 50_000 {
                    truncated.append(metric)
                    notices.append("\(metric.title)记录达到本次读取上限，暂不汇总。")
                    continue
                }
                for sample in samples { sources[HealthSourceIdentity.key(sample)] = HealthSourceIdentity.describe(sample) }
                if metric == .sleep {
                    let groups = Dictionary(grouping: samples.compactMap { $0 as? HKCategorySample }, by: HealthSourceIdentity.key)
                    for (id, values) in groups {
                        let intervals = values.compactMap { sample -> HealthSleepInterval? in
                            guard let stage = Self.stage(sample.value), sample.endDate > sample.startDate,
                                  sample.endDate.timeIntervalSince(sample.startDate) <= 24 * 3600 else { return nil }
                            return HealthSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage)
                        }
                        candidates.append(HealthSleepCandidate(sourceID: id, intervals: intervals))
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
                } catch { notices.append("\(metric.title)本次未能读取，其他项目仍可查看。") }
                if completed < HealthMetric.allCases.firstIndex(of: metric)! + 1 {
                    completed = HealthMetric.allCases.firstIndex(of: metric)! + 1
                }
                progressValue = Double(completed) / Double(HealthMetric.allCases.count)
            }
            guard completed > 0 else { throw NSError(domain: "SystemHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统健康暂时无法读取，请稍后重试。旧快照已保留。"] ) }
            var sleepRecords: [SleepPayload] = []
            do { sleepRecords = try HealthSleepImporter.automaticRecords(candidates, observations: observations, sources: Array(sources.values)) }
            catch { notices.append("部分睡眠记录暂未整理，已读到的体征与活动仍可查看。") }
            for payload in sleepRecords {
                let date = Calendar.current.date(byAdding: .day, value: 1, to: HealthSleepImporter.night(payload.end))!
                let hours = payload.segments.filter { ![.awake, .unobserved].contains($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
                observations.append(HealthObservation(id: payload.id.uuidString, metric: .sleep, sourceID: "system-health-sleep", start: date, end: date, value: hours))
            }
            let birth = try? health.dateOfBirthComponents()
            let age = birth.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
                .flatMap { Calendar.current.dateComponents([.year], from: $0, to: readAt).year }
            let sex = try? health.biologicalSex().biologicalSex
            let reference: HealthReferenceSex = sex == .female ? .female : sex == .male ? .male : .unspecified
            let next = HealthOverviewSnapshot(readAt: readAt, sources: Array(sources.values).sorted { $0.id < $1.id },
                                              observations: observations, age: age, referenceSex: reference, truncatedMetrics: truncated,
                                              sleepRecords: sleepRecords, notices: notices)
            let hasNewData = HealthOverviewAnalysis.hasNewData(previous: snapshot, next: next)
            // Save before publishing; an unsuccessful refresh leaves the previous snapshot intact.
            try write(HealthOverviewArchive(snapshot: next))
            snapshot = next; cache = [:]; storageError = nil
            message = hasNewData ? "健康数据已更新，读取到新增记录。" : "暂时没有新的数据可以更新，当前数据已是最新的。"
            messageIsError = false
            if let context {
                do { try HealthSleepImporter.save(sleepRecords, in: context) }
                catch { context.rollback(); message = "健康概览已更新，但睡眠报告保存未完成，请重新刷新。"; messageIsError = true }
            }
            // Empty results remain visible on the page with permission and source guidance.
        } catch { message = "读取未完成，原有数据仍保留：\(error.localizedDescription)"; messageIsError = true }
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

    private func readDailyTotals(metric: HealthMetric, start: Date, end: Date) async throws -> (observations: [HealthObservation], sources: [HealthDataSource]) {
        let queryStore = health
        return try await withCheckedThrowingContinuation { continuation in
            let type = HKObjectType.quantityType(forIdentifier: metric.quantityIdentifier!)!
            let query = HKStatisticsCollectionQuery(quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum, anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { query, collection, error in
                queryStore.stop(query)
                if let error { continuation.resume(throwing: error); return }
                var observations: [HealthObservation] = []
                var sources: [String: HealthDataSource] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard statistics.startDate <= end, let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: metric.healthUnit)
                    guard metric.accepts(value) else { return }
                    observations.append(HealthObservation(id: "system|\(metric.rawValue)|\(statistics.startDate.timeIntervalSince1970)", metric: metric,
                        sourceID: "system-health-statistics", start: statistics.startDate, end: min(statistics.endDate, end), value: value))
                    for source in statistics.sources ?? [] {
                        let id = WearableVital.deviceKey(source.bundleIdentifier)
                        sources[id] = HealthDataSource(id: id, appName: DevicePresentation.name(source.name), deviceName: "系统统计来源", hardwareIdentified: false)
                    }
                }
                continuation.resume(returning: (observations, Array(sources.values)))
            }
            health.execute(query)
        }
    }

    func clearSnapshot() throws {
        guard !isLoading else { return }
        if let url, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        snapshot = nil; cache = [:]; storageError = nil; failedToReadCache = false
    }
    func export() throws -> Data { try JSONEncoder().encode(HealthOverviewArchive(snapshot: snapshot)) }
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
                    if metric.isCumulative && source.id == b.id { continue }
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
                    values.append(HealthObservation(id: "\(metric.rawValue)-\(source.id)-\(day)", metric: metric, sourceID: metric.isCumulative ? "system-health-statistics" : source.id,
                                                    start: date, end: date, value: baseline + jitter))
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-health-sparse") {
            values.removeAll { [.oxygen, .vo2].contains($0.metric) }
        }
        snapshot = HealthOverviewSnapshot(readAt: .now, sources: [a, b], observations: values, age: 42, referenceSex: .male)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-health-loading") {
            isLoading = true
            progress = "正在读取心率（3/11）"
            progressValue = 2.0 / 11.0
        }
    }
    #endif
}

import Foundation
import HealthKit

struct HealthSleepWindow: Codable, Equatable {
    let start: Date
    let end: Date
    init(now: Date = .now, calendar: Calendar = .current) {
        start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))!
        end = now
    }
    init(start: Date, end: Date) { self.start = start; self.end = end }
    func contains(_ end: Date) -> Bool { end >= start && end <= self.end }
}

struct HealthSleepOrigin: Codable, Equatable {
    var sourceID: String
    var appName: String
    var bundleIdentifier: String?
    var deviceName: String?
    var model: String?
    var manufacturer: String?
    var localIdentifier: String?
    var label: String { [appName, deviceName ?? model].compactMap { $0 }.joined(separator: " · ") }
}

struct HealthSleepDetails: Codable {
    var version = 1
    let origin: HealthSleepOrigin
    let samples: [HealthSleepInterval]
    let otherSourceIDs: [String]
    let timeZoneIdentifier: String
    let endDay: String
    var isRemoved = false
    var bedRangeIsComplete: Bool? = nil
}

struct HealthSleepReadResult {
    var candidates: [HealthSleepCandidate]
    var sources: [HealthDataSource]
}

enum HealthSleepReadError: LocalizedError {
    case unavailable, tooManySamples
    var errorDescription: String? {
        switch self {
        case .unavailable: "当前设备无法使用系统健康，请在支持系统健康的 iPhone 上读取。"
        case .tooManySamples: "睡眠记录超过本次读取上限，原有记录已保留。请稍后重试。"
        }
    }
}

@MainActor protocol HealthSleepReading {
    var isAvailable: Bool { get }
    func read(_ window: HealthSleepWindow, requestAccess: Bool) async throws -> HealthSleepReadResult
}

/// The dedicated sleep entry asks for sleep read access only, never any write types.
@MainActor struct HKSystemSleepReader: HealthSleepReading {
    let health: HKHealthStore
    var isAvailable: Bool { HealthSleepImporter.enabled && HKHealthStore.isHealthDataAvailable() }
    func read(_ window: HealthSleepWindow, requestAccess: Bool) async throws -> HealthSleepReadResult {
        guard isAvailable else { throw HealthSleepReadError.unavailable }
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        if requestAccess, try await health.statusForAuthorizationRequest(toShare: [], read: [type]) == .shouldRequest {
            try await health.requestAuthorization(toShare: [], read: [type])
        }
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            // Include the preceding day so an episode crossing the range boundary is not cut.
            let predicate = HKQuery.predicateForSamples(withStart: window.start.addingTimeInterval(-24 * 3600), end: window.end)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 50_001,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, values, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: values?.compactMap { $0 as? HKCategorySample } ?? []) }
            }
            health.execute(query)
        }
        guard samples.count < 50_001 else { throw HealthSleepReadError.tooManySamples }
        let grouped = Dictionary(grouping: samples.filter { $0.endDate <= window.end }, by: HealthSourceIdentity.key)
        var sources: [HealthDataSource] = []
        let candidates = grouped.compactMap { id, values -> HealthSleepCandidate? in
            guard let first = values.first else { return nil }
            sources.append(HealthSourceIdentity.describe(first))
            let intervals = values.compactMap { sample -> HealthSleepInterval? in
                guard let stage = HealthOverviewStore.stage(sample.value), sample.endDate > sample.startDate,
                      sample.endDate.timeIntervalSince(sample.startDate) <= 24 * 3600 else { return nil }
                let zone = sample.metadata?[HKMetadataKeyTimeZone] as? String
                return HealthSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage,
                    timeZoneIdentifier: zone.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 })
            }
            return HealthSleepCandidate(sourceID: id, intervals: intervals, origin: HealthSourceIdentity.sleepOrigin(first))
        }
        return HealthSleepReadResult(candidates: candidates, sources: sources)
    }
}

#if DEBUG
/// Only enabled by an explicit UI-test launch argument; never writes samples to HealthKit.
@MainActor struct PreviewSystemSleepReader: HealthSleepReading {
    let isAvailable = true
    func read(_ window: HealthSleepWindow, requestAccess: Bool) async throws -> HealthSleepReadResult {
        try await Task.sleep(for: .milliseconds(150))
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-system-sleep-empty") { return HealthSleepReadResult(candidates: [], sources: []) }
        let calendar = Calendar.current
        var intervals: [HealthSleepInterval] = []
        for day in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -day - 1, to: calendar.startOfDay(for: window.end))!
            let start = date.addingTimeInterval(-3600)
            func sample(_ stage: SleepStage, _ from: Double, _ to: Double) -> HealthSleepInterval {
                HealthSleepInterval(id: HealthSleepNormalizer.stableID("test-only|\(date)|\(stage)|\(from)|\(to)"),
                    start: start.addingTimeInterval(from * 3600), end: start.addingTimeInterval(to * 3600), stage: stage,
                    timeZoneIdentifier: calendar.timeZone.identifier)
            }
            intervals.append(sample(.inBed, 0, 8))
            if arguments.contains("-system-sleep-bed-only") { continue }
            if arguments.contains("-system-sleep-unspecified") { intervals.append(sample(.unspecified, 0, 8)); continue }
            intervals += [sample(.awake, 0, 0.25), sample(.light, 0.25, 2), sample(.deep, 2, 4),
                          sample(.awake, 4, 4.25), sample(.rem, 4.25, 6), sample(.light, 6, 8)]
        }
        let origin = HealthSleepOrigin(sourceID: "system-sleep-ui-test", appName: "界面测试来源 · 非真实健康数据")
        return HealthSleepReadResult(candidates: [HealthSleepCandidate(sourceID: origin.sourceID, intervals: intervals, origin: origin)], sources: [])
    }
}
#endif

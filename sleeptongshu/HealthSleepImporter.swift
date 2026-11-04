import HealthKit
import CryptoKit
import SwiftData

struct HealthSleepInterval {
    let id: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
}

enum HealthSleepNormalizer {
    // Conflicting stages and missing intervals remain unknown.
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

struct HealthSleepCandidate {
    let sourceID: String
    let intervals: [HealthSleepInterval]
}

enum HealthSleepImporter {
    static var enabled: Bool { (Bundle.main.object(forInfoDictionaryKey: "SleepHealthKitEnabled") as? String)?.uppercased() == "YES" }

    static func night(_ end: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: end)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        return end < noon ? calendar.date(byAdding: .day, value: -1, to: day)! : day
    }

    static func automaticRecords(_ candidates: [HealthSleepCandidate], observations: [HealthObservation],
                                 sources: [HealthDataSource], calendar: Calendar = .current) throws -> [SleepPayload] {
        struct Night {
            let sourceID: String
            let segments: [SleepSegment]
            var detailed: Double { segments.filter { [.deep, .light, .rem].contains($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
            var asleep: Double { segments.filter { ![.awake, .unobserved].contains($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
        }
        var nights: [Date: [Night]] = [:]
        for candidate in candidates {
            let valid = candidate.intervals.filter { $0.end > $0.start && $0.end.timeIntervalSince($0.start) <= 24 * 3600 }
            for (day, intervals) in Dictionary(grouping: valid, by: { night($0.end, calendar: calendar) }) {
                let segments = HealthSleepNormalizer.segments(intervals)
                guard let start = segments.first?.start, let end = segments.last?.end,
                      end.timeIntervalSince(start) <= 24 * 3600 else { continue }
                let value = Night(sourceID: candidate.sourceID, segments: segments)
                if value.asleep > 0 { nights[day, default: []].append(value) }
            }
        }
        return try nights.keys.sorted().compactMap { day in
            // Keep one source per night; competing device stages must not be stitched together.
            guard let chosen = nights[day]?.sorted(by: { a, b in
                if a.detailed != b.detailed { return a.detailed > b.detailed }
                if a.asleep != b.asleep { return a.asleep > b.asleep }
                return a.sourceID < b.sourceID
            }).first, let start = chosen.segments.first?.start, let end = chosen.segments.last?.end else { return nil }
            func values(_ metric: HealthMetric) -> [HealthObservation] {
                let valid = observations.filter { sample in
                    sample.metric == metric && sample.sourceID == chosen.sourceID && metric.accepts(sample.value) &&
                    chosen.segments.contains { segment in
                        ![.awake, .unobserved].contains(segment.stage) && sample.start >= segment.start && sample.end <= segment.end
                    }
                }
                return Array(Dictionary(valid.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { $0.start < $1.start }
            }
            func average(_ metric: HealthMetric) -> Double? {
                let samples = values(metric)
                return samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
            }
            let key = "health-system-v1|\(Int(day.timeIntervalSince1970))"
            let label = sources.first { $0.id == chosen.sourceID }?.label ?? "系统健康"
            let payload = SleepPayload(id: HealthSleepNormalizer.stableID(key), start: start, end: end, source: .healthKit,
                                       segments: chosen.segments,
                                       heartSamples: values(.heart).map { HeartSample(id: HealthSleepNormalizer.stableID($0.id), date: $0.start, bpm: $0.value) },
                                       averageHeartRate: average(.heart), averageSpO2: average(.oxygen), averageRespiratoryRate: average(.respiration),
                                       note: "系统健康自动汇总。该晚采用：\(label)。体征只匹配这份睡眠的来源与设备；缺口不补成睡眠。",
                                       metadata: SleepMetadata(externalSource: "系统健康", externalID: key))
            try payload.validate()
            return payload
        }
    }

    @MainActor
    static func save(_ payloads: [SleepPayload], in context: ModelContext, calendar: Calendar = .current) throws {
        let records = try context.fetch(FetchDescriptor<SleepRecord>())
        for payload in payloads {
            try payload.validate()
            let previous = records.first { $0.id == payload.id || ($0.source == .healthKit && $0.metadata?.externalID == payload.metadata?.externalID) }
                ?? records.filter { $0.source == .healthKit && night($0.end, calendar: calendar) == night(payload.end, calendar: calendar) }
                    .sorted { $0.end > $1.end }.first
            if let previous { previous.replace(with: payload) }
            else { context.insert(SleepRecord(payload)) }
        }
        try context.save()
    }
}

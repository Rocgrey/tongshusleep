import Foundation
import SwiftData

enum SleepDataSource: String, Codable, CaseIterable {
    case sample, manual, healthKit, band, phone
    var label: String {
        switch self {
        case .sample: "示例数据"
        case .manual: "手动记录"
        case .healthKit: "系统健康"
        case .band: "穿戴设备"
        case .phone: "手机估算"
        }
    }
}

enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case awake, rem, light, deep, unspecified, unobserved
    var id: String { rawValue }
    var label: String {
        switch self { case .awake: "清醒"; case .rem: "快速眼动"; case .light: "浅睡"; case .deep: "深睡"; case .unspecified: "睡眠（未分期）"; case .unobserved: "未记录" }
    }
    var level: Int {
        switch self { case .awake: 3; case .rem: 2; case .light: 1; case .deep: 0; case .unspecified: 1; case .unobserved: -1 }
    }
}

struct SleepSegment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

struct HeartSample: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var bpm: Double
}

struct SleepPayload: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var source: SleepDataSource
    var segments: [SleepSegment]
    var heartSamples: [HeartSample]
    var averageHeartRate: Double?
    var averageSpO2: Double?
    var averageRespiratoryRate: Double?
    var note: String
    var metadata: SleepMetadata? = nil

    func validate() throws {
        guard end > start, end.timeIntervalSince(start) <= 24 * 3600, note.count <= 2000 else { throw SleepDataError.invalidRecord }
        var previousEnd = start
        for segment in segments {
            guard segment.start >= previousEnd, segment.end > segment.start, segment.end <= end else { throw SleepDataError.invalidRecord }
            previousEnd = segment.end
        }
        // A staged record must cover the full observed interval, without gaps.
        if let first = segments.first, let last = segments.last {
            guard first.start == start, last.end == end,
                  zip(segments, segments.dropFirst()).allSatisfy({ $0.end == $1.start }) else { throw SleepDataError.invalidRecord }
        }
        if let value = averageHeartRate, !value.isFinite || !(20...250).contains(value) { throw SleepDataError.invalidRecord }
        if let value = averageSpO2, !value.isFinite || !(0...100).contains(value) { throw SleepDataError.invalidRecord }
        if let value = averageRespiratoryRate, !value.isFinite || !(1...80).contains(value) { throw SleepDataError.invalidRecord }
        guard heartSamples.allSatisfy({ $0.date >= start && $0.date <= end && $0.bpm.isFinite && (20...250).contains($0.bpm) }) else { throw SleepDataError.invalidRecord }
        if let phone = metadata?.phone {
            guard phone.epochs.count <= 1441, phone.epochs == phone.epochs.sorted(by: { $0.date < $1.date }),
                  Set(phone.epochs.map(\.date)).count == phone.epochs.count,
                  phone.epochs.allSatisfy({ $0.date >= start && $0.date < end && $0.isValid }),
                  phone.estimatedMinutes.map({ (0...inBedMinutes).contains($0) }) ?? true,
                  phone.estimatedOnset.map({ $0 >= start && $0 < end }) ?? true else { throw SleepDataError.invalidRecord }
        }
    }
    private var inBedMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

enum SleepDataError: LocalizedError {
    case invalidRecord, unsupportedVersion, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "记录的时间、阶段或体征不完整，请检查数据。"
        case .unsupportedVersion: "此备份版本暂不支持。"
        case .tooLarge: "备份过大，请选择 10 MB 以内的文件。"
        }
    }
}

@Model
final class SleepRecord {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date
    var sourceRawValue: String
    var segmentsData: Data
    var heartSamplesData: Data
    var averageHeartRate: Double?
    var averageSpO2: Double?
    var averageRespiratoryRate: Double?
    var note: String
    var metadataData: Data?

    init(_ payload: SleepPayload) {
        id = payload.id
        start = payload.start
        end = payload.end
        sourceRawValue = payload.source.rawValue
        segmentsData = (try? JSONEncoder().encode(payload.segments)) ?? Data()
        heartSamplesData = (try? JSONEncoder().encode(payload.heartSamples)) ?? Data()
        averageHeartRate = payload.averageHeartRate
        averageSpO2 = payload.averageSpO2
        averageRespiratoryRate = payload.averageRespiratoryRate
        note = payload.note
        metadataData = payload.metadata.flatMap { try? JSONEncoder().encode($0) }
    }

    func replace(with payload: SleepPayload) {
        start = payload.start; end = payload.end; sourceRawValue = payload.source.rawValue
        segmentsData = (try? JSONEncoder().encode(payload.segments)) ?? Data()
        heartSamplesData = (try? JSONEncoder().encode(payload.heartSamples)) ?? Data()
        averageHeartRate = payload.averageHeartRate; averageSpO2 = payload.averageSpO2
        averageRespiratoryRate = payload.averageRespiratoryRate; note = payload.note
        metadataData = payload.metadata.flatMap { try? JSONEncoder().encode($0) }
    }

    var source: SleepDataSource { SleepDataSource(rawValue: sourceRawValue) ?? .manual }
    var seriesKey: String { metadata?.externalSource.map { "\(source.rawValue)|\($0)" } ?? source.rawValue }
    var seriesLabel: String { DevicePresentation.name(metadata?.externalSource ?? source.label) }
    var segments: [SleepSegment] { (try? JSONDecoder().decode([SleepSegment].self, from: segmentsData)) ?? [] }
    var heartSamples: [HeartSample] { (try? JSONDecoder().decode([HeartSample].self, from: heartSamplesData)) ?? [] }
    var metadata: SleepMetadata? { metadataData.flatMap { try? JSONDecoder().decode(SleepMetadata.self, from: $0) } }
    var inBedMinutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    var asleepMinutes: Int {
        if source == .phone { return metadata?.phone?.estimatedMinutes ?? 0 }
        return segments.isEmpty ? inBedMinutes : segments.filter { $0.stage != .awake && $0.stage != .unobserved }.map(\.minutes).reduce(0, +)
    }
    var hasStages: Bool { segments.contains { [.deep, .light, .rem].contains($0.stage) } }
    var hasSleepDuration: Bool { source != .phone || metadata?.phone?.estimatedMinutes != nil }
    func minutes(_ stage: SleepStage) -> Int { segments.filter { $0.stage == stage }.map(\.minutes).reduce(0, +) }
    var efficiency: Int? { !segments.isEmpty && !segments.contains { $0.stage == .unobserved } && inBedMinutes > 0 ? Int(Double(asleepMinutes) / Double(inBedMinutes) * 100) : nil }
    var deepShare: Int? { hasStages && !segments.contains { [.unobserved, .unspecified].contains($0.stage) } && asleepMinutes > 0 ? Int(Double(minutes(.deep)) / Double(asleepMinutes) * 100) : nil }
    var awakenings: Int? { hasStages && !segments.contains { $0.stage == .unobserved } ? segments.dropFirst().filter { $0.stage == .awake }.count : nil }
    var score: Int? {
        guard let efficiency else { return nil }
        let duration = min(100, Int(Double(asleepMinutes) / 480 * 100))
        return Int((Double(duration) * 0.6 + Double(efficiency) * 0.4).rounded())
    }
    var payload: SleepPayload {
        SleepPayload(id: id, start: start, end: end, source: source, segments: segments, heartSamples: heartSamples,
                     averageHeartRate: averageHeartRate, averageSpO2: averageSpO2,
                     averageRespiratoryRate: averageRespiratoryRate, note: note, metadata: metadata)
    }
    static func durationText(_ minutes: Int) -> String { "\(minutes / 60)小时\(minutes % 60)分" }
    static func clock(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
}

struct SleepBackup: Codable {
    var version = 2
    var exportedAt = Date()
    var records: [SleepPayload]
    static func decode(_ data: Data) throws -> SleepBackup {
        guard data.count <= 10_000_000 else { throw SleepDataError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Self.self, from: data)
        guard (1...2).contains(backup.version) else { throw SleepDataError.unsupportedVersion }
        try backup.records.forEach { try $0.validate() }
        return backup
    }
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// Transport boundaries use value types, so SwiftData objects never cross actors.
protocol SleepSyncClient: Sendable {
    func upload(_ records: [SleepPayload]) async throws
    func download(since: Date?) async throws -> [SleepPayload]
}

enum SampleSleepRecords {
    static func makeMonth(now: Date = .now, calendar: Calendar = .current) -> [SleepRecord] {
        (0..<30).map { offset in
            let todayEnd = calendar.date(byAdding: .minute, value: 7 * 60 + 54, to: calendar.startOfDay(for: now))!
            let shift = now < todayEnd ? 1 : 0
            let morning = calendar.date(byAdding: .day, value: -offset - shift, to: calendar.startOfDay(for: now))!
            let end = calendar.date(byAdding: .minute, value: 7 * 60 + 12 + (offset * 13 % 42), to: morning)!
            let pattern: [(SleepStage, Int)] = [
                (.light, 24), (.deep, 42), (.light, 38), (.rem, 25), (.awake, 4),
                (.light, 32), (.deep, 38), (.light, 46), (.rem, 35), (.awake, 8),
                (.light, 39), (.deep, 22), (.light, 33), (.rem, 47), (.light, 37 + offset * 7 % 47)
            ]
            let total = pattern.map(\.1).reduce(0, +)
            let start = end.addingTimeInterval(-Double(total) * 60)
            var cursor = start
            let segments = pattern.map { stage, minutes in
                let next = cursor.addingTimeInterval(Double(minutes) * 60)
                defer { cursor = next }
                return SleepSegment(stage: stage, start: cursor, end: next)
            }
            let heart = stride(from: 0, through: total, by: 15).enumerated().map { index, minute in
                HeartSample(date: start.addingTimeInterval(Double(minute) * 60), bpm: 56 + sin(Double(index) * 0.72) * 5 + Double(offset % 4))
            }
            return SleepRecord(SleepPayload(id: UUID(), start: start, end: end, source: .sample, segments: segments,
                heartSamples: heart, averageHeartRate: heart.map(\.bpm).reduce(0, +) / Double(heart.count),
                averageSpO2: 97 + Double(offset % 3) * 0.4, averageRespiratoryRate: 14.2 + Double(offset % 4) * 0.3, note: ""))
        }
    }
}

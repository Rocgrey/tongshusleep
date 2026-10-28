import Foundation
import CryptoKit

enum VeepooGatt {
    static let service = "F0020001-0451-4000-B000-000000000000"
    static let notify = "F0020002-0451-4000-B000-000000000000"
    static let write = "F0020003-0451-4000-B000-000000000000"
}

enum VeepooImportError: LocalizedError {
    case malformed, noSleep, incomplete, unavailable, failure(String)
    var errorDescription: String? {
        switch self {
        case .malformed: "厂商返回的时间或分期格式无法验证，未保存该记录。"
        case .noSleep: "本次没有取得可验证的睡眠记录。请先佩戴过夜，次日再同步。"
        case .incomplete: "厂商返回的跨段睡眠不完整，未将其当作完整一晚保存。"
        case .unavailable: "当前安装包未启用此设备的数据通道。"
        case .failure(let message): message
        }
    }
}

struct VeepooDecodedSleep {
    var records: [SleepPayload]
    var rejected: Int
    var vitals: [WearableVital] = []
}

enum VeepooSleepDecoder {
    private struct Slice {
        var start: Date
        var end: Date
        var segments: [SleepSegment]
        var previous: Bool
        var next: Bool
    }

    static func decode(_ result: [String: Any], calendar: Calendar = .current) throws -> VeepooDecodedSleep {
        guard let device = result["deviceID"] as? String, !device.isEmpty,
              let rows = result["sleeps"] as? [[String: Any]], rows.count <= 1000 else { throw VeepooImportError.malformed }
        var rejected = 0
        let slices = rows.compactMap { row -> Slice? in
            do { return try slice(row, calendar: calendar) }
            catch { rejected += 1; return nil }
        }.sorted { $0.start < $1.start }
        var joined: [Slice] = []
        var pending: Slice?
        for part in slices {
            if part.previous {
                guard var prior = pending, prior.next, prior.end == part.start,
                      part.end.timeIntervalSince(prior.start) <= 24 * 3600 else {
                    rejected += 1
                    if pending != nil { rejected += 1; pending = nil }
                    continue
                }
                prior.end = part.end
                prior.segments += part.segments
                prior.next = part.next
                pending = prior
            } else {
                if pending != nil { rejected += 1 }
                pending = part
            }
            if let complete = pending, !complete.next { joined.append(complete); pending = nil }
        }
        if pending != nil { rejected += 1 }
        let vitals = result["vitals"] as? [[String: Any]] ?? []
        guard vitals.count <= 100_000 else { throw VeepooImportError.malformed }
        let deviceHash = digest(device)
        let timestampedVitals = vitals.compactMap { sample -> (Date, [String: Any])? in
            guard let text = sample["time"] as? String, let time = date(text, calendar: calendar) else { return nil }
            return (time, sample)
        }
        var output: [UUID: SleepPayload] = [:]
        for night in joined {
            let asleep = night.segments.filter { $0.stage != .awake && $0.stage != .unobserved }
            var heart: [Date: Set<Double>] = [:], oxygen: [Date: Set<Double>] = [:], respiration: [Date: Set<Double>] = [:]
            for (date, sample) in timestampedVitals {
                guard asleep.contains(where: { date >= $0.start && date < $0.end }) else { continue }
                if let value = number(sample["heart"]), (20...250).contains(value) { heart[date, default: []].insert(value) }
                if let value = number(sample["oxygen"]), (1...100).contains(value) { oxygen[date, default: []].insert(value) }
                if let value = number(sample["respiration"]), (1...80).contains(value) { respiration[date, default: []].insert(value) }
            }
            // Conflicting measurements at one timestamp remain missing instead of being arbitrarily selected.
            let heartSamples = heart.compactMap { time, values in values.count == 1 ? HeartSample(date: time, bpm: values.first!) : nil }.sorted { $0.date < $1.date }
            let oxygenValues = oxygen.values.compactMap { $0.count == 1 ? $0.first : nil }
            let respiratoryValues = respiration.values.compactMap { $0.count == 1 ? $0.first : nil }
            let externalID = "veepoo:\(deviceHash):\(Int(night.start.timeIntervalSince1970))"
            let hash = digest(externalID)
            let id = UUID(uuidString: "\(hash.prefix(8))-\(hash.dropFirst(8).prefix(4))-\(hash.dropFirst(12).prefix(4))-\(hash.dropFirst(16).prefix(4))-\(hash.dropFirst(20).prefix(12))")!
            let payload = SleepPayload(id: id, start: night.start, end: night.end, source: .band,
                segments: coalesce(night.segments), heartSamples: heartSamples,
                averageHeartRate: average(heartSamples.map(\.bpm)), averageSpO2: average(oxygenValues),
                averageRespiratoryRate: average(respiratoryValues),
                note: "直接读取的设备睡眠；设备失眠标记按清醒展示。体征仅统计有记录的睡眠区间，缺失指标不作推算。",
                metadata: SleepMetadata(externalSource: "戒指 · \(deviceHash.prefix(6))", externalID: externalID))
            try payload.validate()
            output[id] = payload
        }
        return VeepooDecodedSleep(records: output.values.sorted { $0.start < $1.start }, rejected: rejected,
                                  vitals: try WearableVitalDecoder.decode(result.merging(["vitals": vitals]) { old, _ in old }, calendar: calendar))
    }

    private static func slice(_ row: [String: Any], calendar: Calendar) throws -> Slice {
        guard let startText = row["start"] as? String, let endText = row["end"] as? String,
              let start = date(startText, calendar: calendar), let end = date(endText, calendar: calendar),
              end > start, end.timeIntervalSince(start) <= 24 * 3600 else { throw VeepooImportError.malformed }
        let points: [(Int, SleepStage)]
        let step: TimeInterval
        switch row["format"] as? String {
        case "normal":
            guard let line = row["line"] as? String, !line.isEmpty, line.count <= 288 else { throw VeepooImportError.malformed }
            points = try line.enumerated().map { index, character in
                guard let stage = [Character("0"): SleepStage.light, "1": .deep, "2": .awake][character] else { throw VeepooImportError.malformed }
                return (index, stage)
            }
            step = 300
        case "accurate":
            guard number(row["pointSeconds"]) == 60,
                  let values = row["points"] as? [[String: Any]], !values.isEmpty, values.count <= 1440 else { throw VeepooImportError.malformed }
            points = try values.map { point in
                guard let index = number(point["index"]), index.rounded() == index, (0..<1440).contains(index),
                      let type = number(point["type"]), type.rounded() == type else { throw VeepooImportError.malformed }
                let stage: SleepStage
                switch Int(type) { case 0: stage = .deep; case 1: stage = .light; case 2: stage = .rem; case 3, 4: stage = .awake; default: stage = .unobserved }
                return (Int(index), stage)
            }.sorted { $0.0 < $1.0 }
            step = 60
        default: throw VeepooImportError.malformed
        }
        var segments: [SleepSegment] = []
        var cursor = start
        for (index, stage) in points {
            let lower = start.addingTimeInterval(Double(index) * step)
            guard lower >= cursor, lower < end else { throw VeepooImportError.malformed }
            if lower > cursor { segments.append(SleepSegment(stage: .unobserved, start: cursor, end: lower)) }
            let upper = min(end, lower.addingTimeInterval(step))
            segments.append(SleepSegment(stage: stage, start: lower, end: upper))
            cursor = upper
        }
        if cursor < end { segments.append(SleepSegment(stage: .unobserved, start: cursor, end: end)) }
        guard segments.contains(where: { [.deep, .light, .rem].contains($0.stage) }) else { throw VeepooImportError.malformed }
        return Slice(start: start, end: end, segments: segments, previous: number(row["previous"]) == 1, next: number(row["next"]) == 1)
    }

    private static func date(_ value: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        for format in ["yyyy/MM/dd HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: value), formatter.string(from: result) == value { return result }
        }
        return nil
    }
    private static func number(_ value: Any?) -> Double? {
        let result = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    private static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    private static func coalesce(_ segments: [SleepSegment]) -> [SleepSegment] {
        var result: [SleepSegment] = []
        for segment in segments {
            if let last = result.last, last.stage == segment.stage, last.end == segment.start { result[result.count - 1].end = segment.end }
            else { result.append(segment) }
        }
        return result
    }
}

import Foundation
import SwiftProtobuf
import SwiftData

/// Matches the manufacturer's SleepPreprocessor, not an on-device sleep algorithm.
struct BIOSleepAlgorithmRequest: Codable {
    var recordDate: Int
    var device_id: String
    var prevDay: String
    var nextDay: String
    var prevDayRri: [Int]
    var nextDayRri: [Int]

    static func make(_ report: WearableProbeReport) throws -> [Self] {
        guard WearableHistoryDecoder.isBIO(model: report.observedModel, firmware: report.observedFirmware),
              let deviceID = report.algorithmDeviceID, !deviceID.isEmpty, report.finishedAt != nil else { return [] }
        var days: [String: [Date: [String: Any]]] = [:]
        var rris: [String: [Date: [Int]]] = [:]
        for row in report.records {
            guard let bytes = row.protobufBase64.flatMap({ Data(base64Encoded: $0) }), let value = try? IW_HisData(serializedBytes: bytes) else { continue }
            if case .health(let h) = value.data, let date = WearableHistoryDecoder.date(h.timeStamp, model: report.observedModel, firmware: report.observedFirmware, now: report.finishedAt!) {
                let day = StepDates.format(date)
                var fields: [String: Any] = ["Q": value.seq, "T": [StepDates.calendar.component(.hour, from: date), StepDates.calendar.component(.minute, from: date)]]
                if h.hasSleepData {
                    var sleep: [String: Any] = ["a": h.sleepData.sleepData]
                    if h.sleepData.hasShutDown { sleep["s"] = h.sleepData.shutDown }
                    if h.sleepData.hasCharge { sleep["c"] = h.sleepData.charge }
                    fields["E"] = sleep
                }
                if h.hasPedoData { fields["P"] = ["s": h.pedoData.step, "c": h.pedoData.calorie, "d": h.pedoData.distance, "t": h.pedoData.type, "a": h.pedoData.state & 15] }
                if h.hasHrData {
                    fields["H"] = ["a": h.hrData.avgBpm, "n": h.hrData.minBpm, "x": h.hrData.maxBpm].filter { (1..<255).contains($0.value) }
                }
                if h.hasHrvData {
                    var values = ["s": Double(h.hrvData.sdnn)/10, "r": Double(h.hrvData.rmssd)/10,
                                  "p": Double(h.hrvData.pnn50)/10, "m": Double(h.hrvData.mean)/10].filter { $0.value > 0 }
                    // Follow the vendor's preprocessing fallback; this is not sleep staging.
                    if h.hrvData.fatigue > -1000, h.hrvData.fatigue <= 1000 {
                        let fatigue = h.hrvData.fatigue > 0 ? Int(h.hrvData.fatigue) : (h.hrvData.rmssd > 0 ? Int(log(Double(h.hrvData.rmssd)) * 20) : 0)
                        if fatigue > 0 { values["f"] = Double(fatigue) }
                        if !values.isEmpty { fields["V"] = values }
                    }
                }
                // Same timestamp from overlapping directories: never submit it twice.
                days[day, default: [:]][date] = fields
            } else if case .rri(let rri) = value.data,
                      let date = WearableHistoryDecoder.date(rri.timeStamp, model: report.observedModel, firmware: report.observedFirmware, now: report.finishedAt!) {
                rris[StepDates.format(date), default: [:]][date] = rri.rawData.flatMap { word in
                    [Int(Int16(bitPattern: UInt16((word >> 16) & 0xffff))), Int(Int16(bitPattern: UInt16(word & 0xffff)))]
                }
            }
        }
        func json(_ day: String) throws -> String {
            let values = (days[day] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
            return String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), as: UTF8.self)
        }
        func rri(_ day: String) -> [Int] { (rris[day] ?? [:]).sorted { $0.key < $1.key }.flatMap(\.value) }
        return try days.keys.sorted().suffix(3).compactMap { day in
            guard let date = StepDates.date(day), let recordDate = Int(day.replacingOccurrences(of: "-", with: "")) else { return nil }
            let previous = StepDates.format(StepDates.calendar.date(byAdding: .day, value: -1, to: date)!)
            guard days[previous] != nil else { return nil }
            return Self(recordDate: recordDate, device_id: deviceID, prevDay: try json(previous), nextDay: try json(day), prevDayRri: rri(previous), nextDayRri: rri(day))
        }
    }
}
struct BIOSleepAlgorithmResult: Codable {
    struct Section: Codable { var start: String; var end: String; var type: Int }
    var completed: Int
    var start_time: String
    var end_time: String
    var sections: [Section]
}
struct BIOSleepAlgorithmEnvelope: Decodable {
    var return_code: Int
    var message: String
    var result: BIOSleepAlgorithmResult?
}
enum BIOSleepResultAdapter {
    /// Reject overlaps/unknown codes. Uncovered intervals stay unknown, not awake.
    static func payload(_ result: BIOSleepAlgorithmResult, observation: SleepPayload) throws -> SleepPayload {
        guard observation.metadata?.bioNight != nil, (0...1).contains(result.completed), !result.sections.isEmpty else { throw SleepDataError.invalidRecord }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = StepDates.calendar; formatter.timeZone = StepDates.timeZone; formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        guard let start = formatter.date(from: result.start_time), let end = formatter.date(from: result.end_time), end > start,
              StepDates.format(end) == observation.metadata?.bioNight?.endDay, start >= observation.start.addingTimeInterval(-60),
              end <= observation.end.addingTimeInterval(60) else { throw SleepDataError.invalidRecord }
        var cursor = start; var segments: [SleepSegment] = []
        for section in result.sections {
            guard let a = formatter.date(from: section.start), let b = formatter.date(from: section.end), a >= cursor, b > a, b <= end,
                  let stage = [3: SleepStage.deep, 4: .light, 6: .awake, 7: .rem][section.type] else { throw SleepDataError.invalidRecord }
            if a > cursor { segments.append(.init(stage: .unobserved, start: cursor, end: a)) }
            segments.append(.init(stage: stage, start: a, end: b)); cursor = b
        }
        if cursor < end { segments.append(.init(stage: .unobserved, start: cursor, end: end)) }
        guard segments.contains(where: { $0.stage.isAsleep }) else { throw SleepDataError.invalidRecord }
        var payload = observation; payload.start = start; payload.end = end; payload.segments = segments
        payload.metadata?.bioNight?.algorithm = "vendor-cloud-sleep-v1"
        payload.metadata?.bioNight?.algorithmResult = result
        let samples = observation.metadata!.bioNight!.samples.filter { sample in segments.contains { $0.stage.isAsleep && sample.date >= $0.start && sample.date < $0.end } }
        func mean(_ kind: VitalKind) -> Double? { let values = samples.filter { $0.kind == kind }.map(\.value); return values.isEmpty ? nil : values.reduce(0,+)/Double(values.count) }
        payload.averageHeartRate = mean(.heart); payload.averageSpO2 = mean(.oxygen); payload.averageRespiratoryRate = mean(.respiration)
        payload.heartSamples = samples.filter { $0.kind == .heart }.map { HeartSample(date: $0.date, bpm: $0.value) }
        try payload.validate(); return payload
    }
}

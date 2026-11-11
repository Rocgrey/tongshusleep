import Foundation
import SwiftProtobuf

/// BIO9/103 reports use percentage battery and local-clock timestamps (80 = UTC+8).
/// Keep this firmware adaptation separate from the older SDK's 0...9 battery format.
enum WearableHistoryDecoder {
    static func isBIO(model: String?, firmware: String?) -> Bool {
        model?.uppercased() == "BIO9" && firmware?.hasPrefix("103.") == true
    }

    static func battery(_ raw: UInt32, model: String?, firmware: String?, at: Date = .now) -> DeviceBatteryReading? {
        if isBIO(model: model, firmware: firmware) {
            return DeviceBatteryReading(level: Int(raw), isPercentage: true, readAt: at)
        }
        return DeviceBatteryReading(gridLevel: Int(raw), maximum: 9, readAt: at)
    }

    /// The vendor documents wall-clock seconds, not UTC instants. Scope the observed
    /// timezone encoding to this firmware; never guess unknown models or use receive time.
    static func date(_ stamp: IW_DateTime, model: String?, firmware: String?, now: Date) -> Date? {
        guard isBIO(model: model, firmware: firmware), stamp.hasDateTime, stamp.hasTimeZone,
              stamp.timeZone == 80 else { return nil }
        let date = Date(timeIntervalSince1970: Double(stamp.dateTime.seconds) - 8 * 3600)
        guard date >= Date(timeIntervalSince1970: 946684800), date <= now.addingTimeInterval(300) else { return nil }
        return date
    }

    static func decode(_ report: WearableProbeReport, now: Date = .now) -> WearableDecodedHistory {
        var vitals: [String: WearableVital] = [:]
        var rows: [WearableHealthRow] = []
        var skippedTimes = 0
        for record in report.records where record.type == 0 {
            let value: IW_HisData?
            if let bytes = record.protobufBase64.flatMap({ Data(base64Encoded: $0) }) {
                value = try? IW_HisData(serializedBytes: bytes)
            } else { value = try? IW_HisData(jsonString: record.protobufJSON) }
            guard let value, case .health(let health) = value.data else { continue }
            guard let date = date(health.timeStamp, model: report.observedModel, firmware: report.observedFirmware, now: now) else {
                skippedTimes += 1; continue
            }
            var row = WearableHealthRow(sequence: record.sequence, date: date)
            func add(_ kind: VitalKind, _ number: Double?, label: String = "设备历史") {
                guard let number, kind.accepts(number) else { return }
                let vital = WearableVital(device: report.deviceKey, deviceLabel: report.deviceName,
                                          date: date, kind: kind, value: number, origin: label)
                vitals[vital.id] = vital
            }
            if health.hasHrData, health.hrData.hasAvgBpm,
               VitalKind.heart.accepts(Double(health.hrData.avgBpm)) {
                row.heart = Double(health.hrData.avgBpm); add(.heart, row.heart)
            }
            if health.hasBpBpmData, row.heart == nil, VitalKind.heart.accepts(Double(health.bpBpmData.bpm)) {
                row.heart = Double(health.bpBpmData.bpm); add(.heart, row.heart)
            }
            if health.hasBxoyData, VitalKind.oxygen.accepts(Double(health.bxoyData.agvOxy)) {
                row.oxygen = Double(health.bxoyData.agvOxy); add(.oxygen, row.oxygen)
            }
            if health.hasBpData {
                let high = Double(health.bpData.sbp), low = Double(health.bpData.dbp)
                if VitalKind.systolic.accepts(high), VitalKind.diastolic.accepts(low), high > low {
                    row.systolic = high; row.diastolic = low
                    add(.systolic, high); add(.diastolic, low)
                }
            }
            if health.hasHrvData {
                // Vendor SleepPreprocessor divides SDNN/RMSSD by ten. -1000 is missing.
                let hrv = health.hrvData
                let sdnn = Double(hrv.sdnn) / 10, rmssd = Double(hrv.rmssd) / 10
                if hrv.hasSdnn, sdnn.isFinite, sdnn > 0, sdnn < 2000 {
                    row.sdnn = sdnn; add(.hrv, sdnn, label: "设备历史 · SDNN（毫秒）")
                }
                if hrv.hasRmssd, rmssd.isFinite, rmssd > 0, rmssd < 2000 { row.rmssd = rmssd }
                let fatigue = Double(hrv.fatigue)
                if hrv.hasFatigue, fatigue.isFinite, (0...100).contains(fatigue) {
                    row.stress = 100 - fatigue
                    // Existing vitals omit zero stress; the report still preserves a real zero.
                    add(.stress, row.stress)
                }
            }
            if health.hasBreathData, VitalKind.respiration.accepts(Double(health.breathData.breathrate)) {
                row.respiration = Double(health.breathData.breathrate); add(.respiration, row.respiration)
            }
            if health.hasPedoData { row.steps = health.pedoData.step }
            if health.hasTemperatureData, health.temperatureData.type.rawValue == 1 {
                let temperature = Double(health.temperatureData.estiArm >> 16) / 100
                if (25...45).contains(temperature) { row.temperature = temperature }
            }
            rows.append(row)
        }
        // Sequence identifies transport packets; measurement time identifies local vitals.
        return WearableDecodedHistory(vitals: vitals.values.sorted { $0.date < $1.date },
                                      rows: rows.sorted { $0.date < $1.date }, skippedTimes: skippedTimes)
    }
}

struct WearableHealthRow: Identifiable {
    var sequence: UInt32
    var date: Date
    var heart: Double?
    var oxygen: Double?
    var systolic: Double?
    var diastolic: Double?
    var sdnn: Double?
    var rmssd: Double?
    var stress: Double?
    var respiration: Double?
    var temperature: Double?
    var steps: UInt32?
    var id: UInt32 { sequence }
}

struct WearableDecodedHistory {
    var vitals: [WearableVital]
    var rows: [WearableHealthRow]
    var skippedTimes: Int
}

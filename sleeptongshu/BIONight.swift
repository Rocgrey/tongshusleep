import Foundation
import SwiftData

/// A clock window with real measurements, not a claim that the wearer was asleep.
struct BIONight: Codable {
    var device: String
    var endDay: String
    var readAt: Date
    var samples: [WearableVital]
    var sleepInputMinutes: Int
    var timeZoneIdentifier = "Asia/Shanghai"
    var algorithm = "night-observation-v1"
    var algorithmResult: BIOSleepAlgorithmResult? = nil
    func mean(_ kind: VitalKind) -> Double? {
        let values = samples.filter { $0.kind == kind }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    func count(_ kind: VitalKind) -> Int { samples.filter { $0.kind == kind }.count }
    static func endDay(for date: Date) -> String? {
        let hour = StepDates.calendar.component(.hour, from: date)
        guard hour >= 18 || hour < 12 else { return nil }
        let day = hour >= 18 ? StepDates.calendar.date(byAdding: .day, value: 1, to: date)! : date
        return StepDates.format(day)
    }
    /// Use measured timestamps only; report reception is not measurement time.
    static func payloads(report: WearableProbeReport, history: WearableDecodedHistory) -> [SleepPayload] {
        guard WearableHistoryDecoder.isBIO(model: report.observedModel, firmware: report.observedFirmware), let readAt = report.finishedAt else { return [] }
        let groups = Dictionary(grouping: history.rows.filter { endDay(for: $0.date) != nil }) { endDay(for: $0.date)! }
        return groups.compactMap { day, rows in
            let samples = history.vitals.filter { endDay(for: $0.date) == day }
            let inputs = Set(rows.filter(\.hasSleepInput).map(\.date)).count
            guard !samples.isEmpty || inputs > 0, let start = rows.map(\.date).min(), let last = rows.map(\.date).max() else { return nil }
            let external = "bio-night|\(report.deviceKey)|\(day)"
            return SleepPayload(id: HealthSleepNormalizer.stableID(external), start: start, end: last.addingTimeInterval(60), source: .band,
                segments: [], heartSamples: [], averageHeartRate: nil, averageSpO2: nil, averageRespiratoryRate: nil, note: "",
                metadata: SleepMetadata(externalSource: report.deviceName, externalID: external,
                    bioNight: BIONight(device: report.deviceKey, endDay: day, readAt: readAt, samples: samples, sleepInputMinutes: inputs)))
        }.sorted { $0.end < $1.end }
    }
    @MainActor static func save(_ payloads: [SleepPayload], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<SleepRecord>())
        do {
            for incoming in payloads {
                try incoming.validate()
                if let old = existing.first(where: { $0.id == incoming.id }) {
                    guard let previous = old.metadata?.bioNight, let next = incoming.metadata?.bioNight,
                          previous.device == next.device, next.readAt >= previous.readAt else { continue }
                    // Bounded reads may return different pieces. Missing packets are not deletions.
                    var payload = incoming
                    var merged = Dictionary(previous.samples.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
                    next.samples.forEach { merged[$0.id] = $0 }
                    payload.metadata?.bioNight?.samples = merged.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
                    payload.metadata?.bioNight?.sleepInputMinutes = max(previous.sleepInputMinutes, next.sleepInputMinutes)
                    payload.start = min(old.start, incoming.start); payload.end = max(old.end, incoming.end)
                    payload.note = old.note
                    if let result = previous.algorithmResult {
                        payload = (try? BIOSleepResultAdapter.payload(result, observation: payload)) ?? old.payload
                    }
                    try payload.validate(); old.replace(with: payload)
                } else { context.insert(SleepRecord(incoming)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

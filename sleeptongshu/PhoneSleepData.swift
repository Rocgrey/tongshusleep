import Foundation

struct SleepMetadata: Codable {
    var phone: PhoneNight? = nil
    var externalSource: String? = nil
    var externalID: String? = nil
}

struct PhoneEpoch: Codable, Identifiable, Equatable {
    var date: Date
    var audioSeconds: Double = 0
    var soundDB: Double = -80
    var movement: Double? = nil
    var snoreSeconds: Double = 0
    var speechSeconds: Double = 0
    var id: Date { date }
    var isValid: Bool {
        audioSeconds.isFinite && (0...60).contains(audioSeconds) && soundDB.isFinite && (-160...0).contains(soundDB)
        && (movement.map { $0.isFinite && (0...20).contains($0) } ?? true)
        && snoreSeconds.isFinite && speechSeconds.isFinite && (0...60).contains(snoreSeconds) && (0...60).contains(speechSeconds)
    }
    // Quiet phone signals are only a heuristic, never a physiological sleep stage.
    var quiet: Bool { audioSeconds >= 40 && soundDB < -35 && (movement.map { $0 < 0.025 } ?? false) }
}

struct PhoneNight: Codable {
    var epochs: [PhoneEpoch]
    var estimatedOnset: Date?
    var estimatedMinutes: Int?
    var classifierAvailable: Bool
    var interrupted: Bool
    var algorithm = "quiet-window-v1"
    var snoreSeconds: Double { epochs.map(\.snoreSeconds).reduce(0, +) }
    var speechSeconds: Double { epochs.map(\.speechSeconds).reduce(0, +) }
    var coverageMinutes: Int { Int(epochs.map(\.audioSeconds).reduce(0, +) / 60) }
    var motionMinutes: Int { epochs.filter { ($0.movement ?? 0) >= 0.025 }.count }

    static func analyze(_ epochs: [PhoneEpoch], classifierAvailable: Bool, interrupted: Bool) -> PhoneNight {
        var run = 0
        var onset: Date?
        for (index, epoch) in epochs.enumerated() {
            let continuous = index == 0 || epoch.date.timeIntervalSince(epochs[index - 1].date) <= 61
            run = epoch.quiet ? (continuous ? run + 1 : 1) : 0
            if run == 15 { onset = epochs[index - 14].date; break }
        }
        let minutes = onset.map { start in Int(epochs.filter { $0.date >= start && $0.quiet }.map(\.audioSeconds).reduce(0, +) / 60) }
        return PhoneNight(epochs: epochs, estimatedOnset: onset, estimatedMinutes: minutes,
                          classifierAvailable: classifierAvailable, interrupted: interrupted)
    }

    static func preview(start: Date) -> PhoneNight {
        let epochs: [PhoneEpoch] = (0..<480).map { index in
            let db: Double = -48 + sin(Double(index) / 8) * 8 + (index % 69 < 4 ? 25.0 : 0.0)
            return PhoneEpoch(date: start.addingTimeInterval(Double(index) * 60), audioSeconds: 60,
                       soundDB: db,
                       movement: index < 18 || index % 69 < 4 ? 0.06 : 0.006,
                       snoreSeconds: index % 45 < 5 ? 12 : 0, speechSeconds: index % 115 == 0 ? 4 : 0)
        }
        return analyze(epochs, classifierAvailable: true, interrupted: false)
    }
}

struct PhoneCheckpoint: Codable {
    var id = UUID()
    var start: Date
    var end: Date
    var epochs: [PhoneEpoch]
    var classifierAvailable: Bool
    var interrupted = false
    var stoppedAt: Date? = nil
    var payload: SleepPayload {
        SleepPayload(id: id, start: start, end: end, source: .phone, segments: [], heartSamples: [],
                     averageHeartRate: nil, averageSpO2: nil, averageRespiratoryRate: nil,
                     note: interrupted ? "采集曾中断；报告仅包含成功保存的信号。" : "手机声音与体动的粗略估算，不提供生理睡眠分期。",
                     metadata: SleepMetadata(phone: PhoneNight.analyze(epochs, classifierAvailable: classifierAvailable, interrupted: interrupted)))
    }
}

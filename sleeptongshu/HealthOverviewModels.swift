import Foundation

enum HealthMetric: String, Codable, CaseIterable, Identifiable {
    case sleep, restingHeart, hrv, heart, oxygen, respiration, steps, exercise, vo2, systolic, diastolic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleep: "睡眠"; case .restingHeart: "静息心率"; case .hrv: "HRV"; case .heart: "心率"
        case .oxygen: "血氧"; case .respiration: "呼吸率"; case .steps: "步数"; case .exercise: "运动时间"
        case .vo2: "最大摄氧量"; case .systolic: "血压高压"; case .diastolic: "血压低压"
        }
    }
    var unit: String {
        switch self {
        case .sleep: "小时"; case .restingHeart, .heart, .respiration: "次/分"; case .hrv: "毫秒"
        case .oxygen: "%"; case .steps: "步"; case .exercise: "分钟"; case .vo2: "mL/kg/min"
        case .systolic, .diastolic: "mmHg"
        }
    }
    var symbol: String {
        switch self {
        case .sleep: "moon.fill"; case .hrv: "waveform.path.ecg"; case .heart, .restingHeart: "heart.fill"
        case .oxygen: "drop.fill"; case .respiration: "lungs.fill"; case .steps: "figure.walk"
        case .exercise: "figure.run"; case .vo2: "figure.outdoor.cycle"; case .systolic, .diastolic: "gauge.with.dots.needle.50percent"
        }
    }
    var isCumulative: Bool { self == .steps || self == .exercise }
    func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .sleep: return value > 0 && value <= 24
        case .heart, .restingHeart: return (20...250).contains(value)
        case .hrv: return value > 0 && value <= 500
        case .oxygen: return value > 0 && value <= 100
        case .respiration: return value > 0 && value <= 80
        case .steps: return value >= 0 && value <= 200_000
        case .exercise: return value >= 0 && value <= 1440
        case .vo2: return (10...100).contains(value)
        case .systolic: return (40...300).contains(value)
        case .diastolic: return (20...200).contains(value)
        }
    }
    var explanation: String {
        switch self {
        case .sleep: "系统健康中的睡着时长。每晚自动采用一份分期较完整的记录，不把不同设备的同一晚相加；清醒和仅卧床不计入。成人通常建议每晚至少 7 小时，需结合个人情况。"
        case .restingHeart: "身体安静时的心跳速度。成人常见参考约 60～100 次/分，规律运动者可能更低；与自己长期的变化比较更有用。"
        case .hrv: "相邻心跳间隔变化的大小。这里仅使用系统健康中以毫秒记录的 SDNN，不与设备其他 HRV 分数混用。受测量时段、姿势和呼吸影响，没有适合所有人的单一及格值。"
        case .heart: "读取到的心率样本，每日值为样本中位数，不是全天连续平均，也不等于静息心率。运动会使数值升高，应结合当时活动判断。"
        case .oxygen: "血液携氧情况的设备估计值。健康成人海平面常见约 95%～100%；高海拔、佩戴和设备误差会影响结果。身体不舒服时不能只看设备数值。"
        case .respiration: "每分钟呼吸次数。成人安静时常见约 12～20 次/分，睡眠和活动时可能不同；这里没有把所有记录认定为睡眠测量。"
        case .steps: "直接读取系统健康提供的每日步数统计，不把设备原始记录逐条相加。空白表示没读到记录，不按 0 步算。步数没有人人适用的目标，可从个人习惯逐步增加。"
        case .exercise: "系统健康提供的每日运动分钟统计。成年人一般可参考每周 150～300 分钟中等强度活动；设备的运动分钟和这个标准不完全等同。"
        case .vo2: "最大摄氧量反映运动时利用氧气的能力，单位 mL/kg/min。穿戴设备通常给出估计值，受测量条件影响；不能仅凭这一项评价整体健康。"
        case .systolic: "心脏收缩时的血压。这里只显示系统健康已有的高压样本；不能替代规范的袖带测量，也不能只凭一天的读数诊断。"
        case .diastolic: "心脏放松时的血压。这里只显示系统健康已有的低压样本；高压和低压分别统计，不能把不同时间的两项拼成一次测量。"
        }
    }
}

struct HealthDataSource: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var deviceName: String
    var hardwareIdentified: Bool
    var label: String { "\(appName) · \(deviceName)" }
    var selectionLabel: String { "\(label) · \(id.prefix(4))" }
}

struct HealthObservation: Codable, Identifiable, Equatable {
    var id: String
    var metric: HealthMetric
    var sourceID: String
    var start: Date
    var end: Date
    var value: Double
}

struct HealthDay: Identifiable, Equatable {
    var date: Date
    var value: Double
    var count: Int
    var id: Date { date }
}

enum HealthReferenceSex: String, Codable, CaseIterable {
    case unspecified, female, male
    var title: String {
        switch self { case .unspecified: "未选择"; case .female: "女性参考组"; case .male: "男性参考组" }
    }
}

struct HealthOverviewSnapshot: Codable {
    var version = 1
    var readAt: Date
    var sources: [HealthDataSource]
    var observations: [HealthObservation]
    var age: Int?
    var referenceSex: HealthReferenceSex = .unspecified
    var truncatedMetrics: [HealthMetric] = []
    var sleepRecords: [SleepPayload]? = nil
    var notices: [String]? = nil
}

struct HealthOverviewArchive: Codable {
    var snapshot: HealthOverviewSnapshot?
    // Kept decodable for 0.2.8 backups; old per-metric selections are no longer applied.
    var selections: [String: String] = [:]
}

enum HealthOverviewAnalysis {
    private struct Reading: Hashable {
        let start: Date
        let end: Date
        let value: Double
    }
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let index = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[index - 1] + sorted[index]) / 2 : sorted[index]
    }

    static func hasNewData(previous: HealthOverviewSnapshot?, next: HealthOverviewSnapshot) -> Bool {
        guard let previous else { return !next.observations.isEmpty }
        let old = Dictionary(previous.observations.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return next.observations.contains { observation in
            guard let existing = old[observation.id] else { return true }
            return existing.metric != observation.metric || existing.value != observation.value ||
                existing.start != observation.start || existing.end != observation.end
        }
    }

    static func daily(_ observations: [HealthObservation], metric: HealthMetric, calendar: Calendar = .current) -> [HealthDay] {
        let valid = Dictionary(observations.filter { $0.metric == metric && $0.end >= $0.start && metric.accepts($0.value) }
            .map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        if metric.isCumulative, Set(valid.map(\.sourceID)).count > 1 { return [] }
        var excludedDays = Set<Date>()
        if metric.isCumulative {
            for entry in valid {
                let start = calendar.startOfDay(for: entry.start)
                let next = calendar.date(byAdding: .day, value: 1, to: start)!
                if entry.end > next {
                    // Never spread a cumulative sample across days by an invented proportion.
                    var day = start
                    while day < entry.end {
                        excludedDays.insert(day)
                        guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                        day = following
                    }
                }
            }
        }
        let groups = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.start) }
        return groups.compactMap { date, values in
            guard !excludedDays.contains(date) else { return nil }
            if metric.isCumulative {
                let sorted = values.sorted { $0.start < $1.start }
                var end: Date?
                for value in sorted {
                    if let end, value.start < end { return nil }
                    end = max(end ?? value.end, value.end)
                }
            }
            let readings = Set(values.map { Reading(start: $0.start, end: $0.end, value: $0.value) })
            let value: Double
            if metric.isCumulative { value = values.reduce(0) { $0 + $1.value } }
            else if metric == .sleep { value = values.map(\.value).max()! }
            else { value = median(readings.map(\.value))! }
            guard metric.accepts(value) else { return nil }
            return HealthDay(date: date, value: value, count: metric.isCumulative ? values.count : readings.count)
        }.sorted { $0.date < $1.date }
    }

    static func window(_ days: [HealthDay], ending end: Date, count: Int, calendar: Calendar = .current) -> [HealthDay] {
        let boundary = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -count, to: boundary)!
        return days.filter { $0.date >= start && $0.date < boundary }
    }

    // Compare disjoint windows; a device change can also change the observed values.
    static func change(_ days: [HealthDay], now: Date, calendar: Calendar = .current) -> (recent: Double, previous: Double)? {
        let recent = window(days, ending: now, count: 14, calendar: calendar)
        let previousEnd = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now))!
        let previous = window(days, ending: previousEnd, count: 14, calendar: calendar)
        guard recent.count >= 7, previous.count >= 7,
              let recentValue = median(recent.map(\.value)), let previousValue = median(previous.map(\.value)) else { return nil }
        return (recentValue, previousValue)
    }

    static func sleepObservations(_ intervals: [HealthSleepInterval], sourceID: String, calendar: Calendar = .current) -> [HealthObservation] {
        // Group at local noon, union stages before counting so duplicate exports do not inflate sleep.
        let groups = Dictionary(grouping: intervals) { HealthSleepImporter.night($0.end, calendar: calendar) }
        return groups.compactMap { day, entries in
            let segments = HealthSleepNormalizer.segments(entries)
            let asleep = segments.filter { ![.awake, .unobserved].contains($0.stage) }
            let hours = asleep.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
            guard HealthMetric.sleep.accepts(hours) else { return nil }
            let date = calendar.date(byAdding: .day, value: 1, to: day)!
            return HealthObservation(id: "sleep|\(sourceID)|\(day.timeIntervalSince1970)", metric: .sleep, sourceID: sourceID,
                                     start: date, end: date, value: hours)
        }.sorted { $0.start < $1.start }
    }
}

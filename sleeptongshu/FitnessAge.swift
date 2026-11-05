import Foundation

struct FitnessAgeRequirement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let satisfied: Bool
}

struct FitnessAgeEstimate: Equatable {
    enum Boundary { case within, younger, older }
    var years: Double
    var boundary: Boundary
    var display: String {
        switch boundary {
        case .younger: "≤25"
        case .older: "≥75"
        case .within: "约\(Int((years / 5).rounded()) * 5)"
        }
    }
}

struct ExploratoryAgeSignal: Identifiable, Equatable {
    var id: String
    var title: String
    var value: Double
    var unit: String
    var score: Double
}

struct ExploratoryAgeEstimate: Equatable {
    var age: Int
    var actualAge: Int
    var score: Double
    var date: Date
    var signals: [ExploratoryAgeSignal]
}

enum FitnessAge {
    static let algorithmVersion = "FRIEND-median-v2"
    static let ageKnots = [24.5, 34.5, 44.5, 54.5, 64.5, 74.5]
    static let exploratoryExplanation = "探索性健康年龄是本 App 的自定义演示算法，不是医学模型，也没有经过人群或临床验证。它只用于观察新数据带来的短期变化，不表示身体真的变老或变年轻。\n\n取最近 7 个完整自然日内，至少有两类数据的最新同一天。睡眠以 7.5 小时为中心，越偏离分数越低；步数按 8,000 步映射；静息心率按 50 次/分起、每高 1 次扣 1.2 分；HRV 与该日期前 30 天个人日中位数比较，每高/低 1% 加/减 1 分。各项分数限制在 20～80，再取平均。平均分每偏离 50 分 10 分，估算年龄相对实际年龄调整 1 岁，最多上下 3 岁。至少需要两项有效指标。\n\n这些阈值和换算比例只是为了让图表随可用数据变化，未经验证，不适合比较不同人，也不用于诊断或治疗。设备、佩戴、运动、采样频率和缺失都会改变结果。普通心率不当作静息心率；HRV 没有个人前 30 天基线时不计入。"

    static func exploratory(_ days: [HealthMetric: [HealthDay]], actualAge: Int?, now: Date,
                            calendar: Calendar = .current) -> ExploratoryAgeEstimate? {
        guard let actualAge, (18...100).contains(actualAge) else { return nil }
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -7, to: today)!
        let metrics: [HealthMetric] = [.sleep, .steps, .restingHeart, .hrv]
        let values = Dictionary(uniqueKeysWithValues: metrics.map { metric in
            (metric, Dictionary((days[metric] ?? []).map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { _, last in last }))
        })
        let candidateDates = Set(values.values.flatMap(\.keys)).filter { $0 >= firstDay && $0 < today }.sorted(by: >)
        guard let date = candidateDates.first(where: { day in metrics.filter { values[$0]?[day] != nil }.count >= 2 }) else { return nil }
        var signals: [ExploratoryAgeSignal] = []
        if let value = values[.sleep]?[date] {
            signals.append(.init(id: "sleep", title: "睡眠", value: value, unit: "小时",
                                 score: clamp(100 - abs(value - 7.5) * 18, 20...80)))
        }
        if let value = values[.steps]?[date] {
            signals.append(.init(id: "steps", title: "步数", value: value, unit: "步",
                                 score: clamp(value / 8_000 * 80, 20...80)))
        }
        if let value = values[.restingHeart]?[date] {
            signals.append(.init(id: "restingHeart", title: "静息心率", value: value, unit: "次/分",
                                 score: clamp(100 - max(0, value - 50) * 1.2, 20...80)))
        }
        if let value = values[.hrv]?[date] {
            let baselineStart = calendar.date(byAdding: .day, value: -30, to: date)!
            let baseline = (days[.hrv] ?? []).filter { $0.date >= baselineStart && $0.date < date }.map(\.value)
            if let median = HealthOverviewAnalysis.median(baseline), median > 0 {
                signals.append(.init(id: "hrv", title: "HRV", value: value, unit: "毫秒",
                                     score: clamp(50 + (value / median - 1) * 100, 20...80)))
            }
        }
        guard signals.count >= 2 else { return nil }
        let score = signals.map(\.score).reduce(0, +) / Double(signals.count)
        let adjustment = min(3, max(-3, Int(((50 - score) / 10).rounded())))
        return ExploratoryAgeEstimate(age: max(18, actualAge + adjustment), actualAge: actualAge,
                                      score: score, date: date, signals: signals)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func requirements(_ days: [HealthDay], now: Date, age: Int?, sex: HealthReferenceSex,
                             calendar: Calendar = .current) -> [FitnessAgeRequirement] {
        let recent = HealthOverviewAnalysis.window(days, ending: now, count: 30, calendar: calendar)
        let count = Set(recent.filter { HealthMetric.vo2.accepts($0.value) }.map { calendar.startOfDay(for: $0.date) }).count
        return [
            FitnessAgeRequirement(id: "age", title: "实际年龄", detail: age.map { (20...79).contains($0) ? "已读取 \($0) 岁" : "当前参考范围为 20～79 岁" } ?? "未读到出生日期，可在健康设置中补充年龄", satisfied: age.map { (20...79).contains($0) } ?? false),
            FitnessAgeRequirement(id: "sex", title: "参考分组", detail: sex == .unspecified ? "未读到参考资料，可在健康设置中补充" : sex.title, satisfied: sex != .unspecified),
            FitnessAgeRequirement(id: "vo2", title: "最大摄氧量", detail: count >= 3 ? "近 30 天有 \(count) 天记录" : "近 30 天有 \(count) 天，还需 \(3 - count) 天；今天不计入", satisfied: count >= 3)
        ]
    }
    // FRIEND 2015, Table 3: measured treadmill VO2max, 50th percentile. Not Cooper Clinic estimates.
    static func reference(_ sex: HealthReferenceSex) -> [Double]? {
        switch sex {
        case .male: [48.0, 42.4, 37.8, 32.6, 28.2, 24.4]
        case .female: [37.6, 30.2, 26.7, 23.4, 20.0, 18.3]
        case .unspecified: nil
        }
    }
    static func estimate(vo2: Double, age: Int?, sex: HealthReferenceSex) -> FitnessAgeEstimate? {
        guard let age, (20...79).contains(age), HealthMetric.vo2.accepts(vo2), let values = reference(sex) else { return nil }
        if vo2 >= values[0] { return FitnessAgeEstimate(years: ageKnots[0], boundary: .younger) }
        if vo2 <= values[5] { return FitnessAgeEstimate(years: ageKnots[5], boundary: .older) }
        for index in 0..<5 where vo2 <= values[index] && vo2 >= values[index + 1] {
            let fraction = (values[index] - vo2) / (values[index] - values[index + 1])
            return FitnessAgeEstimate(years: ageKnots[index] + 10 * fraction, boundary: .within)
        }
        return nil
    }

    static func current(_ days: [HealthDay], now: Date, age: Int?, sex: HealthReferenceSex, calendar: Calendar = .current) -> (estimate: FitnessAgeEstimate, vo2: Double, count: Int)? {
        let recent = HealthOverviewAnalysis.window(days, ending: now, count: 30, calendar: calendar)
        guard recent.count >= 3, let value = HealthOverviewAnalysis.median(recent.map(\.value)),
              let estimate = estimate(vo2: value, age: age, sex: sex) else { return nil }
        return (estimate, value, recent.count)
    }

    static func change(_ days: [HealthDay], now: Date, calendar: Calendar = .current) -> Double? {
        let recent = HealthOverviewAnalysis.window(days, ending: now, count: 30, calendar: calendar)
        let previousEnd = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now))!
        let previous = HealthOverviewAnalysis.window(days, ending: previousEnd, count: 30, calendar: calendar)
        guard recent.count >= 3, previous.count >= 3,
              let current = HealthOverviewAnalysis.median(recent.map(\.value)),
              let prior = HealthOverviewAnalysis.median(previous.map(\.value)), prior > 0 else { return nil }
        return (current - prior) / prior * 100
    }

    static let explanation = "这里的身体年龄参考，仅指心肺能力在研究参考人群中接近哪个年龄段，不是全身的生物年龄。\n\n使用系统健康中最近 30 个完整自然日的最大摄氧量；先取每日中位数，再取这些日值的中位数，至少需要 3 个不同日期。按参考分组，把数值与 FRIEND 研究的各年龄段中位数比较，在相邻年龄段中点之间按直线换算。显示到约 5 岁，超出表格两端只显示 ≤25 或 ≥75，不向外推算。\n\n需要 20～79 岁的实际年龄和参考分组。研究使用的是美国无心血管疾病成人的跑台运动测试，不代表所有人群；穿戴设备估计的最大摄氧量也不等同于实验室实测。换算成参考年龄是本 App 的展示方法，并非该研究验证过的年龄预测模型。\n\n睡眠、HRV、血氧等在页面单独呈现，没有随意加减成几岁。身体年龄参考低，不代表没有疾病。\n\n长期变化显示最近 30 天相对前 30 天最大摄氧量中位数的变化百分比，两段各至少 3 天；设备或测量方式改变也会影响比较。不是每年老几岁，也不作为衰老速度。"
    static let referenceTitle = "Reference Standards for Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise National Database"
    static let referenceAuthors = "Leonard A. Kaminsky、Ross Arena、Jonathan Myers，2015，表 3"
}

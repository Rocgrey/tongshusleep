import Foundation

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

enum FitnessAge {
    static let algorithmVersion = "FRIEND-median-v2"
    static let ageKnots = [24.5, 34.5, 44.5, 54.5, 64.5, 74.5]
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

import Foundation

extension VitalKind {
    var meaning: String {
        switch self {
        case .heart: "一分钟心脏跳了多少次。活动、情绪和睡眠都会让心率变化。"
        case .oxygen: "血液带氧情况的一个参考。佩戴太松、手冷或活动时，读数可能不准。"
        case .respiration: "一分钟呼吸了多少次。运动、紧张和睡眠时，速度会不同。"
        case .systolic: "心脏把血液送出去时的压力，也就是血压中的较大数字。"
        case .diastolic: "两次心跳之间的血压，也就是血压中的较小数字。"
        case .hrv: "相邻两次心跳之间，间隔时间有多大变化。它和身体恢复、紧张程度有关，不是心率。"
        case .stress: "设备根据身体信号给出的压力参考，不等于你的真实心情。"
        default: "此项目已不再展示。"
        }
    }

    var referenceText: String {
        switch self {
        case .heart: "成人安静清醒时：60–100 次/分"
        case .oxygen: "一般参考：95%–100%"
        case .respiration: "成人安静清醒时：12–18 次/分"
        case .systolic: "成人安静时一般参考：90–120 mmHg"
        case .diastolic: "成人安静时一般参考：60–80 mmHg"
        case .hrv: "没有适用于所有人的统一正常值"
        case .stress: "暂不设置正常范围"
        default: "暂无参考"
        }
    }

    var referenceNote: String {
        switch self {
        case .heart: "睡觉时可能更低，长期运动的人也可能低于 60。这里的记录可能包含活动和睡眠，不能只凭一个数字判断。"
        case .oxygen: "高海拔或已有肺部疾病时，适用范围可能不同。读数偏低先确认佩戴，再用可靠设备复测；反复偏低或不舒服时请咨询医生。"
        case .respiration: "这是安静清醒时的一般参考，不能直接当作睡眠标准。呼吸有困难时，应及时就医。"
        case .systolic, .diastolic: "血压要把高压和低压一起看。设备读数只供观察，不能替代上臂式血压计，也不能用来决定吃药或停药。"
        case .hrv: "这台设备的算法和单位还没有确认，因此只保留设备给出的数字，不写成毫秒。请和自己同一设备的多天记录比较，不和别人比高低。"
        case .stress: "目前还没有确认设备怎样计分、满分多少。这里只看个人变化，不按数字判断焦虑程度或身体是否健康。"
        default: ""
        }
    }

    var referenceSource: String {
        switch self {
        case .heart, .respiration, .systolic, .diastolic: "《生命体征》（译名） · Linda J. Vorvick 等修订"
        case .oxygen: "《血氧测量》（译名） · MedlinePlus 编辑团队"
        default: "参考方式：同一设备、相近状态下，观察自己的多天变化。"
        }
    }

    // Only oxygen has a general comparison band here; resting ranges do not classify mixed activity/sleep samples.
    var chartReference: ClosedRange<Double>? { self == .oxygen ? 95...100 : nil }
}

struct VitalDay: Identifiable {
    let date: Date
    let minimum: Double
    let maximum: Double
    let mean: Double
    let count: Int
    var id: Date { date }
}

struct VitalBucket: Identifiable {
    let id: Int
    let label: String
    let count: Int
}

enum VitalInsights {
    static func daily(_ samples: [WearableVital], calendar: Calendar = .current) -> [VitalDay] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }.map { date, values in
            let numbers = values.map(\.value)
            return VitalDay(date: date, minimum: numbers.min()!, maximum: numbers.max()!,
                            mean: numbers.reduce(0, +) / Double(numbers.count), count: numbers.count)
        }.sorted { $0.date < $1.date }
    }

    static func buckets(_ samples: [WearableVital]) -> [VitalBucket] {
        guard let low = samples.map(\.value).min(), let high = samples.map(\.value).max() else { return [] }
        guard low != high else { return [VitalBucket(id: 0, label: number(low), count: samples.count)] }
        let width = (high - low) / 4
        let decimal = width < 1 ? 2 : 1
        return (0..<4).map { index in
            let start = low + Double(index) * width
            let end = index == 3 ? high : low + Double(index + 1) * width
            let count = samples.filter { $0.value >= start && (index == 3 ? $0.value <= end : $0.value < end) }.count
            return VitalBucket(id: index, label: "\(number(start, decimals: decimal))–\(number(end, decimals: decimal))", count: count)
        }
    }

    static func number(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)))
    }
}

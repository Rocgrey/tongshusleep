import SwiftUI

struct SleepReference: Identifiable {
    let title: String
    let author: String
    var id: String { title + author }
}

enum SleepMetricGuide {
    static let stagesReference = SleepReference(title: "《睡眠阶段：一晚的睡眠是怎样变化的？》（译名）", author: "Eric Suni")
    static let deepReference = SleepReference(title: "《你需要多少深睡？》（译名）", author: "Danielle Pacheco")
    static let physiologyReference = SleepReference(title: "《睡眠的各个阶段》（译名）", author: "美国国家心肺血液研究所")
    static let qualityReference = SleepReference(title: "《哪些原因会让睡眠质量变差？》（译名）", author: "Eric Suni")
    static let consensusReference = SleepReference(title: "《国家睡眠基金会睡眠质量建议：第一份报告》（译名）", author: "Maurice Ohayon 等，2017")

    static func efficiency(_ record: SleepRecord) -> MetricHelp {
        MetricHelp(title: "睡眠效率怎么算？", body: "睡眠效率，就是这段记录里有多少时间真正睡着了。\n\n计算：睡着的时间 ÷ 整段记录的时间 × 100%。显示整数，小数不计。\n本晚：\(SleepRecord.durationText(record.asleepMinutes)) ÷ \(SleepRecord.durationText(record.inBedMinutes))\(record.efficiency.map { " ≈ \($0)%" } ?? "；资料不完整，暂不计算")。\n\n成人通常可参考 85% 及以上。比如躺床 8 小时、睡着 7 小时，效率约为 87%。但时间睡得太短，即使效率高，也可能没休息够。\n\n这个参考通常把躺床但还没睡着的时间也算进去。设备可能在你睡着后才开始记录，让结果看起来偏高。请结合睡眠时长和白天精神状态一起看。缺少一段记录时，不给出结果。", references: [qualityReference, consensusReference])
    }

    static func score(_ record: SleepRecord) -> MetricHelp {
        let duration = min(100, Int(Double(record.asleepMinutes) / 480 * 100))
        return MetricHelp(title: "睡眠参考分怎么算？", body: "这是 App 自己计算的 0–100 分，用来看看自己最近几晚有没有变化。它不是医生的评价，也不是设备的原始评分。\n\n先算时长分：睡眠分钟数 ÷ 480 × 100，小数不计，最高 100 分。睡够 8 小时，时长分就是 100 分。\n\n再算总分：时长分 × 60% + 睡眠效率 × 40%，最后四舍五入。\n\n\(record.score.map { "本晚：\(duration) × 60% + \(record.efficiency ?? 0) × 40% = \($0) 分。" } ?? "本晚资料不够，暂不打分。")\n\n60% 和 40% 是 App 的设定，没有医学上的及格线。深睡、血氧、打鼾等没有参与计分，所以分高不一定代表睡得好。8 小时是计分用的固定时间，修改睡眠目标不会改变这个算法。\n\n多看看连续几晚的变化和醒来后的感受，不用为一晚的分数担心。", references: [])
    }

    static func stages(_ record: SleepRecord) -> MetricHelp {
        let source: String
        switch record.source {
        case .band: source = "本晚来自戒指，色条表示设备记录的各段睡眠。"
        case .healthKit: source = "本晚来自系统健康，色条表示所选来源记录的各段睡眠。"
        case .sample: source = "当前选中的是预览记录，可在本地数据中移除；它不会与真实记录合并统计。"
        case .manual: source = "本晚是手动记录，没有设备资料时不区分睡眠阶段。"
        case .phone: source = "本晚由手机估算；声音和体动不能分辨深睡、浅睡或快速眼动。"
        }
        return MetricHelp(title: "关于睡眠阶段", body: "\(source)\n\n一晚中，浅睡、深睡和快速眼动会轮流出现。深睡一般在前半夜更多，快速眼动一般在后半夜更多。\n\n占比，就是某个阶段在睡着的时间里占了多少。例如睡了 8 小时，其中深睡 1 小时，深睡占比约为 12%。清醒的时间不算在睡眠里。\n\n缺少记录或有一段睡眠没有区分阶段时，暂不显示比例。设备是根据身体信号估算，可能与医院检查有差别；年龄、身体情况和设备算法也会影响结果。", references: [physiologyReference, stagesReference])
    }

    static func referenceText(_ stage: SleepStage) -> String {
        switch stage {
        case .deep: "成人参考约 10%–20%"
        case .light: "成人通常约一半或更多"
        case .rem: "成人参考约 20%–25%"
        default: "不计入睡眠占比"
        }
    }

    static func stage(_ stage: SleepStage, record: SleepRecord) -> MetricHelp {
        let meaning: String
        let references: [SleepReference]
        switch stage {
        case .deep:
            meaning = "深睡时通常睡得更沉，不容易被叫醒，身体和大脑在休息、恢复。一般前半夜较多。\n\n成人常见参考约 10%–20%。随着年龄增长，深睡可能减少。不是越多越好，也不必每晚都达到某个数字。"
            references = [deepReference, physiologyReference]
        case .light:
            meaning = "浅睡是正常睡眠的一部分，包括刚睡着和睡得比较平稳的时间。浅睡多，不等于没休息好。\n\n成人通常约一半或更多。不同年龄和设备的结果会不同，没有人人适用的及格范围。更有用的是看自己的多晚变化和白天是否有精神。"
            references = [stagesReference, physiologyReference]
        case .rem:
            meaning = "快速眼动，图表中也写作 REM。这个阶段眼球会快速活动，大脑比较活跃，常出现生动的梦，和记忆、学习、情绪整理有关。其他阶段也可能做梦。\n\n成人常见参考约 20%–25%，通常后半夜更多。睡得太短、用药和身体情况都可能影响比例，单晚偏低不能说明生病。"
            references = [deepReference, physiologyReference]
        case .awake:
            meaning = "睡着后，设备连续记录为清醒的一段时间，算作一次夜间清醒。刚开始记录时还没睡着的那一段不算。短暂清醒很常见，不一定影响休息。\n\n本晚夜间清醒：\(record.awakenings.map { "\($0) 次" } ?? "资料不完整")。"
            references = [physiologyReference]
        case .unspecified:
            meaning = "设备知道这段时间在睡觉，但没有告诉我们是深睡、浅睡还是快速眼动。它会算进睡眠总时长，暂不计算各阶段比例。"
            references = []
        case .unobserved:
            meaning = "这段时间没有可靠记录，不能判断在睡觉还是清醒。不把它当成任何阶段，也暂不计算效率、分数和各阶段比例。"
            references = []
        }
        let isSleepStage = [.deep, .light, .rem].contains(stage)
        let summary = isSleepStage
            ? "本晚 \(record.minutes(stage)) 分钟，\(record.share(stage).map { "占睡眠的 \($0)%" } ?? "资料不完整，暂不计算占比")。\n计算：这个阶段的时间 ÷ 睡着的总时间 × 100%，显示整数，小数不计。"
            : "本晚\(stage.label) \(record.minutes(stage)) 分钟。"
        let limitation = isSleepStage ? "\n\n这些是成人的一般参考，不是设备检测的及格线；儿童和个人情况需要分别看。" : ""
        return MetricHelp(title: "\(stage.label)\(isSleepStage ? "占比" : "时段")", body: "\(summary)\n\n\(meaning)\(limitation)", references: references)
    }
}

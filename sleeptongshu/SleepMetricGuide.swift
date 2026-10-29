import SwiftUI

struct SleepReference: Identifiable {
    let title: String
    let url: String
    var id: String { url }
}

enum SleepMetricGuide {
    static let stagesReference = SleepReference(title: "Sleep Foundation · Stages of Sleep", url: "https://www.sleepfoundation.org/stages-of-sleep")
    static let deepReference = SleepReference(title: "Sleep Foundation · Deep Sleep", url: "https://www.sleepfoundation.org/stages-of-sleep/deep-sleep")
    static let physiologyReference = SleepReference(title: "NHLBI · Stages of Sleep", url: "https://www.nhlbi.nih.gov/health/sleep/stages-of-sleep")
    static let qualityReference = SleepReference(title: "Sleep Foundation · Sleep Quality", url: "https://www.sleepfoundation.org/sleep-hygiene/how-to-determine-poor-quality-sleep")
    static let consensusReference = SleepReference(title: "Ohayon 等，2017 · 睡眠质量专家共识", url: "https://doi.org/10.1016/j.sleh.2016.11.006")

    static func efficiency(_ record: SleepRecord) -> MetricHelp {
        MetricHelp(title: "睡眠效率怎么算？", body: "本 App 的记录内效率 = 总睡眠时长 ÷ 记录起止之间的总时长 × 100%，显示时向下取整。总睡眠包括深睡、浅睡、REM 和明确标记的未分期睡眠，不包括清醒与未记录。\n\n本晚：\(SleepRecord.durationText(record.asleepMinutes)) ÷ \(SleepRecord.durationText(record.inBedMinutes))\(record.efficiency.map { " ≈ \($0)%" } ?? "；记录不完整，暂不计算")。\n\n意义：了解已记录时段内有多少时间在睡眠。临床睡眠效率以完整卧床时间为分母；成人常以 ≥ 85%（最高 100%）作为睡眠较集中的参考，不能单独判断睡眠质量。\n\n戒指或系统健康可能从入睡才开始记录，遗漏睡前清醒会让本值偏高，因此不能直接等同于临床指标。即使效率很高，睡眠时间太短仍可能休息不足。有未记录区间或没有睡眠/清醒区间时，不给出效率。", references: [qualityReference, consensusReference])
    }

    static func score(_ record: SleepRecord) -> MetricHelp {
        let duration = min(100, Int(Double(record.asleepMinutes) / 480 * 100))
        return MetricHelp(title: "睡眠参考分怎么算？", body: "这是 App 自定义的 0–100 分观察指标，用于对照同一来源多晚的时长与记录内效率。没有经过临床验证，不是戒指原始评分。\n\n时长分 = min(100，睡眠分钟数 ÷ 480 × 100)，先向下取整；8 小时及以上记 100 分。\n参考分 = 时长分 × 60% + 记录内睡眠效率 × 40%，最后四舍五入。\n\n\(record.score.map { "本晚：\(duration) × 60% + \(record.efficiency ?? 0) × 40% = \($0) 分。" } ?? "本晚缺少可计算的效率，暂不生成分数。")\n\n分数较高只表示这两个维度较高，不保证睡眠健康；未纳入深睡、REM、血氧、鼾声、白天精神状态等。8 小时是固定计分基准，与可调整的睡眠目标独立；60/40 权重是产品设定，不来自医学文献，也没有临床合格线。\n\n缺失区间不补算。请结合睡眠总量、白天感受与连续多晚趋势理解，避免为追求高分延长卧床时间。", references: [consensusReference])
    }

    static func stages(_ record: SleepRecord) -> MetricHelp {
        let source: String
        switch record.source {
        case .band: source = "本晚来自戒指，色条按已同步的分期时间绘制。"
        case .healthKit: source = "本晚来自系统健康，色条按所选来源的分期时间绘制。"
        case .sample: source = "当前选中的是预览记录，可在本地数据中移除；它不会与真实记录合并统计。"
        case .manual: source = "本晚为手动记录，没有设备分期时不生成阶段。"
        case .phone: source = "本晚为手机信号估算；声音和体动不能判断深睡、浅睡或 REM。"
        }
        return MetricHelp(title: "关于睡眠阶段", body: "\(source)\n\n浅睡通常对应 N1 与 N2，深睡对应慢波睡眠 N3；REM 是快速眼动睡眠。它们在整晚交替出现，深睡往往在前半夜更多，REM 往往在后半夜更多。\n\n每种阶段占比 = 该阶段时长 ÷ 总睡眠时长 × 100%，分母不含清醒。有未分期或未记录区间时，暂不展示分期比例，避免把缺失数据算成 0。\n\n下方各阶段可查看含义与成人参考。戒指以传感器信号估算分期，与脑电睡眠检查的分期可能不同；年龄、用药、身体状态和设备算法也会影响结果。", references: [physiologyReference, stagesReference])
    }

    static func referenceText(_ stage: SleepStage) -> String {
        switch stage {
        case .deep: "成人参考约 10%–20%"
        case .light: "成人通常约一半或更多"
        case .rem: "成人参考约 20%–25%"
        default: "不计入睡眠占比分母"
        }
    }

    static func stage(_ stage: SleepStage, record: SleepRecord) -> MetricHelp {
        let meaning: String
        let references: [SleepReference]
        switch stage {
        case .deep:
            meaning = "深睡是非快速眼动睡眠的 N3 阶段，也称慢波睡眠，参与身体恢复与记忆巩固，通常前半夜较多。\n\n成人科普参考约占总睡眠的 10%–20%；年龄增长时往往减少。此区间来自人群概括，不是戒指检测的合格标准，也不是越多越好。"
            references = [deepReference, physiologyReference]
        case .light:
            meaning = "浅睡通常合并 N1（入睡过渡）与 N2（较稳定睡眠），是正常睡眠的重要组成部分，并不等于没有休息好。\n\n成人通常约一半或更多：文献科普中 N2 本身约占一半，浅睡还包含 N1。没有适用于所有年龄与设备的统一浅睡正常范围，本 App 不设置合格上下限；主要观察个人多晚趋势。"
            references = [stagesReference, physiologyReference]
        case .rem:
            meaning = "REM 是 Rapid Eye Movement，即快速眼动睡眠。此时大脑较活跃、眼球快速活动，多数骨骼肌张力降低，常出现生动梦境，与学习、记忆和情绪加工有关；其他阶段也可能做梦。\n\n成人科普参考约占总睡眠的 20%–25%，通常后半夜更长。比例受年龄、睡眠时长、用药等影响；比例低不能单独判定疾病。"
            references = [deepReference, stagesReference, physiologyReference]
        case .awake:
            meaning = "清醒时段不计入总睡眠时长。入睡后被记录为清醒的连续时间段计为一次夜间清醒，起始清醒段不计；短暂清醒很常见。\n\n本晚夜间清醒次数：\(record.awakenings.map { "\($0) 次" } ?? "暂无完整记录")。"
            references = [physiologyReference]
        case .unspecified:
            meaning = "来源确认这段时间处于睡眠，但没有提供具体阶段。它会计入总睡眠，不归入深睡、浅睡或 REM；存在未分期区间时，不展示分期占比。"
            references = []
        case .unobserved:
            meaning = "这段时间没有可用记录，或来源区间存在冲突，不能判断睡眠还是清醒。不计入总睡眠，不补作清醒或深睡；存在未记录区间时不生成睡眠效率、参考分或分期占比。"
            references = []
        }
        let value = record.share(stage).map { "\($0)%" } ?? "暂不可计算"
        let isSleepStage = [.deep, .light, .rem].contains(stage)
        let summary = isSleepStage
            ? "本晚 \(record.minutes(stage)) 分钟，占比\(value)。算法：该阶段分钟数 ÷ 总睡眠分钟数 × 100%，向下取整；清醒不在分母中。"
            : "本晚\(stage.label) \(record.minutes(stage)) 分钟。"
        let limitation = isSleepStage ? "\n\n参考值主要针对成人脑电睡眠分期，不能直接作为戒指算法的诊断阈值。分期未完整提供时显示 --，不补算。" : ""
        return MetricHelp(title: "\(stage.label)\(isSleepStage ? "占比" : "时段")", body: "\(summary)\n\n\(meaning)\(limitation)", references: references)
    }
}

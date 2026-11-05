import SwiftUI
import Charts

struct StageTimeline: View {
    let record: SleepRecord
    var body: some View {
        Chart(record.segments) { segment in
            RectangleMark(xStart: .value("开始", segment.start), xEnd: .value("结束", segment.end),
                          yStart: .value("阶段下界", Double(segment.stage.level) - 0.32),
                          yEnd: .value("阶段上界", Double(segment.stage.level) + 0.32))
            .foregroundStyle(segment.stage.color).cornerRadius(3)
            .accessibilityLabel(segment.stage.label)
            .accessibilityValue("\(SleepRecord.clock(segment.start))，\(segment.minutes)分钟")
        }
        .chartXScale(domain: record.start...record.end)
        .chartYScale(domain: (record.minutes(.unobserved) > 0 ? -1.6 : -0.6)...3.6)
        .chartYAxis {
            AxisMarks(position: .leading, values: record.minutes(.unobserved) > 0 ? [-1, 0, 1, 2, 3] : [0, 1, 2, 3]) { value in
                AxisGridLine().foregroundStyle(SleepPalette.line.opacity(0.6))
                AxisValueLabel {
                    if let level = value.as(Int.self), let stage = SleepStage.allCases.first(where: { $0.level == level }) {
                        Text(level == 1 && !record.hasStages ? "睡眠" : stage == .rem ? "REM" : stage.label).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [record.start, record.start.addingTimeInterval(record.end.timeIntervalSince(record.start) / 2), record.end]) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(SleepRecord.clock(date)).font(.system(size: 10)).foregroundStyle(SleepPalette.muted) }
                }
            }
        }
        .frame(height: 150)
    }
}

struct HeartRateChart: View {
    let samples: [HeartSample]
    var body: some View {
        Chart(samples) { sample in
            AreaMark(x: .value("时间", sample.date), yStart: .value("基线", 40), yEnd: .value("心率", sample.bpm))
                .foregroundStyle(LinearGradient(colors: [SleepPalette.awake.opacity(0.19), SleepPalette.awake.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("时间", sample.date), y: .value("心率", sample.bpm))
                .foregroundStyle(SleepPalette.awake).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
        }
        .chartYScale(domain: 40...max(85, (samples.map(\.bpm).max() ?? 80) + 5))
        .chartYAxis { AxisMarks(position: .leading, values: [40, 60, 80]) { _ in AxisGridLine().foregroundStyle(SleepPalette.line); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute()) } }
        .frame(height: 115)
        .accessibilityLabel("睡眠心率曲线")
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case duration = "时长", efficiency = "效率", deep = "深睡"
    var id: String { rawValue }
    func value(_ record: SleepRecord) -> Double? {
        switch self {
        case .duration: record.hasSleepDuration ? Double(record.asleepMinutes) / 60 : nil
        case .efficiency: record.efficiency.map(Double.init)
        case .deep: record.deepShare.map(Double.init)
        }
    }
    var unit: String { self == .duration ? "h" : "%" }
}

struct SleepTrendChart: View {
    let records: [SleepRecord]
    let metric: TrendMetric
    let goal: Double
    var body: some View {
        Chart {
            if metric == .duration {
                RuleMark(y: .value("目标", goal)).foregroundStyle(SleepPalette.teal.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(records) { record in
                if let value = metric.value(record) {
                    BarMark(x: .value("日期", record.end, unit: .day), y: .value(metric.rawValue, value))
                        .foregroundStyle(record.id == records.last?.id ? SleepPalette.teal : SleepPalette.mint.opacity(0.7)).cornerRadius(4)
                        .accessibilityLabel(record.end.formatted(.dateTime.month().day()))
                        .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(1))))\(metric.unit)")
                }
            }
        }
        .chartYScale(domain: 0...(metric == .duration ? max(10, (records.compactMap(metric.value).max() ?? 0) + 1) : 100))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(SleepPalette.line)
                AxisValueLabel { if let number = value.as(Double.self) { Text("\(Int(number))\(metric.unit)").font(.system(size: 10)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: records.count <= 7 ? 7 : 5)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 10))
            }
        }
        .frame(height: 195)
    }
}

struct SleepStageBalance: View {
    let record: SleepRecord
    private var stages: [SleepStage] { [.deep, .light, .rem, .awake, .unspecified, .unobserved].filter { record.minutes($0) > 0 } }
    var body: some View {
        HStack(spacing: 22) {
            Chart(stages) { stage in
                SectorMark(angle: .value("分钟", record.minutes(stage)), innerRadius: .ratio(0.76), angularInset: 2)
                    .foregroundStyle(stage.color).cornerRadius(2)
                    .accessibilityLabel(stage.label).accessibilityValue("\(record.minutes(stage)) 分钟")
            }.frame(width: 112, height: 112)
                .chartBackground { _ in
                    VStack(spacing: 3) {
                        Image(systemName: "moon.fill").font(.system(size: 18)).foregroundStyle(SleepPalette.deep)
                        Text("整晚分布").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                    }
                }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stages) { stage in
                    HStack(spacing: 7) {
                        Circle().fill(stage.color).frame(width: 6, height: 6)
                        Text(stage.label).font(.system(size: 12))
                        Spacer(minLength: 4)
                        Text(SleepRecord.durationText(record.minutes(stage))).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
            }
        }.accessibilityElement(children: .contain)
    }
}

struct SleepRegularityChart: View {
    let records: [SleepRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "入睡与醒来的节奏", subtitle: "每条线是一晚的记录范围，不代表整段都睡着")
            Chart {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    BarMark(xStart: .value("开始", hour(record.start)), xEnd: .value("结束", hour(record.start) + record.end.timeIntervalSince(record.start) / 3600),
                            y: .value("晚次", records.count - 1 - index), height: .fixed(6))
                        .foregroundStyle(record.source == .sample ? SleepPalette.deep.opacity(0.55) : SleepPalette.teal)
                        .cornerRadius(3)
                        .accessibilityLabel(record.end.formatted(.dateTime.month().day()))
                        .accessibilityValue("\(SleepRecord.clock(record.start)) 至 \(SleepRecord.clock(record.end))")
                }
            }.chartYScale(domain: -0.5...max(0.5, Double(records.count) - 0.5))
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(0..<records.count)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), records.indices.contains(index) {
                                Text(records[records.count - 1 - index].end.formatted(.dateTime.month().day())).font(.system(size: 10))
                            }
                        }
                    }
                }.chartXAxis {
                AxisMarks(values: .stride(by: 6)) { value in
                    AxisGridLine().foregroundStyle(SleepPalette.line)
                    AxisValueLabel { if let hour = value.as(Double.self) { Text("\(Int(hour + 12) % 24):00").font(.system(size: 10)) } }
                }
            }.frame(height: CGFloat(max(120, min(540, records.count * 18))))
                .accessibilityLabel("每晚记录开始和结束时间图")
        }
    }
    private func hour(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(((parts.hour ?? 0) + 12) % 24) + Double(parts.minute ?? 0) / 60
    }
}

import SwiftUI
import Charts

struct StageTimeline: View {
    let record: SleepRecord
    @State private var selected: SleepSegment?
    @ScaledMetric(relativeTo: .body) private var chartHeight = 170.0
    private var levels: [Int] { Array(Set(record.segments.map { $0.stage.level })).sorted() }
    var body: some View {
        Chart(record.segments) { segment in
            RectangleMark(xStart: .value("开始", segment.start), xEnd: .value("结束", segment.end),
                          yStart: .value("阶段下界", Double(segment.stage.level) - 0.32),
                          yEnd: .value("阶段上界", Double(segment.stage.level) + 0.32))
            .foregroundStyle(segment.stage.color).cornerRadius(3)
            .accessibilityLabel(segment.stage.label)
            .accessibilityValue("\(record.displayClock(segment.start)) 至 \(record.displayClock(segment.end))，\(segment.minutes)分钟")
        }
        .chartXScale(domain: record.start...record.end)
        .chartYScale(domain: (Double(levels.first ?? 0) - 0.6)...(Double(levels.last ?? 3) + 0.6))
        .chartYAxis {
            AxisMarks(position: .leading, values: levels) { value in
                AxisGridLine().foregroundStyle(SleepPalette.line.opacity(0.6))
                AxisValueLabel {
                    if let level = value.as(Int.self), let stage = SleepStage.allCases.first(where: { $0.level == level }) {
                        Text(stage == .rem ? "REM" : stage == .inBed ? "卧床" : stage.label).font(.caption2).foregroundStyle(SleepPalette.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [record.start, record.start.addingTimeInterval(record.end.timeIntervalSince(record.start) / 2), record.end]) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(record.displayClock(date)).font(.caption2).foregroundStyle(SleepPalette.muted) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).onTapGesture { location in
                    guard let plot = proxy.plotFrame else { return }
                    let x = location.x - geometry[plot].origin.x
                    guard let date = proxy.value(atX: x, as: Date.self) else { return }
                    selected = record.segments.first { $0.start <= date && $0.end > date }
                }
            }
        }
        .frame(height: chartHeight).accessibilityIdentifier("sleepStageTimeline")
        .sheet(item: $selected) { segment in
            NavigationStack {
                Form {
                    LabeledContent("阶段", value: segment.stage.label)
                    LabeledContent("开始", value: record.displayClock(segment.start))
                    LabeledContent("结束", value: record.displayClock(segment.end))
                    LabeledContent("时长", value: "\(segment.minutes) 分钟")
                    Text("记录时区：\(record.displayTimeZone.identifier)").font(.caption)
                }.navigationTitle("阶段详情").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selected = nil } } }
            }.presentationDetents([.medium, .large])
        }
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
    private var days: [SleepTrendDay] { SleepTrendDay.summarize(records) }
    private func value(_ day: SleepTrendDay) -> Double? {
        switch metric {
        case .duration: Double(day.asleepMinutes) / 60
        case .efficiency: day.efficiency
        case .deep: day.deepShare
        }
    }
    var body: some View {
        Chart {
            if metric == .duration {
                RuleMark(y: .value("目标", goal)).foregroundStyle(SleepPalette.teal.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(days) { day in
                if let value = value(day) {
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value(metric.rawValue, value))
                        .foregroundStyle(day.date == days.last?.date ? SleepPalette.teal : SleepPalette.mint.opacity(0.7)).cornerRadius(4)
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                        .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(1))))\(metric.unit)")
                }
            }
        }
        .chartYScale(domain: 0...(metric == .duration ? max(10, (days.compactMap(value).max() ?? 0) + 1) : 100))
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
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var stages: [SleepStage] { SleepStage.allCases.filter { record.minutes($0) > 0 } }
    var body: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) { distribution; legend }
        } else { ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { distribution; legend }
            VStack(alignment: .leading, spacing: 16) { distribution; legend }
        }.accessibilityElement(children: .contain) }
    }
    private var distribution: some View {
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
    }
    private var legend: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stages) { stage in
                    HStack(spacing: 7) {
                        Circle().fill(stage.color).frame(width: 6, height: 6)
                        Text(stage.label).font(.caption)
                        Spacer(minLength: 4)
                        Text(SleepRecord.durationText(record.minutes(stage))).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
            }
    }
}

struct SleepRegularityChart: View {
    let records: [SleepRecord]
    private var sleeps: [SleepRecord] { records.filter { $0.hasSleepDuration && $0.sleepOnset != nil && $0.sleepEnd != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "入睡与结束的节奏", subtitle: "每条线从入睡到最后睡眠结束，包含期间已记录的清醒；午睡单独显示")
            Chart {
                ForEach(Array(sleeps.enumerated()), id: \.element.id) { index, record in
                    BarMark(xStart: .value("开始", hour(record.sleepOnset!, zone: record.displayTimeZone)), xEnd: .value("结束", endHour(record)),
                            y: .value("晚次", sleeps.count - 1 - index), height: .fixed(6))
                        .foregroundStyle(record.source == .sample ? SleepPalette.deep.opacity(0.55) : SleepPalette.teal)
                        .cornerRadius(3)
                        .accessibilityLabel(record.day.formatted(.dateTime.month().day()))
                        .accessibilityValue("\(record.displayClock(record.sleepOnset!)) 至 \(record.displayClock(record.sleepEnd!))")
                }
            }.chartYScale(domain: -0.5...max(0.5, Double(sleeps.count) - 0.5))
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(0..<sleeps.count)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), sleeps.indices.contains(index) {
                                Text(sleeps[sleeps.count - 1 - index].day.formatted(.dateTime.month().day())).font(.caption2)
                            }
                        }
                    }
                }.chartXAxis {
                AxisMarks(values: .stride(by: 6)) { value in
                    AxisGridLine().foregroundStyle(SleepPalette.line)
                    AxisValueLabel { if let hour = value.as(Double.self) { Text("\(Int(hour + 12) % 24):00").font(.system(size: 10)) } }
                }
            }.frame(height: CGFloat(max(120, min(540, sleeps.count * 18))))
                .accessibilityLabel("每次入睡和睡眠结束时间图")
            Text("线长按实际经过时间绘制。遇到时钟调整，以详情中的当地开始、结束时刻为准。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
        }
    }
    private func hour(_ date: Date, zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(((parts.hour ?? 0) + 12) % 24) + Double(parts.minute ?? 0) / 60
    }
    private func endHour(_ record: SleepRecord) -> Double {
        hour(record.sleepOnset!, zone: record.displayTimeZone) + record.sleepEnd!.timeIntervalSince(record.sleepOnset!) / 3600
    }
}

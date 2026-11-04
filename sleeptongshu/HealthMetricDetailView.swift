import SwiftUI
import Charts

struct HealthMetricDetailView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.dismiss) private var dismiss
    let metric: HealthMetric
    @State private var period = 30
    @State private var selection: Date?
    private var days: [HealthDay] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - period, to: Calendar.current.startOfDay(for: .now))!
        return health.days(for: metric).filter { $0.date >= start && $0.date <= .now }
    }
    private var inspected: HealthDay? {
        guard let selection else { return days.last }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selection) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(health.sourceSummary(for: metric), systemImage: "heart.text.clipboard")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    Picker("记录范围", selection: $period) { Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90) }
                        .pickerStyle(.segmented).onChange(of: period) { _, _ in selection = nil }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(inspected.map { $0.value.formatted(.number.precision(.fractionLength(metric == .steps || metric == .exercise ? 0 : 1))) } ?? "—")
                            .font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(metric.healthTint).monospacedDigit()
                            .accessibilityIdentifier("healthDetailValue")
                        Text(metric.unit).font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                        Spacer()
                        Text(inspected?.date.formatted(.dateTime.month().day()) ?? "当日无记录").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    }
                    if days.isEmpty {
                        ContentUnavailableView("没有可展示的记录", systemImage: metric.symbol,
                                               description: Text(health.snapshot?.truncatedMetrics.contains(metric) == true ? "该项目达到本次读取上限，暂不合计。" : "试试更长的时间范围，再检查系统健康是否已有记录及读取权限。"))
                    } else {
                        Chart(days) { day in
                            if metric.isCumulative || metric == .sleep {
                                BarMark(x: .value("日期", day.date, unit: .day), y: .value(metric.title, day.value)).foregroundStyle(metric.healthTint.opacity(0.75))
                            } else {
                                PointMark(x: .value("日期", day.date), y: .value(metric.title, day.value)).symbolSize(30).foregroundStyle(metric.healthTint)
                            }
                            if let inspected, inspected.id == day.id {
                                RuleMark(x: .value("选中日期", day.date)).foregroundStyle(SleepPalette.muted.opacity(0.4)).lineStyle(StrokeStyle(dash: [4, 4]))
                            }
                        }.chartXSelection(value: $selection)
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .chartYAxis { AxisMarks(position: .leading) }.frame(height: 210)
                            .accessibilityLabel("\(metric.title)每日记录图")
                        Text("\(days.count) 天有记录 · \(metric.isCumulative ? "日值由系统健康统计" : metric == .sleep ? "日值为睡着时长" : "日值为样本中位数")。空白不算 0，缺口不连线。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                    }
                    Divider()
                    SectionHeading(title: "这个数字代表什么")
                    Text(metric.explanation).font(.system(size: 14)).foregroundStyle(SleepPalette.muted).lineSpacing(6)
                    if metric == .hrv || metric == .restingHeart {
                        Text("个人趋势比较最近 14 个完整自然日和之前 14 日，两段各至少 7 天。取各段日值的中位数后相减，不作为疾病或压力诊断。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                    }
                    if metric.isCumulative {
                        Text("直接采用系统健康的每日统计，不手动累加多台设备的原始数据。今天尚未结束，数值可能继续更新；来源未同步或未获准读取时，统计也可能不完整。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                    }
                    Divider()
                    SectionHeading(title: "最近记录")
                    ForEach(Array(days.suffix(10).reversed())) { day in
                        HStack {
                            Text(day.date.formatted(.dateTime.month().day())).foregroundStyle(SleepPalette.muted)
                            Spacer()
                            Text("\(day.value.formatted(.number.precision(.fractionLength(metric == .steps ? 0 : 1)))) \(metric.unit)")
                        }.font(.system(size: 13)).padding(.vertical, 4)
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
                .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

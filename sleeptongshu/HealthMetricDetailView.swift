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
                            .chartYScale(domain: .automatic(includesZero: metric.isCumulative || metric == .sleep))
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .chartYAxis { AxisMarks(position: .leading) }.frame(height: 210)
                            .accessibilityLabel("\(metric.title)每日记录图")
                        Text("\(days.count) 天有记录 · \(metric.isCumulative ? "日值由系统健康统计" : metric == .sleep ? "日值为睡着时长" : "日值为样本中位数")。空白不算 0，缺口不连线。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                        HStack(spacing: 12) {
                            summary("最低日值", value: days.map(\.value).min())
                            summary("日值中位数", value: HealthOverviewAnalysis.median(days.map(\.value)))
                            summary("最高日值", value: days.map(\.value).max())
                        }.padding(.vertical, 10)
                        Divider()
                        HealthCoverageCalendar(days: days, period: period, tint: metric.healthTint)
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

    private func summary(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(metric == .steps ? 0 : 1))) } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(metric.healthTint)
            Text(metric.unit).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthCoverageCalendar: View {
    let days: [HealthDay]
    let period: Int
    let tint: Color
    private var dates: [Date] {
        (0..<period).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now)) }
    }
    private var recorded: Set<Date> { Set(days.map { Calendar.current.startOfDay(for: $0.date) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "哪些天有记录", subtitle: "最近 \(period) 天 · \(recorded.count) 天有可用数据")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    let hasData = recorded.contains(date)
                    Text(date.formatted(.dateTime.day())).font(.system(size: 10, weight: hasData ? .semibold : .regular)).monospacedDigit()
                        .foregroundStyle(hasData ? tint : SleepPalette.muted)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(hasData ? tint.opacity(0.14) : SleepPalette.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("\(date.formatted(.dateTime.month().day()))，\(hasData ? "有记录" : "未读到记录")")
                }
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.2)).frame(width: 10, height: 10)
                Text("有记录")
                RoundedRectangle(cornerRadius: 2).fill(SleepPalette.line).frame(width: 10, height: 10)
                Text("未读到")
            }.font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text("从左到右、从上到下按日期排列。灰色不代表身体异常，也不代表当天数值为 0。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }
}

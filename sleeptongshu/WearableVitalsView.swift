import SwiftUI
import Charts

struct WearableVitalsView: View {
    @EnvironmentObject private var store: WearableVitalsStore
    @State private var device = ""
    @State private var kind = VitalKind.heart
    @State private var days = 7
    @State private var selectedDate: Date?

    private var devices: [String] { Set(store.visibleSamples.map(\.device)).sorted() }
    private var deviceSamples: [WearableVital] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: .now))!
        return store.visibleSamples.filter { $0.device == device && $0.date >= start && $0.date <= .now }
    }
    private var kinds: [VitalKind] { VitalKind.allCases.filter { item in item.isVisible && deviceSamples.contains { $0.kind == item } } }
    private var selected: [WearableVital] { deviceSamples.filter { $0.kind == kind } }
    private var daily: [VitalDay] { VitalInsights.daily(selected) }
    private var inspected: WearableVital? {
        guard let selectedDate else { return selected.last }
        return selected.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var tint: Color {
        switch kind {
        case .heart: SleepPalette.awake
        case .oxygen: SleepPalette.teal
        case .hrv: SleepPalette.deep
        default: SleepPalette.teal
        }
    }
    private var yDomain: ClosedRange<Double> {
        let low = min(selected.map(\.value).min() ?? 0, kind.chartReference?.lowerBound ?? .infinity)
        let high = max(selected.map(\.value).max() ?? 1, kind.chartReference?.upperBound ?? -.infinity)
        let padding = max(1, (high - low) * 0.15)
        return max(0, low - padding)...(high + padding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "身体的变化，慢慢看", subtitle: "只看已有记录 · 数据保存在本机")
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if store.visibleSamples.isEmpty {
                    ContentUnavailableView("暂无体征记录", systemImage: "heart.text.clipboard",
                                           description: Text("连接设备后会自动同步。有了记录，就能查看自己的变化。"))
                } else {
                    filters
                    if deviceSamples.isEmpty {
                        ContentUnavailableView("这几天没有记录", systemImage: "calendar", description: Text("试试更长的时间范围，或连接设备读取新记录。"))
                    } else {
                        metricPicker
                        if !selected.isEmpty {
                            overview
                            reference
                            Divider()
                            timeline
                            Divider()
                            dailyChart
                            Divider()
                            distribution
                            Divider()
                            recentRecords
                        }
                    }
                }
            }.padding(22).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
        .navigationTitle("体征记录").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onAppear { refreshSelection() }
        .onChange(of: device) { _, _ in refreshKind() }
        .onChange(of: days) { _, _ in refreshKind() }
        .onChange(of: kind) { _, _ in selectedDate = nil }
        .onChange(of: store.visibleSamples) { _, _ in refreshSelection() }
    }

    private var filters: some View {
        VStack(spacing: 14) {
            Picker("设备", selection: $device) {
                ForEach(devices, id: \.self) { key in
                    Text(DevicePresentation.name(store.visibleSamples.first { $0.device == key }?.deviceLabel ?? "设备")).tag(key)
                }
            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            Picker("时间范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }
                .pickerStyle(.segmented).accessibilityIdentifier("vitalPeriod")
        }
    }

    private var metricPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(kinds) { item in
                if let sample = deviceSamples.last(where: { $0.kind == item }) {
                    Button { kind = item } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.title).font(.system(size: 13, weight: .medium))
                                Spacer(minLength: 2)
                                if kind == item { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(VitalInsights.number(sample.value)).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text(item.unit).font(.system(size: 10))
                            }.lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(14)
                            .foregroundStyle(kind == item ? SleepPalette.teal : SleepPalette.ink)
                            .background(kind == item ? SleepPalette.teal.opacity(0.09) : Color.white, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel("查看\(item.title)趋势")
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(.system(size: 22, weight: .semibold))
                Spacer()
                Text("\(daily.count) 天 · \(selected.count) 条").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
            Text(kind.meaning).font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            HStack(alignment: .top, spacing: 12) {
                summaryValue("平均", value: selected.map(\.value).reduce(0, +) / Double(selected.count))
                summaryValue("最低", value: selected.map(\.value).min()!)
                summaryValue("最高", value: selected.map(\.value).max()!)
            }.padding(.vertical, 6)
            Text("按已有记录计算；记录不均匀时，平均值不代表全天或整晚。")
                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
        }
    }

    private var reference: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind.referenceText, systemImage: "info.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(SleepPalette.teal)
            Text(kind.referenceNote).font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            Text(kind.referenceSource).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
        }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("vitalReference")
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "每次记录的变化", subtitle: "\(kind.title) · \(kind.unit)")
            if let inspected {
                HStack {
                    Text(inspected.date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                    Spacer()
                    Text("\(VitalInsights.number(inspected.value)) \(kind.unit)").fontWeight(.semibold).foregroundStyle(tint)
                }.font(.system(size: 12)).frame(height: 22)
            }
            Chart {
                if let range = kind.chartReference {
                    RectangleMark(yStart: .value("参考下限", range.lowerBound), yEnd: .value("参考上限", range.upperBound))
                        .foregroundStyle(SleepPalette.teal.opacity(0.07))
                    RuleMark(y: .value("参考下限", range.lowerBound)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(SleepPalette.teal.opacity(0.5))
                }
                ForEach(selected) { sample in
                    PointMark(x: .value("时间", sample.date), y: .value(kind.unit, sample.value)).foregroundStyle(tint).symbolSize(30)
                }
                if selectedDate != nil, let inspected {
                    RuleMark(x: .value("所选时间", inspected.date)).foregroundStyle(tint.opacity(0.4))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(range: .plotDimension(padding: 8))
            .chartXSelection(value: $selectedDate)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day().hour()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 190).accessibilityLabel("\(kind.title)记录图")
            Text(kind == .oxygen ? "每个点是一条记录，淡绿色区域是 95%–100% 的一般参考。空白表示没有记录。" : "每个点是一条记录。点越高，数值越大；空白表示没有记录，不补画成连续变化。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "每天的高低变化", subtitle: "\(daily.count) 天有记录 · \(kind.unit)")
            Chart(daily) { day in
                BarMark(x: .value("日期", day.date, unit: .day), yStart: .value("最低", day.minimum), yEnd: .value("最高", day.maximum), width: .ratio(0.25))
                    .foregroundStyle(tint.opacity(0.3)).cornerRadius(3)
                PointMark(x: .value("日期", day.date, unit: .day), y: .value("平均", day.mean)).foregroundStyle(tint).symbolSize(35)
            }
            .chartYScale(domain: yDomain)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 165).accessibilityLabel("\(kind.title)每日范围图")
            Text("竖条两端是当天已有记录的最低值和最高值，圆点是平均值。只有一条记录时，只看到一个点；没有记录的日期留空。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var distribution: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "哪些数值出现得多", subtitle: "统计记录条数，不代表持续时间")
            VStack(spacing: 14) {
                ForEach(VitalInsights.buckets(selected)) { bucket in
                    VStack(spacing: 7) {
                        HStack {
                            Text("\(bucket.label) \(kind.unit)")
                            Spacer()
                            Text("\(bucket.count) 条").monospacedDigit()
                        }.font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.07))
                                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.75))
                                    .frame(width: proxy.size.width * Double(bucket.count) / Double(max(1, VitalInsights.buckets(selected).map(\.count).max() ?? 1)))
                            }
                        }.frame(height: 8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bucket.label) \(kind.unit)，\(bucket.count) 条")
                }
            }.accessibilityIdentifier("vitalDistribution")
            Text("条越长，落在这个数值范围里的记录越多。各段相邻边界只计一次；这些分组不是正常或异常的划分。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var recentRecords: some View {
        DisclosureGroup("最近记录 · 最多 20 条") {
            VStack(spacing: 12) {
                ForEach(Array(selected.suffix(20).reversed())) { sample in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sample.date.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 12))
                            Text(sample.origin == "设备时段均值" ? "这段时间的平均值" : sample.origin).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer()
                        Text("\(VitalInsights.number(sample.value)) \(kind.unit)").font(.system(size: 13, weight: .medium))
                    }
                    Divider()
                }
            }.padding(.top, 16)
        }.font(.system(size: 13, weight: .medium))
    }

    private func summaryValue(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text(VitalInsights.number(value)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(kind.unit).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshSelection() {
        if !devices.contains(device) { device = store.visibleSamples.last?.device ?? "" }
        refreshKind()
    }
    private func refreshKind() {
        if !kinds.contains(kind) { kind = kinds.first ?? .heart }
        selectedDate = nil
    }
}

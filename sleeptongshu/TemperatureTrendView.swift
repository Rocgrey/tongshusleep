import SwiftUI
import Charts

/// The chart stays unframed and uses actual day ranges rather than interpolating missing readings.
struct TemperatureTrendView: View {
    let summary: TemperatureSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?

    private var inspected: VitalDay? {
        guard let selectedDate else { return summary.days.last }
        return summary.days.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        if let latest = summary.latest, let mean = summary.mean {
            VStack(alignment: .leading, spacing: SleepPalette.Layout.inset) {
                HStack {
                    Label("体温趋势", systemImage: "thermometer.medium")
                        .font(.headline).foregroundStyle(SleepPalette.rose)
                    Spacer(minLength: SleepPalette.Layout.compact)
                    Text("\(summary.days.count) 天有记录").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: SleepPalette.Layout.item) {
                        latestValue(latest)
                        Spacer(minLength: 0)
                        averageValue(mean)
                    }
                    VStack(alignment: .leading, spacing: SleepPalette.Layout.item) { latestValue(latest); averageValue(mean) }
                }
                Text("\(DevicePresentation.name(latest.deviceLabel)) · 最近记录 \(latest.date.formatted(.dateTime.month().day().hour().minute()))")
                    .font(SleepPalette.TypeStyle.note).foregroundStyle(SleepPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                #if DEBUG
                if summary.samples.contains(where: { $0.origin == "界面测试示例" }) {
                    Text("界面测试示例 · 非真实数据").font(.caption).foregroundStyle(SleepPalette.rose)
                }
                #endif
                chart(mean: mean)
                legend
                if let day = inspected {
                    AnyLayout(typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: SleepPalette.Layout.item))) {
                        dayValue(day)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        navigation(day)
                    }
                }
                Text("\(summary.samples.count) 条设备估算记录。竖条两端为当天高低值，圆点为均值；虚线为这些记录的均值。空白日期没有记录，均值不代表全天或整晚。")
                    .font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                Text("腕部估算值不等同于体温计读数，适合和自己同一设备的记录比较。")
                    .font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("temperatureTrend")
        }
    }

    private func latestValue(_ latest: WearableVital) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近体温").font(.caption).foregroundStyle(SleepPalette.muted)
            (Text(VitalInsights.number(latest.value)).font(SleepPalette.TypeStyle.value) + Text(" ℃").font(.body))
                .monospacedDigit().foregroundStyle(SleepPalette.ink)
        }.accessibilityElement(children: .combine)
    }

    private func averageValue(_ mean: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("记录均值").font(.caption).foregroundStyle(SleepPalette.muted)
            Text("\(VitalInsights.number(mean)) ℃").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(SleepPalette.rose)
        }.accessibilityElement(children: .combine)
    }

    private func chart(mean: Double) -> some View {
        Chart {
            RuleMark(y: .value("记录均值", mean))
                .foregroundStyle(SleepPalette.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .accessibilityLabel("所选周期记录均值").accessibilityValue("\(VitalInsights.number(mean)) 摄氏度")
            ForEach(summary.days) { day in
                BarMark(x: .value("日期", day.date, unit: .day), yStart: .value("最低", day.minimum), yEnd: .value("最高", day.maximum), width: .fixed(8))
                    .foregroundStyle(SleepPalette.rose.opacity(0.35)).cornerRadius(4)
                    .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                    .accessibilityValue("最低 \(VitalInsights.number(day.minimum))，最高 \(VitalInsights.number(day.maximum)) 摄氏度，\(day.count) 条")
                PointMark(x: .value("日期", day.date, unit: .day), y: .value("每日均值", day.mean))
                    .foregroundStyle(SleepPalette.rose).symbolSize(day.id == inspected?.id ? 75 : 40)
                    .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                    .accessibilityValue("平均 \(VitalInsights.number(day.mean)) 摄氏度")
            }
        }
        .chartYScale(domain: summary.domain)
        .chartXScale(domain: summary.range.lowerBound...summary.range.upperBound)
        .chartXSelection(value: $selectedDate)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 4)) { value in
            AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.month().day())).font(.system(size: 11)) } }
        } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(SleepPalette.line.opacity(0.5))
            AxisValueLabel { if let number = value.as(Double.self) { Text(VitalInsights.number(number)).font(.system(size: 11)) } }
        } }
        .frame(height: typeSize.isAccessibilitySize ? 230 : 190)
        .accessibilityLabel("每日体温高低与均值图，单位摄氏度")
        .accessibilityIdentifier("temperatureRangeChart")
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SleepPalette.Layout.inset) { legendItems }
            VStack(alignment: .leading, spacing: SleepPalette.Layout.compact) { legendItems }
        }.font(.caption).foregroundStyle(SleepPalette.muted)
    }
    @ViewBuilder private var legendItems: some View {
        Label("每日均值", systemImage: "circle.fill").foregroundStyle(SleepPalette.rose)
        Label("每日高低", systemImage: "line.3.horizontal")
        Label("记录均值", systemImage: "line.diagonal")
    }

    private func dayValue(_ day: VitalDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date.formatted(.dateTime.month().day()) + " · \(day.count) 条").font(.caption).foregroundStyle(SleepPalette.muted)
            Text("\(VitalInsights.number(day.minimum))–\(VitalInsights.number(day.maximum)) ℃")
                .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(SleepPalette.ink)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("temperatureSelectedDay")
    }
    private func navigation(_ day: VitalDay) -> some View {
        let index = summary.days.firstIndex { $0.id == day.id } ?? 0
        return HStack(spacing: SleepPalette.Layout.compact) {
            Button { selectedDate = summary.days[index - 1].date } label: { Image(systemName: "chevron.left").frame(width: SleepPalette.Layout.touch, height: SleepPalette.Layout.touch) }
                .disabled(index == 0).accessibilityLabel("上一条体温日期").accessibilityIdentifier("previousTemperatureDay")
            Button { selectedDate = summary.days[index + 1].date } label: { Image(systemName: "chevron.right").frame(width: SleepPalette.Layout.touch, height: SleepPalette.Layout.touch) }
                .disabled(index + 1 >= summary.days.count).accessibilityLabel("下一条体温日期").accessibilityIdentifier("nextTemperatureDay")
        }.font(.system(size: 16, weight: .semibold)).buttonStyle(GrovePressStyle()).foregroundStyle(SleepPalette.rose)
    }
}

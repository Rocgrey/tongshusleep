import SwiftUI
import Charts

struct BIONightView: View {
    let record: SleepRecord
    let night: BIONight
    @Environment(\.dynamicTypeSize) private var dynamicType
    @EnvironmentObject private var algorithm: BIOAlgorithmStore
    @State private var kind = VitalKind.heart
    private var observation: Bool { !record.hasSleepDuration }
    private var measured: [WearableVital] {
        observation ? night.samples : night.samples.filter { sample in
            record.segments.contains { $0.stage.isAsleep && sample.date >= $0.start && sample.date < $0.end }
        }
    }
    private func count(_ kind: VitalKind) -> Int { measured.filter { $0.kind == kind }.count }
    private func mean(_ kind: VitalKind) -> Double? {
        let values = measured.filter { $0.kind == kind }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)
    }
    private var available: [VitalKind] { VitalKind.allCases.filter { $0.isVisible && count($0) > 0 } }
    private var selectedKind: VitalKind { available.contains(kind) ? kind : available.first ?? .heart }
    private var samples: [WearableVital] { measured.filter { $0.kind == selectedKind }.sorted { $0.date < $1.date } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if observation { VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("夜间观测", systemImage: "moon.stars.fill").font(.headline).foregroundStyle(SleepPalette.teal)
                    Spacer()
                    Text("\(night.samples.count) 条体征").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                Text(record.metadata?.externalSource ?? "蓝牙设备").font(.subheadline).foregroundStyle(SleepPalette.muted)
                Text("先看已有的真实记录").font(.title2.weight(.semibold)).foregroundStyle(SleepPalette.ink)
                Text("深睡、浅睡、快速眼动和清醒次数尚未返回。以下为夜间实际采样，不能据此判断睡着时长。")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                Label("观测 \(record.displayClock(record.start))–\(record.displayClock(record.end))", systemImage: "clock")
                    .font(.subheadline.weight(.medium)).foregroundStyle(SleepPalette.ink)
                Text("按前日 18:00 至当日 12:00 整理，归在结束日；这是整理范围，不代表一直在睡眠。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            } }
            if !available.isEmpty {
                SectionHeading(title: "夜间健康体征", subtitle: "有记录才展示 · 均值来自实际采样")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 240 : 135), alignment: .leading)], alignment: .leading, spacing: 22) {
                    ForEach(available) { metric in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("平均\(metric.title)").font(.caption).foregroundStyle(SleepPalette.muted)
                            Text((mean(metric)?.formatted(.number.precision(.fractionLength(0...1))) ?? "--") + " " + (measured.first { $0.kind == metric }?.displayUnit ?? metric.unit))
                                .font(.title3.weight(.semibold)).foregroundStyle(metric == .oxygen ? SleepPalette.deep : metric == .heart ? SleepPalette.rose : SleepPalette.teal)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(count(metric)) 次采样").font(.caption2).foregroundStyle(SleepPalette.muted)
                        }
                    }
                }
                Text(observation ? "这些是有记录时刻的平均值，采样可能有间断，不能代表整晚持续监测或睡眠期间均值。" : "仅统计已识别睡眠期间的有效采样；未记录的时段不参与平均。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                Picker("夜间指标", selection: $kind) { ForEach(available) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    .accessibilityIdentifier("bioNightMetric")
                Chart(samples) { sample in
                    PointMark(x: .value("记录时间", sample.date), y: .value(selectedKind.title, sample.value))
                        .symbolSize(26).foregroundStyle(selectedKind == .oxygen ? SleepPalette.deep : SleepPalette.teal)
                }.chartXScale(domain: record.start...record.end)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel { if let date = value.as(Date.self) { Text(record.displayClock(date)).font(.caption2) } }
                    } }
                    .frame(height: 175)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bioNightChart")
                Text("每个圆点是一条真实采样。没有圆点的时段没有记录，不连接成连续曲线。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("睡眠分析进度", systemImage: "waveform.path").font(.subheadline.weight(.semibold))
                Text(observation ? "已收到设备的夜间记录。睡眠阶段尚未生成，结果返回后会自动更新。" : (night.algorithmResult?.completed == 1 ? "已取得设备睡眠结果。" : "当前为阶段性结果，下次同步时继续更新。"))
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                Text("同步读取 \(night.readAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(SleepPalette.muted)
                Text(algorithm.message).font(.caption).foregroundStyle(SleepPalette.muted)
                Text("启用自动同步后，睡眠原始输入经你的平台提交厂家云算法；有效分期返回后自动更新，不发送原始录音。")
                    .font(.caption2).foregroundStyle(SleepPalette.muted)
            }
        }
    }
}

struct AutomaticSyncStatusView: View {
    @EnvironmentObject private var sync: AutomaticSyncStore
    @AppStorage("automaticHealthSyncV1") private var enabled = true
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if sync.isBusy { ProgressView().controlSize(.small) }
            else { Image(systemName: enabled ? "icloud" : "iphone") }
            Text(enabled ? sync.message : "自动同步已关闭，记录保存在本机")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(SleepPalette.muted).accessibilityIdentifier("automaticSyncStatus")
    }
}

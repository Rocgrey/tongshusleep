import SwiftUI
import Charts

struct WearableVitalsView: View {
    @EnvironmentObject private var store: WearableVitalsStore
    @State private var device = ""
    @State private var kind = VitalKind.heart
    @State private var days = 7

    private var devices: [String] { Set(store.samples.map(\.device)).sorted() }
    private var deviceSamples: [WearableVital] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return store.samples.filter { $0.device == device && $0.date >= start }
    }
    private var kinds: [VitalKind] { VitalKind.allCases.filter { value in deviceSamples.contains { $0.kind == value } } }
    private var selected: [WearableVital] { deviceSamples.filter { $0.kind == kind } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "体征记录", subtitle: "设备实测与设备估计分别标注 · 仅保存在本机")
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if store.samples.isEmpty {
                    ContentUnavailableView("暂无体征记录", systemImage: "heart.text.clipboard",
                                           description: Text("连接设备后同步。即使没有睡眠记录，也能保存设备提供的有效体征。"))
                } else {
                    Picker("设备", selection: $device) {
                        ForEach(devices, id: \.self) { key in
                            Text(DevicePresentation.name(store.samples.first { $0.device == key }?.deviceLabel ?? "穿戴设备")).tag(key)
                        }
                    }.pickerStyle(.menu)
                    Picker("时间范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented)
                    if deviceSamples.isEmpty {
                        Text("这台设备在所选时段没有记录。").foregroundStyle(SleepPalette.muted)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(kinds) { item in
                                if let sample = deviceSamples.last(where: { $0.kind == item }) {
                                    Button { kind = item } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(item.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                            Text(sample.value.formatted(.number.precision(.fractionLength(0...2))))
                                                .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                                            Text(item.unit).font(.system(size: 11))
                                            Text(sample.date.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 10))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                        .foregroundStyle(kind == item ? SleepPalette.teal : SleepPalette.ink)
                                        .background(kind == item ? SleepPalette.teal.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain).accessibilityLabel("查看\(item.title)趋势")
                                }
                            }
                        }
                        if !selected.isEmpty {
                            SectionHeading(title: kind.title, subtitle: "\(selected.count) 条 · \(kind.unit)")
                            Chart(selected) { sample in
                                PointMark(x: .value("记录时间", sample.date), y: .value(kind.unit, sample.value))
                                    .foregroundStyle(SleepPalette.teal).symbolSize(28)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day().hour()) } }
                            .frame(height: 190).accessibilityLabel("\(kind.title)记录图")
                            Text("按设备记录显示数据点，空白时段不作补算。蓝牙实时数据标注接收时间；设备时段均值不代表每一刻的测量。")
                                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                            ForEach(Array(selected.suffix(20).reversed())) { sample in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sample.date.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 12))
                                        Text(sample.origin).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                                    }
                                    Spacer()
                                    Text("\(sample.value.formatted(.number.precision(.fractionLength(0...2)))) \(kind.unit)")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Divider()
                            }
                        }
                    }
                    Text("HRV 与压力保留设备定义，不能直接与其他算法比较；血糖单位尚未确认时只显示原值。无创设备报告的血糖、血脂、尿酸和血压不能替代专业测量或化验，不用于诊断及调整用药。")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                }
            }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
        .navigationTitle("体征记录").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onAppear { refreshSelection() }
        .onChange(of: device) { _, _ in refreshKind() }
        .onChange(of: days) { _, _ in refreshKind() }
    }

    private func refreshSelection() {
        if !devices.contains(device) { device = store.samples.last?.device ?? "" }
        refreshKind()
    }
    private func refreshKind() { if !kinds.contains(kind) { kind = kinds.first ?? .heart } }
}

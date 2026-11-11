import SwiftUI

struct DeviceStepsSummaryView: View {
    @EnvironmentObject private var steps: DeviceStepsStore
    @State private var days = 7
    var body: some View {
        if let day = steps.latest {
            NavigationLink {
                ScrollView {
                    VStack(spacing: 22) {
                        Picker("时间范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented)
                        AccountStepsSection(days: days, initialSource: .device)
                    }.padding(22)
                }
                    .background(SleepPalette.background).navigationTitle("设备步数").navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "figure.walk").font(.system(size: 26)).foregroundStyle(SleepPalette.teal)
                        .frame(width: 48, height: 56).background(SleepPalette.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                            Text("界面测试示例 · 非真实数据").font(.caption2).foregroundStyle(SleepPalette.rose)
                        }
                        #endif
                        Text(day.day == StepDates.format(.now) ? "今日设备步数" : "最近设备步数").font(.subheadline).foregroundStyle(SleepPalette.muted)
                        (Text(day.steps.formatted()).font(.system(size: 29, weight: .semibold, design: .rounded)) + Text(" 步").font(.caption))
                            .foregroundStyle(SleepPalette.ink).accessibilityIdentifier("deviceStepTotal")
                        Text("\(day.deviceName) · \(day.day)").font(.caption).foregroundStyle(SleepPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("读取于 \(day.readAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(SleepPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(SleepPalette.muted)
                }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("openDeviceSteps")
        }
        if let error = steps.saveError { Text(error).font(.caption).foregroundStyle(SleepPalette.rose) }
    }
}

enum StepDisplaySource: Hashable { case device, cloud, health }

/// Latest point readings have their own dates and never masquerade as night averages.
struct DeviceRecentVitalsView: View {
    @EnvironmentObject private var store: WearableVitalsStore
    @EnvironmentObject private var steps: DeviceStepsStore
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var device: String? { steps.latest?.device ?? store.visibleSamples.last?.device }
    private var latest: [WearableVital] {
        let rows = store.visibleSamples.filter { $0.device == device }
        return VitalKind.allCases.filter(\.isVisible).compactMap { kind in rows.last { $0.kind == kind } }
    }
    var body: some View {
        if !latest.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "设备最近体征", subtitle: latest.first?.deviceLabel)
                Text("以下为设备最近一次记录，不代表睡眠期间的平均值。每项日期可能不同。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 240 : 135), alignment: .leading)], alignment: .leading, spacing: 18) {
                    ForEach(latest) { sample in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sample.kind.title).font(.caption).foregroundStyle(SleepPalette.muted)
                            Text(sample.value.formatted(.number.precision(.fractionLength(0...1))) + " " + sample.displayUnit)
                                .font(.headline).foregroundStyle(SleepPalette.ink).fixedSize(horizontal: false, vertical: true)
                            Text(sample.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(SleepPalette.muted)
                        }
                    }
                }
                NavigationLink { WearableVitalsView(preferredDevice: device) } label: {
                    Label("查看体征趋势", systemImage: "waveform.path.ecg").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
            }.accessibilityIdentifier("recentDeviceVitals")
        }
    }
}

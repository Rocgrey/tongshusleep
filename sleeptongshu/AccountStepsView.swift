import SwiftUI
import Charts

struct AccountStepsSection: View {
    let days: Int
    var initialSource: StepDisplaySource? = nil
    @EnvironmentObject private var health: HealthOverviewStore
    @EnvironmentObject private var deviceSteps: DeviceStepsStore
    @State private var sourceOverride: StepDisplaySource?
    @State private var selectedDevice: String?
    private var source: StepDisplaySource { sourceOverride ?? initialSource ?? (deviceSteps.rows.isEmpty ? .health : .device) }
    private var deviceMode: Bool { source == .device }
    private var deviceDays: [DeviceStepDay] { deviceSteps.days(for: selectedDevice).filter { period.contains($0.day) } }
    @State private var showRules = false
    private var period: StepRange { StepRange(days: days) }
    private var local: [LocalStepDay] { LocalStepDay.read(health.snapshot).filter { period.contains($0.date) } }
    private var values: [String: Int] {
        if deviceMode { return Dictionary(uniqueKeysWithValues: deviceDays.map { ($0.day, $0.steps) }) }
        return Dictionary(uniqueKeysWithValues: local.map { ($0.date, $0.steps) })
    }
    private var stats: StepStatistics { StepStatistics(values: values, range: period) }
    private var axisDates: [Date] {
        period.dates.enumerated().compactMap { index, day in
            guard index % (days == 7 ? 1 : 7) == 0 else { return nil }
            return StepDates.date(day)?.addingTimeInterval(12 * 3600)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.arguments.contains("-ui-testing-steps-chart") {
                Text("界面测试示例 · 非真实账号步数").font(.caption).foregroundStyle(SleepPalette.rose)
            }
            #endif
            HStack {
                SectionHeading(title: "每日步数", subtitle: "活动的每一步，都有迹可循")
                Spacer()
                Button { showRules = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("步数统计规则")
            }
            Picker("步数来源", selection: Binding(get: { source }, set: { sourceOverride = $0 })) {
                Text("蓝牙设备").tag(StepDisplaySource.device)
                Text("系统健康").tag(StepDisplaySource.health)
            }
                .pickerStyle(.segmented).accessibilityIdentifier("stepsSource")
            if deviceMode {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                    Text("界面测试示例 · 非真实设备步数").font(.caption).foregroundStyle(SleepPalette.rose)
                }
                #endif
                if !deviceSteps.devices.isEmpty {
                    Picker("设备", selection: Binding(get: { selectedDevice ?? deviceSteps.latest?.device ?? "" }, set: { selectedDevice = $0 })) {
                        ForEach(deviceSteps.devices) { Text("\($0.deviceName) · \($0.device.suffix(4))").tag($0.device) }
                    }.pickerStyle(.menu).accessibilityIdentifier("stepsDevicePicker")
                }
                Text("设备当天累计值，重连后自动更新。不与系统健康或其他设备相加。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("近 \(days) 天累计").font(.caption).foregroundStyle(SleepPalette.muted)
                    Text(stats.recordedDays == 0 ? "—" : stats.total.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("有记录日的日均").font(.caption).foregroundStyle(SleepPalette.muted)
                    Text(stats.average.map { Int($0.rounded()).formatted() } ?? "—").font(.system(size: 22, weight: .semibold, design: .rounded))
                }
            }.foregroundStyle(SleepPalette.ink)
            if stats.recordedDays > 0 {
                Chart(period.dates, id: \.self) { day in
                    if let count = values[day] {
                        BarMark(x: .value("日期", StepDates.date(day)!, unit: .day), y: .value("步数", count), width: .ratio(0.65))
                            .foregroundStyle(deviceMode ? SleepPalette.deep : SleepPalette.teal).cornerRadius(3)
                        if count == 0 { PointMark(x: .value("日期", StepDates.date(day)!, unit: .day), y: .value("步数", 0)).foregroundStyle(SleepPalette.rose) }
                    }
                }.chartXScale(domain: StepDates.date(period.start)!...StepDates.calendar.date(byAdding: .day, value: 1, to: StepDates.date(period.end)!)!)
                    .chartXAxis { AxisMarks(values: axisDates) { value in
                        AxisValueLabel { if let date = value.as(Date.self) { Text(String(StepDates.format(date).suffix(5))).font(.system(size: 9)) } }
                    } }.frame(height: 170).environment(\.calendar, StepDates.calendar).environment(\.timeZone, StepDates.timeZone)
                    .accessibilityIdentifier("stepsChart")
            } else {
                Label(deviceMode ? "设备尚未返回这段时间的每日步数" : "尚未读取这段时间的系统步数", systemImage: "figure.walk")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted).frame(maxWidth: .infinity, minHeight: 110)
            }
            Text("有记录 \(stats.recordedDays) 天 · 其中 0 步 \(stats.zeroDays) 天 · 未记录 \(stats.missingDays) 天")
                .font(.caption).foregroundStyle(SleepPalette.muted)
            if deviceMode {
                if let latest = deviceDays.max(by: { $0.readAt < $1.readAt }) {
                    Text("已保存在本机 · 最近读取 \(latest.readAt.formatted(date: .abbreviated, time: .shortened)) · \(latest.dayBasis)")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                }
                Text("今天的值是读取时的累计，可能还会增加；有日汇总才记入统计，零散分钟数据不补成全天。需要更新时在“监测与设备”重连设备即可。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                if let error = deviceSteps.saveError { Text(error).font(.caption).foregroundStyle(SleepPalette.rose) }
            } else {
                Text("可在健康页更新系统数据。开启账号自动同步后，已有步数会同步至平台；本页只展示本机实际读取的记录。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }
            ForEach(Array(period.dates.reversed()), id: \.self) { day in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(day); Spacer(); Text(values[day].map { "\($0.formatted()) 步" } ?? "未记录").monospacedDigit() }.font(.system(size: 13))
                    if deviceMode, let row = deviceDays.first(where: { $0.day == day }) {
                        Text("蓝牙设备 · \(row.deviceName) · \(row.dayBasis)").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                        Text("本机已保存 · 读取于 \(row.readAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    } else if !deviceMode, let row = local.first(where: { $0.date == day }) {
                        Text("系统健康汇总 · 读取于 \(row.measuredAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    }
                }.padding(.vertical, 4)
                Divider()
            }
        }.sheet(isPresented: $showRules) {
                NavigationStack { ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("同一天，只算一次").font(.title2.bold())
                        Text("蓝牙设备按设备与日期分别保存。重复读取更新当天累计值，不相加；不同设备分别查看，不能相加。设备只返回今天步数时，历史日期显示未记录，不用零散分钟包拼凑。启用自动同步时会同步到当前账号，可在个人页关闭。")
                        Text("系统健康采用每日汇总，不把手机与设备的原始条目相加。同一天的多来源记录分别查看，不重复累加。")
                        Text("真实的 0 步会计入日均。没有记录的日期留空，不按 0 步处理。日均 = 周期累计 ÷ 有记录的天数。")
                        Text("系统健康及已验证的 BIO 日累计采用北京时间（UTC+8）；其他设备日汇总沿用设备记录日期并单独标注。图中的空白表示没有记录，底部圆点表示真实 0 步。这里展示本机记录，账号同步在后台独立完成。")
                    }.font(.subheadline).padding(24)
                }.navigationTitle("步数统计说明").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showRules = false } } }
                }.presentationDetents([.medium, .large])
            }
    }
}

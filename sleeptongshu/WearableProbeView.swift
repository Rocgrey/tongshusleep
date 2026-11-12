import SwiftUI
import Charts

struct WearableProbePanel: View {
    @ObservedObject var client: WearableProbeClient
    var connected = false
    @State private var showsReport = false
    @EnvironmentObject private var rawSync: RawSensorSyncStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Label("设备数据接入", systemImage: "waveform.path.ecg").font(.system(size: 16, weight: .semibold))
                Spacer()
                if client.isBusy { ProgressView().controlSize(.small) }
            }
            Text(client.status).font(.system(size: 12)).foregroundStyle(SleepPalette.teal)
            Label("连接后自动采集原始信号", systemImage: "waveform")
                .font(.subheadline).accessibilityIdentifier("rawSensorAutomatic")
            Text("识别设备后逐类采集约 20 秒，再读取历史数据。原始包先保存到本机；登录且开启账号自动同步时分批上传，断网后重试。这不是整夜连续采集。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
            if let report = client.report {
                DeviceBatteryView(reading: client.battery, isCurrent: connected, isReading: client.isBusy, deviceName: report.deviceName)
                Text(report.deviceName).font(.system(size: 12, weight: .medium)).foregroundStyle(SleepPalette.muted)
                Label("本次读取 \(report.startedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                HStack(alignment: .top, spacing: 24) {
                    number("设备当天步数", value: report.currentSteps.map(String.init) ?? "—")
                    number("已收历史记录", value: "\(report.records.count)")
                }
                Text("\(report.channels.filter { $0.received > 0 }.count) 类历史数据已返回 · 连接后自动读取")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                Text("原始信号 \(report.rawSensorPackets?.count ?? 0) 包 · 历史原文 \(report.records.count) 包")
                    .font(.subheadline).monospacedDigit().accessibilityIdentifier("rawSensorCounts")
                if let message = client.savedVitalsMessage {
                    Text(message).font(.caption).foregroundStyle(SleepPalette.teal)
                }
                if client.report?.rawSensorStatus != nil {
                    Text(rawSync.message).font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let history = client.history, !history.vitals.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), alignment: .leading)], alignment: .leading, spacing: 12) {
                        preview("最近心率", value: history.rows.reversed().compactMap(\.heart).first, unit: "次/分")
                        preview("最近血氧", value: history.rows.reversed().compactMap(\.oxygen).first, unit: "%")
                        preview("HRV · SDNN", value: history.rows.reversed().compactMap(\.sdnn).first, unit: "毫秒")
                    }
                }
                Button { showsReport = true } label: { Label("查看本次接入报告", systemImage: "doc.text.magnifyingglass") }
                    .font(.system(size: 13)).accessibilityIdentifier("wearableProbeReport")
            }
            Text("连接后自动读取，约需 1～3 分钟。有效心率、血氧、血压和 HRV 会保存到体征记录。睡眠输入还不是深睡、浅睡或快速眼动。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }.sheet(isPresented: $showsReport) { WearableProbeView(client: client) }
    }
    private func number(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func preview(_ title: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(SleepPalette.muted)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")
                .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(SleepPalette.muted)
        }.accessibilityElement(children: .combine)
    }
}

struct WearableProbeView: View {
    @ObservedObject var client: WearableProbeClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let report = client.report {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(report.deviceName).font(.system(size: 23, weight: .bold))
                            Text(client.isBusy ? client.status : "\(report.startedAt.formatted(date: .abbreviated, time: .shortened)) · 本机报告")
                                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                            field("实际返回型号", report.observedModel ?? "未返回")
                            field("实际返回固件", report.observedFirmware ?? "未返回")
                            DeviceBatteryView(reading: client.battery, isCurrent: client.isConnected, isReading: client.isBusy, deviceName: report.deviceName)
                            field("用户提供的版本", report.userReportedFirmware ?? "未提供")
                            if let value = report.observedAlgorithm { field("设备血压版本字段", value) }
                            Text("用户提供的版本仅供核对，实际兼容性以本次响应为准。")
                                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        }
                        if let history = client.history {
                            WearableHealthHistoryView(history: history, savedMessage: client.savedVitalsMessage)
                        }
                        RawSensorReportView(report: report)
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "各类数据读取情况", subtitle: "空目录表示这次没有记录；未响应还不能判断是否支持")
                            if report.finishedAt == nil {
                                Label(client.isBusy ? "读取尚未结束，请等各通道检查完成后再分享报告。" : "这份报告没有读取结束标记，可能只包含部分通道；请重新连接并等待读取结束。", systemImage: "clock.badge.exclamationmark")
                                    .font(.caption).foregroundStyle(SleepPalette.rose).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("incompleteWearableProbe")
                            }
                            if report.channels.contains(where: { $0.received > 0 }) {
                                Chart(report.channels.filter { $0.received > 0 }) { channel in
                                    BarMark(x: .value("收到包数", channel.received), y: .value("通道", channel.name))
                                        .foregroundStyle(channel.type == 4 ? SleepPalette.deep : SleepPalette.teal).cornerRadius(3)
                                }.frame(height: CGFloat(max(70, report.channels.filter { $0.received > 0 }.count * 34)))
                                    .accessibilityLabel("各通道实际收到的包数")
                            }
                            ForEach(report.channels) { channel in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(channel.name).font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text("\(channel.received) 条").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(channel.received > 0 ? SleepPalette.teal : SleepPalette.muted)
                                    }
                                    Text(channel.state).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                                    if channel.available > 0 { Text("目录中约 \(channel.available) 条，本次在读取上限内分段获取").font(.system(size: 11)).foregroundStyle(SleepPalette.muted) }
                                    if let start = channel.requestedStart, let end = channel.requestedEnd {
                                        Text("本次请求序号 \(start)～\(end) · 实收 \(channel.received) 包")
                                            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                                    }
                                }
                                Divider()
                            }
                        }
                        let heart = report.records.filter { $0.heartRate != nil }.sorted { $0.sequence < $1.sequence }
                        if !heart.isEmpty && client.history?.rows.contains(where: { $0.heart != nil }) != true {
                            SectionHeading(title: "已返回的心率", subtitle: "单位：次/分 · 按设备记录顺序排列")
                            Chart(heart) { record in
                                PointMark(x: .value("记录序号", record.sequence), y: .value("心率", record.heartRate!))
                                    .foregroundStyle(SleepPalette.teal)
                            }.frame(height: 160).chartYAxis { AxisMarks(position: .leading) }
                                .accessibilityLabel("本次返回的历史心率图")
                            Text("这是设备记录的心率，尚未确认时间含义，不计入睡眠平均值；记录缺口不连线。")
                                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                        }
                        SectionHeading(title: "接下来能做什么", subtitle: "先确认信号，再研究算法")
                        Text("心跳间隔、光学脉搏波或三轴加速度有记录，才有进一步研究的依据。还需要确认单位、每秒采集次数、有效标记和整夜是否连续。只返回心率均值、步数或睡眠输入，不能据此可靠计算深睡、浅睡和快速眼动。")
                            .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(5)
                        Text(report.note).font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                        if let url = client.reportURL {
                            ShareLink(item: url) { Label("分享接入报告 JSON", systemImage: "square.and.arrow.up") }
                                .disabled(client.isBusy)
                                .accessibilityIdentifier("shareWearableProbe")
                            Text("报告含健康记录，分享前请确认接收人。")
                                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        }
                        DisclosureGroup("读取详情") {
                            Text(report.events.isEmpty ? "暂无额外提示" : report.events.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                            Text("被丢弃的格式或校验片段：\(report.rejectedFrames)").font(.system(size: 11))
                        }.font(.system(size: 13))
                    } else {
                        ContentUnavailableView("还没有接入报告", systemImage: "sensor", description: Text("连接支持的设备后会自动读取并保存在本机。"))
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
                .navigationTitle("设备接入报告").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(SleepPalette.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 12))
    }
}

/// Charts only contain decoded measurements; missing channels never become zeroes.
private struct WearableHealthHistoryView: View {
    let history: WearableDecodedHistory
    let savedMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 135), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "已读取的体征", subtitle: "按设备测量时间展示 · 缺失数据不补零")
            if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(SleepPalette.teal) }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                metric("最近心率", value: latest(\.heart), unit: "次/分", icon: "heart.fill", tint: SleepPalette.rose)
                metric("最近血氧", value: latest(\.oxygen), unit: "%", icon: "drop.fill", tint: SleepPalette.teal)
                metric("血压高压 / 低压", text: pressure, unit: "mmHg", icon: "waveform.path.ecg", tint: SleepPalette.deep)
                metric("HRV · SDNN", value: latest(\.sdnn), unit: "毫秒", icon: "waveform", tint: SleepPalette.deep)
                metric("HRV · RMSSD", value: latest(\.rmssd), unit: "毫秒", icon: "waveform.path", tint: SleepPalette.teal)
                metric("设备压力", value: latest(\.stress), unit: "/100", icon: "leaf", tint: SleepPalette.rose)
                if latest(\.temperature) != nil { metric("设备估算体温", value: latest(\.temperature), unit: "℃", icon: "thermometer.medium", tint: SleepPalette.rose) }
                if latest(\.respiration) != nil { metric("呼吸率", value: latest(\.respiration), unit: "次/分", icon: "lungs", tint: SleepPalette.teal) }
            }
            let heart = history.rows.filter { $0.heart != nil }
            if !heart.isEmpty {
                Chart(heart) { row in
                    PointMark(x: .value("测量时间", row.date), y: .value("心率", row.heart!))
                        .foregroundStyle(SleepPalette.rose)
                }.frame(height: 165).chartYAxis { AxisMarks(position: .leading) }
                    .accessibilityLabel("设备真实历史心率")
            }
            let oxygen = history.rows.filter { $0.oxygen != nil }
            if !oxygen.isEmpty {
                Chart(oxygen) { row in
                    PointMark(x: .value("测量时间", row.date), y: .value("血氧", row.oxygen!))
                        .foregroundStyle(SleepPalette.teal)
                }.frame(height: 130).chartYAxis { AxisMarks(position: .leading) }
                    .accessibilityLabel("设备真实历史血氧")
            }
            if let start = history.rows.first?.date, let end = history.rows.last?.date {
                Text("记录时间：\(start.formatted(date: .abbreviated, time: .shortened)) 至 \(end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }
            Text("HRV 表示心跳间隔的变化，两种算法值分开展示；压力按设备疲劳值换算，越高表示设备估计的压力越大。仅显示有效测量，不从原始编码猜测结果。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
            if history.skippedTimes > 0 {
                Text("\(history.skippedTimes) 条记录的设备时间尚未确认，保留在报告中，暂不写入日常体征。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }
        }
    }
    private func latest(_ key: KeyPath<WearableHealthRow, Double?>) -> Double? { history.rows.reversed().compactMap { $0[keyPath: key] }.first }
    private var pressure: String {
        guard let row = history.rows.last(where: { $0.systolic != nil && $0.diastolic != nil }) else { return "—" }
        return "\(Int(row.systolic!)) / \(Int(row.diastolic!))"
    }
    private func metric(_ title: String, value: Double?, unit: String, icon: String, tint: Color) -> some View {
        metric(title, text: value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", unit: unit, icon: icon, tint: tint)
    }
    private func metric(_ title: String, text: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(tint)
            Text(text).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
            .accessibilityIdentifier("wearableMetric-\(title)")
    }
}

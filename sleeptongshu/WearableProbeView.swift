import SwiftUI
import Charts

struct WearableProbePanel: View {
    @ObservedObject var client: WearableProbeClient
    var connected = false
    @State private var showsReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Label("设备数据接入", systemImage: "waveform.path.ecg").font(.system(size: 16, weight: .semibold))
                Spacer()
                if client.isBusy { ProgressView().controlSize(.small) }
            }
            Text(client.status).font(.system(size: 12)).foregroundStyle(SleepPalette.teal)
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
                Button { showsReport = true } label: { Label("查看本次接入报告", systemImage: "doc.text.magnifyingglass") }
                    .font(.system(size: 13)).accessibilityIdentifier("wearableProbeReport")
            }
            Text("连接后自动读取，约需 1～3 分钟。心跳间隔会读取较长历史，其他通道先检查一段记录。睡眠输入还不是深睡、浅睡或快速眼动。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }.sheet(isPresented: $showsReport) { WearableProbeView(client: client) }
    }
    private func number(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
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
                            field("用户提供的版本", report.userReportedFirmware ?? "未提供")
                            if let value = report.observedAlgorithm { field("设备血压版本字段", value) }
                            Text("用户提供的版本仅供核对，实际兼容性以本次响应为准。")
                                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "各类数据读取情况", subtitle: "空目录表示这次没有记录；未响应还不能判断是否支持")
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
                                    if channel.available > 0 { Text("目录中共 \(channel.available) 条，本次仅取其中一段").font(.system(size: 11)).foregroundStyle(SleepPalette.muted) }
                                    if let start = channel.requestedStart, let end = channel.requestedEnd {
                                        Text("本次请求序号 \(start)～\(end) · 实收 \(channel.received) 包")
                                            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                                    }
                                }
                                Divider()
                            }
                        }
                        let heart = report.records.filter { $0.heartRate != nil }.sorted { $0.sequence < $1.sequence }
                        if !heart.isEmpty {
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

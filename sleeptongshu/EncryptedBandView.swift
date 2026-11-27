import SwiftUI
import Charts

/// Existing bindings continue syncing; daily device controls do not expose credential import.
struct EncryptedBandPanel: View {
    @EnvironmentObject private var scanner: RingScanner
    @EnvironmentObject private var band: EncryptedBandStore
    @State private var showsDetails = false

    var body: some View {
        if scanner.encryptedBandChannelDetected || band.deviceID != nil {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Label("加密设备同步", systemImage: "lock.shield").font(.headline)
                Text(band.phaseText).font(.subheadline).foregroundStyle(SleepPalette.teal)
                    .accessibilityIdentifier("encryptedBandStatus")
                if band.isBusy {
                    if let progress = band.progress { ProgressView(value: progress).tint(SleepPalette.teal) }
                    else { ProgressView() }
                    Button("停止本次读取", role: .cancel) { band.stop() }
                }
                if let level = band.battery {
                    DeviceBatteryView(reading: DeviceBatteryReading(level: level, isPercentage: true), isCurrent: band.isBusy,
                                      isReading: false, deviceName: band.deviceName)
                }
                if let steps = band.steps { Label("设备当天步数 \(steps)", systemImage: "figure.walk").font(.subheadline) }
                if !band.currentActivityDays.isEmpty {
                    let days = Array(band.currentActivityDays.prefix(7).reversed())
                    Text("设备每日步数").font(.subheadline.weight(.medium))
                    Chart(days) { day in
                        BarMark(x: .value("日期", String(day.day.suffix(5))), y: .value("步数", day.steps))
                            .foregroundStyle(SleepPalette.teal).cornerRadius(3)
                    }.frame(height: 150).accessibilityLabel("蓝牙设备每日步数，最近最多七个有记录日期")
                    Text("来源：蓝牙设备日汇总 · 同一天更新替换，不与系统健康步数相加。缺少记录的日期不补零。")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let date = band.lastReadAt {
                    Text("最近读取 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let summary = band.summary { Text(summary).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                if band.deviceID != nil {
                    DisclosureGroup("读取详情", isExpanded: $showsDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("当前为实测适配：支持的历史文件才会导入，不支持的格式保存在本机。没有分期不生成睡眠图，不删除设备历史。启用自动同步后，已有记录同步到当前账号。")
                            Text(band.diagnostic).font(.caption2.monospaced()).textSelection(.enabled)
                            ShareLink(item: band.diagnostic) { Label("分享读取诊断", systemImage: "square.and.arrow.up") }
                        }.font(.caption).padding(.top, 10)
                    }.font(.subheadline)
                }
            }
        }
    }
}

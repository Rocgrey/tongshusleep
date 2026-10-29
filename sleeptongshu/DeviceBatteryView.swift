import SwiftUI

struct DeviceBatteryView: View {
    let reading: DeviceBatteryReading?
    let isCurrent: Bool
    let isReading: Bool
    let deviceName: String?

    private var tint: Color { reading?.isLow == true ? .red : SleepPalette.teal }
    private var symbol: String {
        let step = Int(((reading?.fraction ?? 0) * 4).rounded()) * 25
        return "battery.\(step)percent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(isCurrent ? "设备电量" : "最近读取的电量", systemImage: symbol)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                Spacer(minLength: 8)
                Text(reading?.text ?? (isReading ? "正在读取…" : "暂未取得"))
                    .font(.system(size: reading == nil ? 13 : 22, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(reading == nil ? SleepPalette.muted : SleepPalette.ink)
                    .accessibilityIdentifier("deviceBatteryValue")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(SleepPalette.line)
                    Capsule().fill(tint).frame(width: geometry.size.width * (reading?.fraction ?? 0))
                }
            }.frame(height: 6).accessibilityHidden(true)
            if let reading {
                if !isCurrent {
                    Text("\(deviceName ?? "设备") · \(reading.readAt.formatted(.dateTime.hour().minute())) 读取，当前已断开")
                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                }
                if !reading.isPercentage {
                    Text("设备只提供电量格数，暂不显示百分比。")
                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                }
                if reading.isLow {
                    Text("电量偏低，建议在睡前充电。")
                        .font(.system(size: 11)).foregroundStyle(tint)
                }
            } else if !isReading {
                Text("设备暂未返回电量，可在下次连接时自动读取。")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
        }
    }
}

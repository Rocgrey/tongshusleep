import SwiftUI
import Charts

struct RawSensorReportView: View {
    let report: WearableProbeReport
    @State private var selectedType: UInt32 = 16
    private var packets: [RawSensorPacket] { report.rawSensorPackets ?? [] }
    private var types: [UInt32] { Array(Set(packets.map(\.sensorType))).sorted() }
    private var selected: RawSensorPacket? { packets.first { $0.sensorType == (types.contains(selectedType) ? selectedType : types.first) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "原始传感器信号", subtitle: "原始值单独保存，不作为睡眠或体征结果")
            Text(report.rawSensorStatus ?? "本次尚未收到原始信号").font(.subheadline).foregroundStyle(SleepPalette.muted)
            ForEach(report.rawSensorAttempts ?? [], id: \.self) { type in
                let count = packets.filter { $0.sensorType == type }.count
                Text("类型 \(type)：\(count > 0 ? "已收到 \(count) 包" : "本次未返回，不代表不支持")")
                    .font(.caption).foregroundStyle(count > 0 ? SleepPalette.teal : SleepPalette.muted)
            }
            if !packets.isEmpty {
                Text("\(packets.count) 个包 · \(packets.reduce(0) { $0 + $1.sensorDataList.count }) 个原始值").font(.headline)
                Picker("传感器", selection: $selectedType) {
                    ForEach(types, id: \.self) { type in Text(packets.first { $0.sensorType == type }!.sensorName).tag(type) }
                }.pickerStyle(.menu).accessibilityIdentifier("rawSensorPicker")
                if let packet = selected {
                    Text("序号 \(packet.sensorSeq) · 设备原始秒数 \(String(packet.sensorSeconds))").font(.caption).foregroundStyle(SleepPalette.muted)
                    Chart(Array(packet.sensorDataList.prefix(240).enumerated()), id: \.offset) { item in
                        LineMark(x: .value("包内数值序号", item.offset), y: .value("原始值", item.element))
                            .foregroundStyle(packet.sensorType == 512 ? SleepPalette.rose : SleepPalette.teal)
                    }.frame(height: 160).accessibilityElement(children: .contain).accessibilityIdentifier("rawSensorChart")
                    Text("首个包的前 240 个值，横轴为包内顺序。采样率、单位和多通道排列尚待厂家确认，不把它当作连续秒数或单一路波形。")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                }
            }
            Text("协议编号：16 为加速度；512 为生物电阻抗；2 才是光学脉搏波。包长度不代表采样率，原始数值不直接表示深睡或快速眼动。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
        }
    }
}

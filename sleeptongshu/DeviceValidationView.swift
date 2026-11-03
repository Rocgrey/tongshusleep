import SwiftUI
import Charts

struct DeviceValidationView: View {
    @ObservedObject var store: DeviceValidationStore
    @Environment(\.dismiss) private var dismiss
    @State private var export: URL?
    @State private var section = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let report = store.report {
                        Text(report.status).font(.system(size: 19, weight: .semibold))
                        Text("\(report.startedAt.formatted(date: .numeric, time: .shortened)) · 固件 \(report.firmware)")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                        if report.origin != "真实设备验证" {
                            Text(report.origin).font(.system(size: 13, weight: .medium)).foregroundStyle(SleepPalette.awake)
                        }
                        if report.finishedAt == nil { ProgressView("正在收集，完成后自动保存报告").font(.system(size: 12)) }
                        HStack(spacing: 12) {
                            count(report.sleepRecords.count, title: "睡眠段")
                            count(report.vitals.count, title: "体征条")
                            count(report.blocks.count, title: "信号块")
                        }
                        Text(report.conclusion).font(.system(size: 14)).lineSpacing(5)
                        Picker("报告内容", selection: $section) {
                            Text("接口结果").tag(0)
                            Text("信号图").tag(1)
                            Text("全部字段").tag(2)
                        }.pickerStyle(.segmented).accessibilityIdentifier("validationSections")
                        if section == 0 { results(report) }
                        else if section == 1 { signals(report) }
                        else { fields(report) }
                        Divider()
                        if let error = store.storageError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                        Button {
                            if store.save(force: true) { export = store.exportURL }
                        } label: { Label("准备导出验证报告", systemImage: "square.and.arrow.up") }
                            .disabled(report.finishedAt == nil).accessibilityIdentifier("prepareValidationExport")
                        if let export {
                            ShareLink(item: export) { Label("分享完整报告文件", systemImage: "doc.text") }
                        }
                        ShareLink(item: report.summary) { Label("分享文字摘要", systemImage: "text.bubble") }
                        Text("报告保存在本机，包含测量时间和健康记录，分享时由你选择接收方。下一次验证会更新这份报告。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                    } else {
                        ContentUnavailableView("暂无验证报告", systemImage: "waveform.path.ecg", description: Text("开启设备数据验证，再连接设备。"))
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
                .navigationTitle("设备数据验证").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func count(_ value: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func results(_ report: DeviceValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            result("历史睡眠与体征", detail: report.transportStatus, icon: "moon.zzz")
            result("逐次心跳间隔", detail: report.rrStatus, icon: "heart")
            result("连续脉搏波", detail: report.waveStatus, icon: "waveform.path.ecg")
            result("身体活动信号", detail: report.motionStatus, icon: "figure.walk")
            Text("心率、血氧、血压、HRV 和压力是设备计算的结果。历史字段来自同步后的本地历史库，可能包括此前缓存；本次未生成记录时也可能为空。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            if report.captureLimitReached || report.inventoryTruncated {
                Text("达到采样或快照上限，报告仅包含部分数据。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.awake)
            }
            DisclosureGroup("验证过程") {
                Text(report.events.joined(separator: "\n")).font(.system(size: 11)).textSelection(.enabled).padding(.top, 8)
            }.font(.system(size: 13))
            DisclosureGroup("连接与设备能力信息") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("能力编号仅作核对，不能证明原始信号可用。")
                    ForEach(report.capabilityCodes.keys.sorted(), id: \.self) { key in
                        Text("\(key)：\(report.capabilityCodes[key] ?? 0)")
                    }
                    ForEach(report.bluetoothServices.keys.sorted(), id: \.self) { key in
                        Text("服务 \(key)")
                        Text((report.bluetoothServices[key] ?? []).joined(separator: "\n"))
                    }
                }.font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
            }.font(.system(size: 13))
        }
    }

    private func result(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(SleepPalette.teal)
            Text(detail).font(.system(size: 13)).lineSpacing(4)
        }
    }

    @ViewBuilder private func signals(_ report: DeviceValidationReport) -> some View {
        if !report.blocks.isEmpty {
            Text("逐次心跳的候选数据").font(.system(size: 16, weight: .semibold))
            if let block = report.blocks.first(where: { !$0.littleEndianValues.isEmpty }) {
                signalChart(block.littleEndianValues.prefix(300).map(Double.init), color: SleepPalette.deep)
                Text("\(block.date) \(block.time) · 第 \(block.number) 块，预览前 300 点。横轴为样本顺序，纵轴为转换值；单位和缩放尚未确认，不代表毫秒。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            } else {
                Text("收到了数据字节，但没有可按双字节展开的转换值。已保留字节供进一步核对。")
                    .font(.system(size: 13))
            }
            ForEach(report.blocks.prefix(12)) { block in
                Text("\(block.date) \(block.time) · 原始 \(block.raw.count) 字节 · 转换 \(block.converted.count) 字节")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
        }
        if !report.wavePreview.isEmpty {
            Text("设备主动返回的脉搏波候选值").font(.system(size: 16, weight: .semibold))
            signalChart(Array(report.wavePreview.prefix(300)), color: SleepPalette.teal)
            Text("横轴为样本顺序，纵轴为设备数值；尚未确认采样率、单位或是否为完整波形，不用于睡眠分期。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
        if report.blocks.isEmpty && report.wavePreview.isEmpty {
            ContentUnavailableView("暂无信号可画", systemImage: "waveform", description: Text("本次没有收到候选信号，不会用心率结果拼接成波形。"))
        }
    }

    private func signalChart(_ values: [Double], color: Color) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("样本顺序", item.offset), y: .value("设备转换值", item.element)).foregroundStyle(color)
        }.chartXAxisLabel("样本顺序").frame(height: 180)
    }

    private func fields(_ report: DeviceValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("已检查 \(report.fields.count) 类历史字段").font(.system(size: 15, weight: .semibold))
            Text("范围包括零值和占位值，不等于有效测量；样例有限，未知字段保留待确认，不写入健康指标。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            ForEach(report.fields) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.path).font(.system(size: 13, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Text(field.meaning).font(.system(size: 12)).lineSpacing(4)
                    Text("\(field.occurrences) 个已采样窗口 · \(field.values) 个值")
                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                    if let low = field.minimum, let high = field.maximum {
                        Text("采样值范围：\(low.formatted()) 至 \(high.formatted())")
                            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                    }
                    Text("样例：\(field.examples.joined(separator: "、"))")
                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
        }
    }
}

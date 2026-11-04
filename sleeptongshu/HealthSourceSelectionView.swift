import SwiftUI

struct HealthSourceSelectionView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthManualProfile") private var manualProfile = false
    @AppStorage("healthReferenceAge") private var ageText = ""
    @AppStorage("healthReferenceSex") private var sexRaw = HealthReferenceSex.unspecified.rawValue
    @State private var clear = false
    @State private var exportDocument: SleepBackupDocument?
    @State private var showsExport = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(HealthMetric.allCases) { metric in
                        VStack(alignment: .leading, spacing: 5) {
                            Picker(selection: Binding(get: { health.selections[metric.rawValue] ?? "" }, set: { health.select($0, for: metric) })) {
                                Text("未选择").tag("")
                                ForEach(health.sources(for: metric)) { source in Text(source.selectionLabel).tag(source.id) }
                                if let selected = health.selections[metric.rawValue], !selected.isEmpty,
                                   !health.sources(for: metric).contains(where: { $0.id == selected }) {
                                    Text("上次选择的来源（本次无记录）").tag(selected)
                                }
                            } label: { Label(metric.title, systemImage: metric.symbol) }
                                .accessibilityIdentifier("healthSource-\(metric.rawValue)")
                            if let source = health.source(for: metric) {
                                Text(source.label).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                                if !source.hardwareIdentified {
                                    Text("来源未提供独立设备标识，同名同型号设备可能无法再区分。")
                                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                                }
                            }
                        }
                    }
                } header: { Text("每一项，选自己的设备") }
                footer: { Text("首次读取会按该项目的记录数量选择一个来源；以后保留你的选择，不自动换设备。不同来源不相加。这里的选择用于健康概览，睡眠报告导入在监测与设备中另行选择。") }
                    .disabled(health.isLoading)
                Section {
                    Toggle("手动填写参考资料", isOn: $manualProfile).accessibilityIdentifier("manualHealthProfile")
                    if manualProfile {
                        TextField("实际年龄（20～79 岁）", text: $ageText).keyboardType(.numberPad).accessibilityIdentifier("healthReferenceAge")
                            .onChange(of: ageText) { _, value in ageText = String(value.filter(\.isNumber).prefix(3)) }
                        Picker("研究参考分组", selection: $sexRaw) {
                            ForEach(HealthReferenceSex.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                    } else {
                        LabeledContent("系统健康中的实际年龄", value: health.snapshot?.age.map { "\($0) 岁" } ?? "未读取到")
                        LabeledContent("系统健康中的参考分组", value: (health.snapshot?.referenceSex ?? .unspecified).title)
                    }
                } header: { Text("心肺参考年龄所需资料") }
                footer: { Text("研究按男女分组提供参考表；不选择时不估算。年龄资料只用于核对适用范围，不用睡眠或 HRV 随意换算几岁。修改参考分组会改变估算结果。") }
                Section("读取与本机快照") {
                    Button { Task { await health.refresh() } } label: { Label(health.isLoading ? health.progress : "重新读取系统健康", systemImage: "arrow.clockwise") }
                        .disabled(health.isLoading)
                    if let date = health.snapshot?.readAt { LabeledContent("上次读取", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Button {
                        do { exportDocument = SleepBackupDocument(data: try health.export()); showsExport = true }
                        catch { self.error = error.localizedDescription }
                    } label: { Label("导出健康快照 JSON", systemImage: "square.and.arrow.up") }.disabled(health.snapshot == nil || health.isLoading)
                    Button("清空本 App 的健康快照", role: .destructive) { clear = true }.disabled(health.isLoading)
                    Text("只清理本 App 保存的健康概览快照，不影响系统健康、睡眠报告或蓝牙体征。下次读取可重新生成。导出包含健康记录，请自行选择接收人。")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
            }.scrollContentBackground(.hidden).background(SleepPalette.background)
                .navigationTitle("来源与参考资料").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("清空本 App 的健康快照？", isPresented: $clear, titleVisibility: .visible) {
                    Button("清空健康快照", role: .destructive) {
                        do { try health.clearSnapshot() } catch { self.error = error.localizedDescription }
                    }
                }
                .fileExporter(isPresented: $showsExport, document: exportDocument, contentType: .json, defaultFilename: "sleeptongshu-health-snapshot") { result in
                    if case .failure(let failure) = result { error = failure.localizedDescription }
                }
                .alert("系统健康", isPresented: Binding(get: { error != nil || health.message != nil }, set: { if !$0 { error = nil; health.message = nil } })) {
                    Button("知道了", role: .cancel) { error = nil; health.message = nil }
                } message: { Text(error ?? health.message ?? "") }
        }
    }
}

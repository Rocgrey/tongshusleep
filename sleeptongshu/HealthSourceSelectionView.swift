import SwiftUI
import SwiftData

struct HealthSourceSelectionView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.modelContext) private var context
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
                    Label("统一读取系统健康", systemImage: "heart.text.clipboard")
                    Text("使用系统健康中已有且获准读取的记录，不需要逐项选择设备。设备换了，只要记录已写入系统健康，刷新后就可以查看。")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                }
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
                    Button { Task { await health.refresh(in: context) } } label: { Label(health.isLoading ? health.progress : "重新读取系统健康", systemImage: "arrow.clockwise") }
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
                if let sources = health.snapshot?.sources, !sources.isEmpty {
                    Section("已读取的记录来源") {
                        ForEach(sources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.appName)
                                Text(source.deviceName).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                            }
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(SleepPalette.background)
                .navigationTitle("健康设置").navigationBarTitleDisplayMode(.inline)
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

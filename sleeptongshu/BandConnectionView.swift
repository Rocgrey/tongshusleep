import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SleepBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BandConnectionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepRecord.end, order: .reverse) private var records: [SleepRecord]
    @EnvironmentObject private var scanner: BandScanner
    @AppStorage("sleepGoalHours") private var goal = 8.0
    @State private var exportDocument: SleepBackupDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var message: String?
    @State private var deleteSamples = false
    @State private var deleteAll = false
    @State private var showsEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "applewatch").font(.system(size: 29)).foregroundStyle(SleepPalette.teal)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(scanner.connectedName ?? "连接穿戴设备").font(.system(size: 17, weight: .semibold))
                                Text(scanner.status).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                            }
                        }
                        if let battery = scanner.battery { Label("电量 \(battery)%", systemImage: "battery.100percent").font(.system(size: 12)) }
                        if let model = scanner.modelNumber { Text("型号：\(model)").font(.system(size: 12)) }
                        if let value = scanner.liveHeartRate { Label("实时心率 \(value) 次/分", systemImage: "heart.fill").font(.system(size: 14)) }
                        if scanner.connectedName != nil || scanner.connectingID != nil {
                            Button("断开连接", role: .destructive) { scanner.disconnect() }
                        } else {
                            Button { scanner.isScanning ? scanner.stopScan() : scanner.scan() } label: {
                                Label(scanner.isScanning ? "停止扫描" : "扫描附近设备", systemImage: scanner.isScanning ? "stop.fill" : "magnifyingglass")
                                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("scanBand")
                        }
                    }.padding(.vertical, 8)
                } footer: {
                    Text("支持扫描手环、手表、戒指等 BLE 设备，读取公开的电量、型号与标准实时心率。历史睡眠需要厂商协议，当前尚未适配；请在真机验证。")
                }
                if !scanner.devices.isEmpty {
                    Section("附近设备 · \(scanner.devices.count)") {
                        ForEach(scanner.devices) { device in
                            Button { scanner.connect(device) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name).font(.system(size: 14))
                                        Text("信号 \(device.rssi) dBm · \(device.id.uuidString.prefix(8))").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                                    }
                                    Spacer()
                                    if scanner.connectingID == device.id { ProgressView() }
                                    else { Image(systemName: "chevron.right").font(.system(size: 11)) }
                                }
                            }.disabled(scanner.connectedName != nil || scanner.connectingID != nil)
                        }
                    }
                }
                Section("我的睡眠目标") {
                    Stepper(value: $goal, in: 5...12, step: 0.5) {
                        LabeledContent("每晚睡眠", value: "\(goal.formatted(.number.precision(.fractionLength(0...1)))) 小时")
                    }
                }
                Section {
                    LabeledContent("本机记录", value: "\(records.count) 条")
                    LabeledContent("其中示例", value: "\(records.filter { $0.source == .sample }.count) 条")
                    Button { showsEditor = true } label: { Label("添加睡眠记录", systemImage: "plus.circle") }
                    Button { prepareExport() } label: { Label("导出 JSON 备份", systemImage: "square.and.arrow.up") }.disabled(records.isEmpty)
                    Button { showsImporter = true } label: { Label("导入 JSON 备份", systemImage: "square.and.arrow.down") }
                } header: { Text("本地数据") } footer: { Text("无需账号，App 不上传记录。导出后可由你选择保存位置；相同 ID 的记录在导入时会跳过。") }
                Section("示例与清理") {
                    Button { loadSamples() } label: { Label("载入示例数据", systemImage: "sparkles") }
                        .disabled(records.contains { $0.source == .sample })
                    Button("移除示例数据", role: .destructive) { deleteSamples = true }
                        .disabled(!records.contains { $0.source == .sample })
                    Button("删除全部记录", role: .destructive) { deleteAll = true }.disabled(records.isEmpty)
                }
                Section {
                    LabeledContent("版本", value: "0.2.0")
                    Text("睡眠阶段及体征用于观察个人趋势，不用于医疗诊断。")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                } header: { Text("睡眠同书") }
            }
            .scrollContentBackground(.hidden).background(SleepPalette.background)
            .navigationTitle("设备与数据")
            .sheet(isPresented: $showsEditor) { SleepEditorView() }
            .onDisappear { scanner.stopScan() }
            .fileExporter(isPresented: $showsExporter, document: exportDocument, contentType: .json, defaultFilename: "sleeptongshu-backup") { result in
                switch result { case .success: message = "备份已导出。"; case .failure(let error): message = error.localizedDescription }
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
                do { try importBackup(result.get()) } catch { message = error.localizedDescription }
            }
            .alert("本地数据", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("移除示例后，手动记录将保留", isPresented: $deleteSamples, titleVisibility: .visible) {
                Button("移除示例数据", role: .destructive) { remove(records.filter { $0.source == .sample }) }
            }
            .confirmationDialog("删除全部记录？请先导出备份。", isPresented: $deleteAll, titleVisibility: .visible) {
                Button("删除全部记录", role: .destructive) { remove(records) }
            }
        }
    }

    private func prepareExport() {
        do { exportDocument = SleepBackupDocument(data: try SleepBackup(records: records.map(\.payload)).encode()); showsExporter = true }
        catch { message = error.localizedDescription }
    }

    private func importBackup(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10_000_000 else { throw SleepDataError.tooLarge }
        let backup = try SleepBackup.decode(Data(contentsOf: url))
        var ids = Set(records.map(\.id))
        var added = 0
        do {
            for payload in backup.records where ids.insert(payload.id).inserted {
                context.insert(SleepRecord(payload))
                added += 1
            }
            try context.save()
            message = "导入 \(added) 条，跳过 \(backup.records.count - added) 条重复记录。"
        } catch { context.rollback(); throw error }
    }

    private func remove(_ entries: [SleepRecord]) {
        entries.forEach { context.delete($0) }
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription }
    }

    private func loadSamples() {
        SampleSleepRecords.makeMonth().forEach { context.insert($0) }
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription }
    }
}

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

struct LocalDataView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepRecord.end, order: .reverse) private var records: [SleepRecord]
    @AppStorage("sleepGoalHours") private var goal = 8.0
    @State private var exportDocument: SleepBackupDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var message: String?
    @State private var deleteSamples = false
    @State private var deleteAll = false
    @State private var showsEditor = false

    var body: some View {
            List {
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
            .navigationTitle("本地数据").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showsEditor) { SleepEditorView() }
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

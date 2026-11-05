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
                    NavigationLink { HealthAccessGuide() } label: { Label("授权与设备同步指引", systemImage: "questionmark.circle") }
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

struct HealthAccessHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HealthAccessGuide()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct HealthAccessGuide: View {
    @Environment(\.openURL) private var openURL
    @State private var cannotOpen = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "heart.text.clipboard.fill").font(.system(size: 42)).foregroundStyle(SleepPalette.rose)
                Text("让健康记录在这里相遇").font(.system(size: 24, weight: .bold))
                guideStep("1", title: "允许读取", text: "打开健康 App → 右上角头像 → App 与服务（部分系统显示为 App）→ sleeptongshu，开启你希望读取的项目。若找不到本 App，先回健康页点一次“读取系统健康”。")
                guideStep("2", title: "先把设备记录同步过来", text: "在手环、手表或戒指的配套 App 中完成同步，并开启向系统健康共享数据。只有配套 App 支持且实际写入的项目，才能在这里读取。蓝牙已连接不代表记录已写入系统健康。")
                guideStep("3", title: "确认系统里确实有记录", text: "在健康 App 中打开步数、心率或睡眠，查看“显示所有数据”和“数据来源与访问权限”。确认有近期记录后，回到 sleeptongshu 更新健康数据，无需逐项选择设备。")
                Divider()
                Label("为什么身体年龄仍是数据不足？", systemImage: "figure.mind.and.body").font(.system(size: 16, weight: .semibold))
                Text("目前估算的是心肺参考年龄，需要实际年龄、参考分组，以及近 30 个完整自然日至少 3 天的最大摄氧量记录。设备不提供这项数据时，授权也不会凭空产生记录；其他健康数据仍可正常查看。")
                    .font(.system(size: 14)).foregroundStyle(SleepPalette.muted).lineSpacing(5)
                Text("系统不会告诉 App 你是否拒绝了某项读取权限。因此“未读到”可能是未授权、尚未同步、没有近期记录，或设备没有提供这项数据。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                Button {
                    openURL(URL(string: "x-apple-health://")!) { accepted in cannotOpen = !accepted }
                } label: {
                    Label("打开健康 App", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("openSystemHealth")
                if cannotOpen {
                    Text("请回到手机桌面，手动打开健康 App。")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                }
            }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .navigationTitle("健康读取指引").navigationBarTitleDisplayMode(.inline)
    }
    private func guideStep(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SleepPalette.teal).frame(width: 30, height: 30)
                .background(SleepPalette.teal.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(SleepPalette.muted).lineSpacing(5)
            }
        }
    }
}

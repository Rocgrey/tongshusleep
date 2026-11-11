import SwiftUI
import SwiftData

/// A single action on either tab reads all available, user-authorized health types.
struct SystemHealthReadButton: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.modelContext) private var context
    var body: some View {
        Button { Task { await health.refresh(in: context, requestAccess: true) } } label: {
            HStack(spacing: 12) {
                if health.isLoading { ProgressView().tint(.white) }
                else { Image(systemName: "heart.text.clipboard") }
                Text(health.isLoading ? "正在读取健康记录" : "从系统健康读取").font(.body.weight(.semibold))
                Spacer(minLength: 6)
                Image(systemName: "arrow.down.circle")
            }.foregroundStyle(.white).padding(16).frame(maxWidth: .infinity, minHeight: 54)
                .background(SleepPalette.teal, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(health.isLoading).accessibilityIdentifier("readHealthOverview")
    }
}

/// Both tabs use the same reader, status and SwiftData reconciliation.
struct SystemSleepImportView: View {
    var showsReadButton = true
    @EnvironmentObject private var health: HealthOverviewStore
    @State private var showsHelp = false
    private var payloads: [SleepPayload] { health.snapshot?.sleepRecords ?? [] }
    private var summary: HealthSleepReadSummary { HealthSleepReadSummary(payloads) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label("系统睡眠", systemImage: "bed.double.fill").font(.headline).foregroundStyle(SleepPalette.ink)
                Spacer()
                Button { showsHelp = true } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("系统睡眠读取说明")
            }
            Text(showsReadButton ? "统一读取最近 90 天的睡眠、活动和可用体征，在本机整理，不写入系统健康。已启用自动同步时，睡眠和步数同步到当前账号，可在个人页关闭。" : "睡眠随上方的健康数据一起更新。卧床与睡着时长分别展示，不推算缺失的阶段。")
                .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-system-sleep") {
                Label("界面测试示例 · 非真实健康数据", systemImage: "info.circle").font(.caption).foregroundStyle(SleepPalette.rose)
            }
            #endif
            if showsReadButton {
                SystemHealthReadButton()
                if health.isLoading {
                    Text(health.progress).font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let message = health.message {
                    Text(message).font(.caption).foregroundStyle(health.messageIsError ? SleepPalette.rose : SleepPalette.muted)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("healthRefreshMessage")
                }
            }
            if let readAt = health.snapshot?.sleepReadAt {
                Label("最近读取 \(readAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption).foregroundStyle(SleepPalette.muted).accessibilityIdentifier("systemSleepReadAt")
                if let first = payloads.map({ SleepRecord($0).day }).min(), let last = payloads.map({ SleepRecord($0).day }).max() {
                    Text("实际记录日期 \(first.formatted(date: .abbreviated, time: .omitted)) 至 \(last.formatted(date: .abbreviated, time: .omitted)) · \(payloads.count) 段")
                        .font(.caption).foregroundStyle(SleepPalette.muted).accessibilityIdentifier("systemSleepDataDates")
                }
            }
            if let message = health.sleepMessage {
                Text(message).font(.caption).foregroundStyle(health.sleepMessageIsError ? SleepPalette.rose : SleepPalette.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("systemSleepMessage")
            } else if health.snapshot?.sleepReadAt != nil {
                Text(payloads.isEmpty ? HealthOverviewStore.noSleepMessage : summary.countText)
                    .font(.caption).foregroundStyle(SleepPalette.muted).accessibilityIdentifier("systemSleepMessage")
            }
            if let latest = summary.sleepRecords.first {
                Text("最近睡眠 \(latest.day.formatted(date: .abbreviated, time: .omitted)) · \(SleepRecord.durationText(latest.asleepMinutes))" + (latest.hasStages ? "" : " · 未分期睡眠"))
                    .font(.subheadline).foregroundStyle(SleepPalette.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("latestConfirmedSystemSleep")
            }
            if let latest = summary.bedRecords.first {
                Text("最近卧床 \(latest.day.formatted(date: .abbreviated, time: .omitted))：来源只标记了卧床，不能当作睡着时长或生成深睡、浅睡、REM。")
                    .font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("latestSystemBedRecord")
            }
        }.sheet(isPresented: $showsHelp) {
            NavigationStack { ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("读取你已记录的睡眠").font(.title2.bold())
                    Text("点击“从系统健康读取”统一申请睡眠、活动和可用体征等读取权限，可按自己的意愿选择项目。不申请任何写入权限。睡眠页与健康页一起更新；系统可能提供手机、手表以及第三方 App 已写入的记录，能否读到取决于数据是否存在和访问设置。")
                    Text("蓝牙连接本身不会产生系统健康睡眠记录。设备配套 App 需要支持并实际写入 Apple 健康；请先在配套 App 中完成同步。")
                    Text("没有记录时，打开健康 App，查看“浏览 → 睡眠”的实际数据；再到健康 App 的头像 → App（或数据访问与设备）→ sleeptongshu 检查睡眠读取设置。系统版本不同，入口名称可能略有不同。")
                    Text("系统不会告诉我们你是否关闭了读取权限。未读取到记录时无法据此判断原因；本机旧导入会移到健康设置的归档中，保留备注。恢复访问并重新读取后可再次显示。")
                    Text("同一段重叠记录优先选择提供较多真实分期的来源，再比较睡眠覆盖时长；不同来源不拼接。超过 30 分钟没有任何阶段记录时分成独立时段；间隔不会补为清醒。午睡单独保留，日期按原记录时区的睡眠结束日显示。")
                    Text("仅卧床不等于睡着。未分期睡眠只计真实时长，不推算深睡、浅睡或 REM。系统记录中的 Core 在这里显示为浅睡。资料有缺口时不计算清醒次数和效率；只有未分期的总时长时，不推算清醒次数。系统睡眠不生成 App 参考分。")
                }.font(.body).foregroundStyle(SleepPalette.ink).padding(22)
            }.background(SleepPalette.background).navigationTitle("系统睡眠说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsHelp = false } } }
            }
        }
    }
}

struct SystemSleepSourceView: View {
    let record: SleepRecord
    var body: some View {
        if let details = record.metadata?.healthSleep {
            VStack(alignment: .leading, spacing: 10) {
                Label(details.origin.appName, systemImage: "heart.text.clipboard").font(.subheadline.weight(.medium))
                Text(details.origin.deviceName ?? details.origin.model ?? "来源未标明设备")
                Text("记录时区 \(details.timeZoneIdentifier) · 归属 \(details.endDay)")
                Text("\(details.samples.count) 个原始样本 · \(details.otherSourceIDs.isEmpty ? "没有其他重叠来源" : "已排除其他重叠来源")")
                if record.efficiency == nil {
                    Text("效率未计算：需要同一来源完整的卧床范围及连续睡眠/清醒记录，缺口不能当作清醒。")
                }
                DisclosureGroup("样本标识与来源详情") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let bundle = details.origin.bundleIdentifier { Text(bundle) }
                        if let manufacturer = details.origin.manufacturer { Text("设备厂商：\(manufacturer)") }
                        if let model = details.origin.model { Text("设备型号：\(model)") }
                        ForEach(details.samples) { sample in
                            Text("\(sample.stage.label) · \(record.displayClock(sample.start))–\(record.displayClock(sample.end))\n\(sample.id.uuidString)").textSelection(.enabled)
                        }
                    }.font(.caption2).padding(.top, 8)
                }
            }.font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

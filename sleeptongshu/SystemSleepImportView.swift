import SwiftUI
import SwiftData

/// Both tabs use the same reader, status and SwiftData reconciliation.
struct SystemSleepImportView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.modelContext) private var context
    @State private var showsHelp = false
    private var payloads: [SleepPayload] { health.snapshot?.sleepRecords ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label("系统睡眠", systemImage: "bed.double.fill").font(.headline).foregroundStyle(SleepPalette.ink)
                Spacer()
                Button { showsHelp = true } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("系统睡眠读取说明")
            }
            Text("只读最近 90 天的睡眠，在本机整理时间与阶段。不写入系统健康，也不会自动上传。")
                .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-system-sleep") {
                Label("界面测试示例 · 非真实健康数据", systemImage: "info.circle").font(.caption).foregroundStyle(SleepPalette.rose)
            }
            #endif
            Button { Task { await health.readSystemSleep(in: context, requestAccess: true) } } label: {
                HStack(spacing: 10) {
                    if health.isLoading { ProgressView().tint(.white) } else { Image(systemName: "arrow.down.heart") }
                    Text(health.isLoading ? "正在读取" : "读取系统睡眠").font(.body.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.clockwise")
                }.padding(14).frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white).background(SleepPalette.teal, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(health.isLoading).accessibilityIdentifier("readSystemSleep")
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
            } else if health.snapshot?.sleepReadAt != nil && payloads.isEmpty {
                Text(HealthOverviewStore.noSleepMessage).font(.caption).foregroundStyle(SleepPalette.muted)
            }
        }.sheet(isPresented: $showsHelp) {
            NavigationStack { ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("读取你已记录的睡眠").font(.title2.bold())
                    Text("点击读取后，只申请睡眠读取权限。系统可能提供手机、手表以及第三方 App 已写入的记录；能否读到取决于数据是否存在和访问设置。")
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

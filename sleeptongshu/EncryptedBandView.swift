import SwiftUI
import UniformTypeIdentifiers
import Charts

/// A user-selected folder grants access to an existing binding, never to another App's sandbox.
struct EncryptedBandPanel: View {
    @EnvironmentObject private var scanner: RingScanner
    @EnvironmentObject private var band: EncryptedBandStore
    @State private var showsSetup = false
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if scanner.encryptedBandChannelDetected || band.deviceID != nil {
                Label("加密设备同步", systemImage: "lock.shield").font(.headline)
                Text(band.phaseText).font(.subheadline).foregroundStyle(SleepPalette.teal)
                    .accessibilityIdentifier("encryptedBandStatus")
                if band.isBusy {
                    if let progress = band.progress { ProgressView(value: progress).tint(SleepPalette.teal) }
                    else { ProgressView() }
                    Button("停止本次读取", role: .cancel) { band.stop() }
                }
                if let level = band.battery {
                    DeviceBatteryView(reading: DeviceBatteryReading(level: level, isPercentage: true), isCurrent: band.isBusy,
                                      isReading: false, deviceName: band.deviceName)
                }
                if let steps = band.steps { Label("设备当天步数 \(steps)", systemImage: "figure.walk").font(.subheadline) }
                if !band.currentActivityDays.isEmpty {
                    let days = Array(band.currentActivityDays.prefix(7).reversed())
                    Text("设备每日步数").font(.subheadline.weight(.medium))
                    Chart(days) { day in
                        BarMark(x: .value("日期", String(day.day.suffix(5))), y: .value("步数", day.steps))
                            .foregroundStyle(SleepPalette.teal).cornerRadius(3)
                    }.frame(height: 150).accessibilityLabel("蓝牙设备每日步数，最近最多七个有记录日期")
                    Text("来源：蓝牙设备日汇总 · 同一天更新替换，不与系统健康步数相加。缺少记录的日期不补零。")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let date = band.lastReadAt {
                    Text("最近读取 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                if let summary = band.summary { Text(summary).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            }
            Button { showsSetup = true } label: {
                HStack {
                    Label("\(scanner.encryptedBandTarget.map { band.hasCredential($0.id) ? "管理" : "导入" } ?? "导入")设备绑定凭证", systemImage: "key.horizontal")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                }.font(.subheadline).padding(.vertical, 8)
            }.disabled(band.isBusy || scanner.isHandingOff).accessibilityIdentifier("encryptedBandSetup")
            Text("部分加密设备需已有绑定凭证。首次导入后，连接时自动读取；未完成过首次绑定的设备不能跳过认证。")
                .font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            if band.deviceID != nil {
                DisclosureGroup("读取详情", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前为实测适配：支持的历史文件才会导入，不支持的格式保存在本机。没有分期不生成睡眠图，不删除设备历史。启用自动同步后，已有记录同步到当前账号。")
                        Text(band.diagnostic).font(.caption2.monospaced()).textSelection(.enabled)
                        ShareLink(item: band.diagnostic) { Label("分享读取诊断", systemImage: "square.and.arrow.up") }
                    }.font(.caption).padding(.top, 10)
                }.font(.subheadline)
            }
        }.sheet(isPresented: $showsSetup) { EncryptedBandSetupView() }
    }
}

struct EncryptedBandSetupView: View {
    @EnvironmentObject private var scanner: RingScanner
    @EnvironmentObject private var band: EncryptedBandStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsFolder = false
    @State private var importing = false
    @State private var candidates: [STBandBandKey] = []
    @State private var manual = ""
    @State private var message: String?
    @State private var showsRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("凭证只保存在这台手机", systemImage: "lock.shield.fill").font(.title3.bold())
                    Text("先在设备配套 App 完成一次正常绑定。这里读取你主动选择文件夹中的已有设备凭证，不需要提供账号密码，也不会联网获取凭证。")
                    Text("找不到配套 App 的文件夹时，本版本不能直接从其他 App 的私有空间取得凭证。可使用你已持有的设备凭证，或继续通过系统健康读取已同步的数据。")
                        .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                    if let target = scanner.encryptedBandTarget {
                        Label(target.name, systemImage: "sensor.fill").font(.headline)
                        Text(band.hasCredential(target.id) ? "已有本机凭证，重新连接会自动读取。可重新导入或移除凭证。" : "已发现加密通道，尚需验证绑定凭证。")
                            .foregroundStyle(SleepPalette.muted)
                    } else {
                        Label("请先搜索并连接要读取的设备", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(SleepPalette.rose).accessibilityIdentifier("encryptedBandNeedsConnection")
                    }
                    Button { showsFolder = true } label: {
                        Label(importing ? "正在读取文件夹" : "选择配套 App 的文件夹", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).disabled(importing || scanner.encryptedBandTarget == nil || band.isBusy)
                        .accessibilityIdentifier("importBandCredentialFolder")
                    Text("在文件选择器中进入“浏览 → 我的 iPhone”，选择设备配套 App 的文件夹。只有文件夹实际包含绑定缓存时才能读取；找不到时，可以使用已有的 32 位设备凭证。不要解绑或恢复出厂设置。")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                    ForEach(Array(candidates.enumerated()), id: \.offset) { index, key in
                        Button { bind(key.hex) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(key.name).font(.headline)
                                    Text("凭证 \(index + 1) · 已隐藏").font(.caption).foregroundStyle(SleepPalette.muted)
                                }
                                Spacer()
                                Image(systemName: "key.horizontal.fill")
                            }.padding(.vertical, 8)
                        }.disabled(scanner.encryptedBandTarget == nil || band.isBusy)
                    }
                    DisclosureGroup("已有设备凭证") {
                        VStack(alignment: .leading, spacing: 12) {
                            SecureField("32 位设备凭证", text: $manual)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("manualBandCredential")
                            Button { bind(manual) } label: { Label("保存并自动读取", systemImage: "lock.open") }
                                .disabled(scanner.encryptedBandTarget == nil || band.isBusy || manual.isEmpty)
                        }.padding(.top, 12)
                    }
                    if let message { Text(message).foregroundStyle(SleepPalette.rose).fixedSize(horizontal: false, vertical: true) }
                    if let target = scanner.encryptedBandTarget, band.hasCredential(target.id) {
                        Button("移除这台设备的绑定凭证", role: .destructive) { showsRemove = true }
                    }
                }.font(.body).padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
                .navigationTitle("设备绑定凭证").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented: $showsFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        importing = true; message = nil; candidates = []
                        Task {
                            do { candidates = try await Task.detached(priority: .userInitiated) { try STBandKeyLoader.load(from: url) }.value }
                            catch { message = "没有读到可用绑定凭证。请确认选中了配套 App 的文件夹，并已正常绑定同步过设备；也可使用已有的 32 位凭证。" }
                            importing = false
                        }
                    case .failure: message = "未能访问所选文件夹，请重新选择。"
                    }
                }
                .confirmationDialog("移除本机绑定凭证？历史记录会保留。", isPresented: $showsRemove, titleVisibility: .visible) {
                    Button("移除凭证", role: .destructive) {
                        guard let target = scanner.encryptedBandTarget else { return }
                        do { try band.forget(target.id); candidates = []; manual = "" }
                        catch { message = "凭证未能移除，请稍后重试。" }
                    }
                }
        }
    }
    private func bind(_ value: String) {
        guard let target = scanner.encryptedBandTarget else { message = "请先连接要读取的设备。"; return }
        do {
            try band.bind(value, id: target.id, name: target.name)
            manual = ""; candidates = []; dismiss()
            scanner.startEncryptedBandSync()
        } catch { message = error.localizedDescription }
    }
}

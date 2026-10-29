import SwiftUI
import SwiftData
import Charts

struct MonitoringView: View {
    @EnvironmentObject private var phone: PhoneSleepMonitor
    @EnvironmentObject private var scanner: RingScanner
    @EnvironmentObject private var vitals: WearableVitalsStore
    @Environment(\.modelContext) private var context
    @Query private var records: [SleepRecord]
    @StateObject private var health = HealthSleepImporter()
    @StateObject private var ring = VeepooRingClient()
    @State private var ringTask: Task<Void, Never>?
    @AppStorage("phoneTrackingEnabled") private var trackingEnabled = false
    @State private var mode = 0
    @State private var showPreview = false
    @State private var showDiscard = false
    @State private var message: String?
    @State private var showsLocalData = false
    @State private var showsVitals = false
    @State private var syncSummary: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("好眠，从今晚开始").font(.system(size: 26, weight: .bold))
                            Text("选择适合你的记录方式").font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "moon.stars.fill").font(.system(size: 28)).foregroundStyle(SleepPalette.deep).padding(.top, 4)
                    }
                    Button { showsLocalData = true } label: {
                        HStack {
                            Label("本地数据与睡眠目标", systemImage: "externaldrive")
                            Spacer()
                            Text("\(records.count) 条").foregroundStyle(SleepPalette.muted)
                            Image(systemName: "chevron.right")
                        }.font(.system(size: 13)).padding(.vertical, 10).contentShape(Rectangle())
                    }.accessibilityIdentifier("localData")
                    Picker("监测方式", selection: $mode) {
                        Label("手机监测", systemImage: "iphone").tag(0)
                        Label("设备检测", systemImage: "sensor.fill").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("monitorMode")
                    if mode == 0 { phonePanel; healthPanel; phoneGuide; differences }
                    else { wearablePanel; healthPanel; differences }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsLocalData) { LocalDataView() }
            .navigationDestination(isPresented: $showsVitals) { WearableVitalsView() }
            .sheet(isPresented: $showPreview) {
                NavigationStack {
                    ScrollView {
                        PhoneReportView(night: .preview(start: Calendar.current.startOfDay(for: .now).addingTimeInterval(-3600)), isPreview: true)
                            .padding(22)
                    }.background(SleepPalette.background).navigationTitle("手机报告示例").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showPreview = false } } }
                }
            }
            .alert("睡眠监测", isPresented: Binding(get: { message != nil || phone.error != nil || health.message != nil }, set: { if !$0 { clearMessage() } })) {
                Button("知道了", role: .cancel) { clearMessage() }
            } message: { Text(message ?? phone.error ?? health.message ?? "") }
            .confirmationDialog("舍弃本次采集？", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("舍弃采集", role: .destructive) { phone.discard() }
            }
            .onDisappear { scanner.stopScan() }
            .onChange(of: scanner.veepooChannelDetected) { _, detected in
                autoSyncIfReady()
            }
            .onChange(of: scanner.isInspecting) { _, _ in autoSyncIfReady() }
            .onAppear {
                autoSyncIfReady()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-preview-wearable") { mode = 1 }
                if ProcessInfo.processInfo.arguments.contains("-preview-phone-report") { showPreview = true }
                if ProcessInfo.processInfo.arguments.contains("-preview-local-data") { showsLocalData = true }
                #endif
            }
        }
    }

    private var phonePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(phone.isRecording ? "正在守候你的睡眠" : "手机睡眠跟踪", systemImage: phone.isRecording ? "record.circle" : "iphone")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("本机处理").font(.system(size: 11)).foregroundStyle(SleepPalette.teal)
            }
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(SleepPalette.teal.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: phone.isRecording ? 0.78 : 0.28)
                        .stroke(SleepPalette.teal, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: phone.isRecording ? "waveform" : "moon.zzz.fill")
                        .font(.system(size: 35)).foregroundStyle(SleepPalette.teal)
                }.frame(width: 102, height: 102).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    if let checkpoint = phone.checkpoint {
                        Text(phone.isRecording ? "正在监测 · 已用时" : "本次监测时长")
                            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        Text(duration(seconds: phone.elapsedSeconds))
                            .font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("monitorElapsedTime")
                        Text("\(checkpoint.epochs.count) 个分钟窗口 · \((phone.isRecording ? phone.motionAvailable : checkpoint.epochs.contains { $0.movement != nil }) ? "体动可用" : "体动未采集")")
                            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                    } else {
                        Text("晚安，放松下来").font(.system(size: 19, weight: .semibold))
                        Text("用声音与体动，了解一晚的安静与起伏。")
                            .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(phone.status).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            if phone.checkpoint == nil {
                Toggle("开启手机睡眠跟踪", isOn: $trackingEnabled).font(.system(size: 14)).tint(SleepPalette.teal)
                Button { Task { await phone.start() } } label: {
                    Label(phone.isStarting ? "正在准备…" : "开始今晚监测", systemImage: "play.fill")
                        .foregroundStyle(trackingEnabled ? Color.white : SleepPalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(!trackingEnabled || phone.isStarting).accessibilityIdentifier("startMonitoring")
                Text("睡前开始，醒来后手动结束；最长监测 23 小时。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            } else if phone.isRecording {
                Label("麦克风信号 \(Int(phone.currentDB)) dBFS", systemImage: "mic.fill").font(.system(size: 12))
                Button { phone.stop() } label: {
                    Label("结束本次监测", systemImage: "stop.fill").foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("stopMonitoring")
                Text("醒来后点“结束本次监测”，再保存报告。当前显示监测时长，不代表已经睡着；本版不会自动判断你已醒来。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            } else {
                HStack {
                    Button { savePhone() } label: { Label("保存睡眠报告", systemImage: "checkmark").foregroundStyle(.white).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("saveMonitoring")
                    Button { showDiscard = true } label: { Image(systemName: "trash").frame(width: 40, height: 36) }
                        .accessibilityLabel("舍弃采集").tint(.red)
                }
            }
            Text("不录制或保存原始音频。手机不能测量深睡、REM、血氧和心率；入睡与睡眠时长为粗略估算。")
                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }.padding(20).background(SleepPalette.teal.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) { if phone.isStarting { ProgressView().padding(4) } }
    }

    private var healthPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "heart.text.clipboard.fill").font(.system(size: 23)).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("从系统健康读取").font(.system(size: 16, weight: .semibold))
                    Text("已有记录，也可以直接带过来").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
                Spacer()
            }
            Text("读取系统“健康”中已有的睡眠与可用体征。请先允许记录来源向系统健康写入数据。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            if !health.providers.isEmpty {
                Picker("选择数据来源", selection: $health.selectedProvider) {
                    ForEach(health.providers, id: \.self) { Text(DevicePresentation.name($0)).tag($0) }
                }.font(.system(size: 12))
                Button { Task { await importHealth() } } label: { Label("导入所选来源", systemImage: "square.and.arrow.down") }
                    .disabled(health.isLoading)
            }
            Button { Task { await health.load() } } label: {
                if health.isLoading { ProgressView().frame(maxWidth: .infinity) }
                else { Label("连接系统健康", systemImage: "heart.fill").frame(maxWidth: .infinity).padding(.vertical, 4) }
            }.buttonStyle(.bordered).disabled(health.isLoading).accessibilityIdentifier("connectHealth")
            if !HealthSleepImporter.enabled {
                Text("当前版本未启用系统健康读取，可使用手机监测或设备同步。")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
        }
    }

    private var phoneGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(title: "睡前准备", subtitle: "让采集更稳定，也让你睡得安心")
                Spacer()
                Button { showPreview = true } label: { Label("报告示例", systemImage: "chart.xyaxis.line") }
                    .font(.system(size: 11)).accessibilityIdentifier("previewPhoneReport")
            }
            guideRow("1", title: "开启跟踪，并允许麦克风", detail: "打开上方跟踪开关；首次开始时允许麦克风与体动访问。")
            guideRow("2", title: "放在床上，距离身体不超过 50 厘米", detail: "例如枕头旁，保持手机稳定；不要放在枕头下面或用被褥覆盖。")
            guideRow("3", title: "保持充足电量，留意散热", detail: "整夜采集会耗电；需要充电时请保持通风，避免线缆缠绕。")
            guideRow("4", title: "建议让 App 保持前台运行", detail: "采集时屏幕保持唤醒，可调低亮度。锁屏后系统可能限制体动回调；来电、其他录音、切换音频设备或强制退出都可能中断采集。")
            guideRow("5", title: "醒来后结束并保存", detail: "至少连续 15 个安静且有体动信号的分钟窗口后才尝试估算入睡。没有足够信号时，只保留采集时段和声音统计。")
        }
    }

    private var wearablePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                Image(systemName: "circle.circle").font(.system(size: 46)).foregroundStyle(SleepPalette.deep)
                VStack(alignment: .leading, spacing: 6) {
                    Text(scanner.connectedName ?? (ring.isBusy ? ring.deviceName : nil) ?? "睡眠戒指")
                        .font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(scanner.status).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
            }
            if scanner.connectedName != nil || ring.isBusy || (!scanner.isScanning && scanner.connectingID == nil && ring.deviceName != nil) {
                DeviceBatteryView(reading: displayedBattery, isCurrent: scanner.connectedName != nil || ring.isBusy,
                                  isReading: scanner.isInspecting || ring.isBusy,
                                  deviceName: scanner.connectedName ?? ring.deviceName)
            }
            if scanner.veepooChannelDetected || !ring.events.isEmpty { ringPanel }
            Button { showsVitals = true } label: {
                HStack {
                    Label("体征记录", systemImage: "heart.text.clipboard")
                    Spacer()
                    Text("\(vitals.visibleSamples.count) 条").foregroundStyle(SleepPalette.muted)
                    Image(systemName: "chevron.right")
                }.font(.system(size: 14)).padding(.vertical, 10)
            }.accessibilityIdentifier("wearableVitals")
            if let value = scanner.liveHeartRate { Label("实时心率 \(value) 次/分", systemImage: "heart.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.pink) }
            if ring.isBusy {
                Button("取消戒指同步", role: .cancel) { ringTask?.cancel(); ring.cancel() }
            } else if scanner.connectedName != nil {
                DisclosureGroup("标准数据与设备诊断") { deviceReadout.padding(.top, 10) }
                    .font(.system(size: 13))
                Button { scanner.inspectDevice() } label: { Label("重新检查设备", systemImage: "arrow.clockwise") }
                    .disabled(scanner.isInspecting).accessibilityIdentifier("refreshDeviceData")
                Button("断开设备", role: .destructive) { scanner.disconnect() }
            } else if scanner.connectingID != nil {
                ProgressView("连接中…")
                Button("取消连接") { scanner.disconnect() }
            } else {
                Button { scanner.isScanning ? scanner.stopScan() : scanner.scan() } label: {
                    Label(scanner.isScanning ? "停止搜索" : "搜索蓝牙", systemImage: scanner.isScanning ? "stop.fill" : "magnifyingglass")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("scanBluetooth")
            }
            if scanner.connectedName == nil && !ring.isBusy {
              if !scanner.rememberedDevices.isEmpty {
                SectionHeading(title: "已连接过的设备", subtitle: "点击直接重连，无需再次搜索")
                ForEach(scanner.rememberedDevices) { device in
                    HStack {
                        Button { scanner.reconnect(device) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "link").foregroundStyle(SleepPalette.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(device.name) · \(device.id.uuidString.prefix(4))").font(.system(size: 14, weight: .medium))
                                    Text("上次连接 \(device.lastConnected.formatted(.dateTime.month().day().hour().minute()))").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(scanner.connectingID != nil)
                        Menu {
                            Button("忘记此设备", role: .destructive) { scanner.forget(device) }
                        } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40) }
                            .accessibilityLabel("设备选项")
                    }
                    Divider()
                }
              }
              ForEach(scanner.devices) { device in
                Button { scanner.connect(device) } label: {
                    HStack {
                        Image(systemName: "sensor.fill").foregroundStyle(SleepPalette.deep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.system(size: 14))
                            Text("\(device.rssi) dBm · \(device.id.uuidString.prefix(8))").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12))
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(scanner.connectedName != nil || scanner.connectingID != nil || ring.isBusy)
                Divider()
              }
            }
            SectionHeading(title: "设备提供什么，就展示什么", subtitle: "兼容性取决于开放协议与数据权限")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                capability("睡眠阶段", icon: "chart.bar.xaxis", detail: "深睡 · 浅睡 · REM · 清醒")
                capability("可用体征", icon: "heart.fill", detail: "心率 · 血氧 · HRV 等")
            }
            Text("连接后同步设备已有的睡眠与体征，没有睡眠也可保存体征。仅展示设备实际提供且可验证的值；未开放的指标不会补算。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            Text("搜索列表显示附近设备的蓝牙名称；能被搜索到，不代表支持睡眠与体征同步。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var displayedBattery: DeviceBatteryReading? {
        if scanner.connectedName != nil {
            return scanner.battery.flatMap { DeviceBatteryReading(level: $0, isPercentage: true) }
        }
        guard scanner.connectingID == nil, !scanner.isScanning else { return nil }
        return ring.battery
    }
    private var ringPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label("睡眠与体征同步", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .semibold))
            Text(ring.status).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            if let progress = ring.progress { ProgressView(value: progress).tint(SleepPalette.teal) }
            else if ring.isBusy { ProgressView().controlSize(.small) }
            if VeepooRingClient.enabled {
                Text("连接受支持的戒指后自动同步。请先结束其他 App 的同步，并保持本 App 打开。同步会校准设备时间，结束后释放蓝牙连接。")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            } else {
                Text("已识别设备通道，当前安装包尚未启用此通道的数据读取。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            }
            if let syncSummary {
                Text(syncSummary).font(.system(size: 12)).foregroundStyle(SleepPalette.teal).lineSpacing(4)
            }
            if !ring.events.isEmpty {
                DisclosureGroup("同步详情") {
                    Text(ring.diagnosticReport).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: ring.diagnosticReport) { Label("分享同步诊断", systemImage: "square.and.arrow.up") }
                }.font(.system(size: 12))
            }
        }
    }

    private func autoSyncIfReady() {
        guard VeepooRingClient.enabled, scanner.veepooChannelDetected,
              !scanner.isInspecting, scanner.connectedName != nil, !ring.isBusy else { return }
        syncRing()
    }

    private func syncRing() {
        guard !ring.isBusy else { return }
        syncSummary = nil
        ring.preparing(name: scanner.connectedName ?? "戒指", battery: scanner.battery)
        ringTask = Task {
            do {
                let peripheral = try await scanner.releaseForVendorSync()
                let download = try await ring.sync(peripheral: peripheral)
                let payloads = download.records
                let added = try vitals.merge(download.vitals)
                for payload in payloads {
                    try payload.validate()
                    if let existing = records.first(where: { $0.id == payload.id }) { existing.replace(with: payload) }
                    else { context.insert(SleepRecord(payload)) }
                }
                try context.save()
                ring.saved(count: payloads.count, vitals: download.vitals.count)
                syncSummary = "本次已保存睡眠 \(payloads.count) 段，新增或更新体征 \(added) 条。\(payloads.isEmpty ? "暂无睡眠记录，请佩戴过夜后重新连接，届时会自动同步。" : "")\(download.vitals.isEmpty ? "本次没有有效体征，请贴合佩戴并完成测量后重新连接。" : "体征可在“体征记录”中查看。")\(download.rejected > 0 ? "部分睡眠格式尚未验证，未保存。" : "")"
            } catch is CancellationError {
                ring.cancel()
            } catch {
                context.rollback()
                ring.reportFailure(error)
                message = error.localizedDescription
            }
        }
    }
    private var deviceReadout: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "连接后的数据状态", subtitle: scanner.isInspecting ? "正在检查设备开放的数据…" : "连接成功后，仍需设备开放对应的数据")
            readout("电量", value: scanner.battery.map { "\($0)%" }, state: scanner.batteryState)
            readout("设备型号", value: scanner.modelNumber, state: scanner.modelState)
            readout("实时心率", value: scanner.liveHeartRate.map { "\($0) 次/分" }, state: scanner.heartRateState)
            readout("历史睡眠", value: nil, state: .failed(VeepooRingClient.enabled && scanner.veepooChannelDetected ? "通道检查完成后自动同步" : "尚不支持此戒指的数据通道"))
            Text("如果心率一直等待，请确认佩戴贴合，并在设备或配套 App 中开启心率广播（若支持）。不要先解绑或恢复出厂设置，以免丢失设备中的记录。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            DisclosureGroup("读取不到数据怎么办？") {
                Text("请确认设备已贴合佩戴并生成记录。蓝牙连接成功仅表示通道建立，历史数据可能还需要设备认证或协议适配。若设备支持写入系统健康，也可从下方导入；具体读取状态见设备诊断。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4).padding(.top, 8)
            }.font(.system(size: 13))
            DisclosureGroup("设备诊断") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(scanner.diagnosticReport).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: scanner.diagnosticReport) { Label("分享设备诊断", systemImage: "square.and.arrow.up") }
                }.padding(.top, 8)
            }.font(.system(size: 13))
        }
    }
    private func readout(_ title: String, value: String?, state: BLEReadState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Text(value ?? state.label).font(.system(size: 12))
                .foregroundStyle(value == nil ? SleepPalette.muted : SleepPalette.teal)
                .multilineTextAlignment(.trailing)
        }
    }
    private var differences: some View {
        DisclosureGroup {
            Text("手机通过床面震动和环境声音间接观察；戒指更贴近身体，通常还能使用心率、血氧等信号，因此数据可能更详细。摆放位置、同床者、宠物、背景声、佩戴松紧、算法、采样频率及统计时段都会影响结果。不同来源请分别看趋势，不宜直接把数值当作同一种测量。")
                .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(5).padding(.top, 12)
        } label: { Label("手机与戒指数据为什么不一样？", systemImage: "info.circle").font(.system(size: 13, weight: .medium)) }
    }
    private func guideRow(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 12, weight: .bold)).foregroundStyle(SleepPalette.teal)
                .frame(width: 25, height: 25).background(SleepPalette.teal.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            }
        }
    }
    private func capability(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(SleepPalette.deep)
            Text(detail).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
        }
    }
    private func duration(seconds: Int) -> String {
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    private func savePhone() {
        guard let saved = phone.checkpoint, saved.end > saved.start, !saved.epochs.isEmpty else { message = "还没有采集到可保存的信号，请重新监测。"; return }
        do {
            let payload = saved.payload
            try payload.validate()
            if !records.contains(where: { $0.id == payload.id }) { context.insert(SleepRecord(payload)) }
            try context.save()
            phone.saved()
            message = "报告已保存在本机，可到“睡眠”查看本次记录。"
        } catch { context.rollback(); message = error.localizedDescription }
    }
    private func importHealth() async {
        do {
            let payloads = try await health.importSelected()
            for payload in payloads {
                if let previous = records.first(where: { $0.id == payload.id }) { previous.replace(with: payload) }
                else { context.insert(SleepRecord(payload)) }
            }
            try context.save()
            message = payloads.isEmpty ? "所选来源没有可导入的睡眠区间，仅有卧床时间不会生成睡眠。" : "已导入或更新 \(payloads.count) 晚记录。同一来源同一晚不会重复累加。"
        } catch { context.rollback(); message = "导入失败：\(error.localizedDescription)" }
    }
    private func clearMessage() { message = nil; phone.error = nil; health.message = nil }
}

struct PhoneReportView: View {
    let night: PhoneNight
    var isPreview = false
    @State private var metric = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "声音与体动", subtitle: isPreview ? "模拟数据 · 仅预览，不会保存到睡眠记录" : "手机采集 · 非医学睡眠分期")
            HStack(alignment: .top) {
                reportNumber("有效声音采集", value: "\(night.coverageMinutes)", unit: "分", color: SleepPalette.teal)
                reportNumber("疑似鼾声", value: night.classifierAvailable ? "\(Int(night.snoreSeconds / 60))" : "--", unit: "分", color: SleepPalette.awake)
                reportNumber("疑似说话", value: night.classifierAvailable ? "\(Int(night.speechSeconds))" : "--", unit: "秒", color: SleepPalette.deep)
            }
            Picker("信号图表", selection: $metric) { Text("声音").tag(0); Text("体动").tag(1); Text("声音事件").tag(2) }.pickerStyle(.segmented)
            if night.epochs.isEmpty { Text("本次没有可用信号").foregroundStyle(SleepPalette.muted) }
            else {
                Chart(night.epochs) { epoch in
                    if metric == 0, epoch.audioSeconds > 0 {
                        BarMark(x: .value("时间", epoch.date), yStart: .value("底部", -80), yEnd: .value("声音", max(-80, epoch.soundDB)))
                            .foregroundStyle(SleepPalette.teal.opacity(0.65))
                    } else if metric == 1, let movement = epoch.movement {
                        BarMark(x: .value("时间", epoch.date), y: .value("体动 g", movement)).foregroundStyle(SleepPalette.deep.opacity(0.7))
                    } else if metric == 2, night.classifierAvailable {
                        BarMark(x: .value("时间", epoch.date), y: .value("疑似鼾声秒数", epoch.snoreSeconds))
                            .foregroundStyle(by: .value("事件", "疑似鼾声"))
                        BarMark(x: .value("时间", epoch.date), y: .value("疑似说话秒数", epoch.speechSeconds))
                            .foregroundStyle(by: .value("事件", "疑似说话"))
                    }
                }
                .chartForegroundStyleScale(["疑似鼾声": SleepPalette.awake, "疑似说话": SleepPalette.deep])
                .chartLegend(metric == 2 ? .visible : .hidden)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 175).accessibilityLabel("手机声音与体动时间图")
                Text(metric == 0 ? "单位 dBFS：麦克风的相对信号强度，不是经过校准的环境分贝。" : metric == 1 ? "单位 g：加速度偏离重力的幅度。床面震动不一定来自本人，空白表示没有体动数据。" : "声音分类置信度 ≥ 75% 的窗口累计时长，可能存在误识别；不能确认本人鼾声或梦话。")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            }
            VStack(alignment: .leading, spacing: 9) {
                Label(night.estimatedOnset.map { "估算入睡 \(SleepRecord.clock($0))" } ?? "暂不能估算入睡时间", systemImage: "moon.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(night.estimatedMinutes.map { "安静低体动窗口约 \(SleepRecord.durationText($0))。这是信号估算，清醒静卧也可能被计入。" } ?? "需要连续 15 个有足够声音和体动信号的安静分钟窗口。采集较短、没有体动或信号中断时不会给出睡眠时长。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                Text("\(night.motionMinutes) 个分钟窗口有较明显体动，不等于清醒次数。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                if night.interrupted { Label("采集曾中断，图表只覆盖已有信号。", systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(SleepPalette.awake) }
                if !night.classifierAvailable { Text("声音分类不可用，未生成鼾声或说话统计。").font(.system(size: 12)).foregroundStyle(SleepPalette.muted) }
            }
            if night.snoreSeconds > 60 {
                Text("出现了较多疑似鼾声。可先减少睡前饮酒并观察侧卧后的变化；若长期打鼾且伴随憋醒、白天明显困倦，建议咨询医生。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            }
        }.foregroundStyle(SleepPalette.ink)
    }
    private func reportNumber(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            (Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)) + Text(" \(unit)").font(.system(size: 11))).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

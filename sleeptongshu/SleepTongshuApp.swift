import SwiftUI
import SwiftData

@main
struct SleepTongshuApp: App {
    @UIApplicationDelegateAdaptor(SleepAppDelegate.self) private var appDelegate
    @AppStorage("appAppearance") private var appearance = AppAppearance.fresh.rawValue
    @StateObject private var content = ContentStore()
    @StateObject private var routes = AppRoutes.shared
    @StateObject private var account = AccountStore.appStore()
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            #if DEBUG
            if testing, ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-theme") {
                UserDefaults.standard.set(AppAppearance.fresh.rawValue, forKey: "appAppearance")
            }
            #endif
            container = try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: testing, cloudKitDatabase: .none))
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                AppEntryView().environmentObject(account).environmentObject(content).environmentObject(routes)
                    .modelContainer(container).tint(Color(uiColor: (AppAppearance(rawValue: appearance) ?? .fresh).accent))
                    .scrollContentBackground(.hidden)
                    .background(SleepPalette.background)
                    .onOpenURL { routes.open($0) }
                    .onAppear { ReminderService.shared.install() }
                    .preferredColorScheme(testAppearance)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            } else {
                ContentUnavailableView("无法打开本地记录", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "请重新启动 App。原有记录不会被自动删除。"))
            }
        }
    }
    private var testAppearance: ColorScheme? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing-light") { return .light }
        if args.contains("-ui-testing-dark") { return .dark }
        #endif
        return nil
    }
}

enum SleepPalette {
    static let background = Color(uiColor: AppAppearance.adaptive(0xF2F5F4, 0x121A19))
    static let surface = Color(uiColor: AppAppearance.adaptive(0xFFFFFF, 0x1D2826))
    static let ink = Color(uiColor: AppAppearance.adaptive(0x1A2B29, 0xEDF4F2))
    static let muted = Color(uiColor: AppAppearance.adaptive(0x596F6B, 0xA7BDB7))
    static var teal: Color { Color(uiColor: UIColor { traits in
        let color = AppAppearance.current.accent
        return traits.userInterfaceStyle == .dark ? color.withAlphaComponent(1).lighter : color
    }) }
    static let rose = Color(red: 0.80, green: 0.28, blue: 0.40)
    static let mint = Color(red: 0.37, green: 0.73, blue: 0.67)
    static let deep = Color(red: 0.30, green: 0.37, blue: 0.77)
    static let rem = Color(red: 0.66, green: 0.57, blue: 0.88)
    static let awake = Color(red: 0.91, green: 0.59, blue: 0.36)
    static let line = Color(uiColor: AppAppearance.adaptive(0xDFE7E5, 0x374A45))
}

extension SleepStage {
    var color: Color {
        switch self { case .awake: SleepPalette.awake; case .rem: SleepPalette.rem; case .light: SleepPalette.mint; case .deep: SleepPalette.deep; case .unspecified: SleepPalette.teal; case .unobserved: SleepPalette.line; case .inBed: SleepPalette.muted.opacity(0.5) }
    }
}

enum SleepTab: Hashable { case sleep, monitoring, trends, health, classroom }

struct RootTabView: View {
    @EnvironmentObject private var routes: AppRoutes
    @EnvironmentObject private var content: ContentStore
    @AppStorage("appAppearance") private var appearance = AppAppearance.fresh.rawValue
    @EnvironmentObject private var account: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var records: [SleepRecord]
    @AppStorage("hasSeededDemoV1") private var hasSeededDemo = false
    @State private var tab = SleepTab.sleep
    @State private var errorMessage: String?
    @StateObject private var phone = PhoneSleepMonitor()
    @StateObject private var scanner = RingScanner()
    @StateObject private var vitals = WearableVitalsStore.appStore()
    @StateObject private var healthOverview = HealthOverviewStore()
    @StateObject private var deviceSteps = DeviceStepsStore.appStore()
    @StateObject private var automaticSync = AutomaticSyncStore()
    @StateObject private var bioAlgorithm = BIOAlgorithmStore()
    @StateObject private var rawSensors = RawSensorSyncStore()
    @AppStorage("automaticHealthSyncV1") private var autoSync = true
    @State private var syncRevision = 0
    @State private var reportMilestone = DeviceReportMilestone(nil)
    private var syncIdentity: String {
        "\(account.session?.accessToken ?? "")|\(autoSync)|\(scenePhase == .active)|\(syncRevision)"
    }

    var body: some View {
        TabView(selection: $tab) {
            SleepDashboardView().tabItem { Label("睡眠", systemImage: "moon.zzz.fill") }.tag(SleepTab.sleep)
            MonitoringView().tabItem { Label("监测与设备", systemImage: "waveform.path") }.tag(SleepTab.monitoring)
            TrendsView().tabItem { Label("趋势", systemImage: "chart.bar.xaxis") }.tag(SleepTab.trends)
            NavigationStack { HealthOverviewView() }.tabItem { Label("健康", systemImage: "heart.text.clipboard") }.tag(SleepTab.health)
            SleepClassroomView(isSelected: tab == .classroom).tabItem { Label("睡眠课堂", systemImage: "book.closed.fill") }.tag(SleepTab.classroom)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: routes.target) { _, target in
            if target == "monitoring" { tab = .monitoring }
            else if target != nil { tab = .classroom }
        }
        .onAppear { if routes.target != nil { tab = routes.target == "monitoring" ? .monitoring : .classroom } }
        .task(id: account.session?.user.id) {
            if account.session != nil { await ReminderService.shared.sync(account: account); await ReminderService.shared.apply(items: content.items) }
        }
        .environmentObject(phone)
        .environmentObject(scanner)
        .environmentObject(vitals)
        .environmentObject(healthOverview)
        .environmentObject(deviceSteps)
        .environmentObject(automaticSync)
        .environmentObject(bioAlgorithm)
        .environmentObject(rawSensors)
        .environmentObject(scanner.encryptedBand)
        .onAppear {
            scanner.wearable.rawUploadScope = { [weak account] in
                guard let account, let session = account.session else { return nil }
                return "\(account.client.serviceID)|\(session.user.id)"
            }
        }
        .task(id: syncIdentity) {
            if account.session == nil { rawSensors.reset(); automaticSync.reset(); await SyncPreparationWorker.shared.clear() }
            guard autoSync, scenePhase == .active, !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            while !Task.isCancelled {
                let session = account.session
                let input = SyncPreparationInput(sleep: records.map(SleepSyncSnapshot.init), steps: deviceSteps.rows,
                    healthSteps: LocalStepDay.read(healthOverview.snapshot), vitals: vitals.samples)
                let batch = await SyncPreparationWorker.shared.prepare(input)
                guard !Task.isCancelled, session?.accessToken == account.session?.accessToken else { return }
                await automaticSync.sync(batch.requests, session: session, service: account.client.serviceID,
                    api: AutomaticSyncAPI(client: account.client), fingerprints: batch.fingerprints)
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in syncRevision += 1 }
        .onReceive(vitals.$samples.dropFirst()) { _ in syncRevision += 1 }
        .onReceive(deviceSteps.$rows.dropFirst()) { _ in syncRevision += 1 }
        .onReceive(healthOverview.$snapshot.dropFirst()) { _ in syncRevision += 1 }
        .onReceive(scanner.wearable.$report.map(DeviceReportMilestone.init).removeDuplicates()) { value in
            reportMilestone = value
        }
        .task(id: "bio|\(account.session?.accessToken ?? "")|\(autoSync)|\(scenePhase == .active)|\(reportMilestone.finished?.timeIntervalSince1970 ?? 0)") {
            if account.session == nil || (!autoSync && !BIOLocalSleep.available) { bioAlgorithm.reset() }
            guard BIOLocalSleep.available || autoSync else { return }
            guard scenePhase == .active, !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
            // Sleep analysis must not wait for a backlog of ordinary health uploads.
            while !Task.isCancelled {
                await bioAlgorithm.analyze(scanner.wearable.report, account: account, context: context)
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
            }
        }
        .task(id: "\(account.session?.accessToken ?? "")|\(autoSync)|\(scenePhase == .active)|\(reportMilestone.rawFinished?.timeIntervalSince1970 ?? 0)|\(reportMilestone.finished?.timeIntervalSince1970 ?? 0)") {
            if account.session == nil { rawSensors.reset() }
            guard autoSync, scenePhase == .active, !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
            // Independent of cloud algorithms and long historical reads.
            while !Task.isCancelled {
                await rawSensors.sync(scanner.wearable.report, account: account)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onReceive(scanner.wearable.$report.compactMap { $0.flatMap(DeviceStepDay.read) }.removeDuplicates()) { day in
            deviceSteps.merge([day])
        }
        .onReceive(scanner.encryptedBand.$activityDays) { days in
            deviceSteps.merge(days.map { day in
                DeviceStepDay(device: WearableVital.deviceKey(day.deviceID.uuidString),
                              deviceName: day.deviceID == scanner.encryptedBand.deviceID ? scanner.encryptedBand.deviceName ?? "蓝牙设备" : deviceSteps.rows.first(where: { $0.device == WearableVital.deviceKey(day.deviceID.uuidString) })?.deviceName ?? "蓝牙设备",
                              day: day.day, steps: day.steps, readAt: day.updatedAt, dayBasis: "设备记录日期")
            })
        }
        .onReceive(scanner.wearable.$history) { history in
            guard let history else { return }
            if let report = scanner.wearable.report {
                do { try BIONight.save(BIONight.payloads(report: report, history: history), in: context) }
                catch { errorMessage = "夜间观测未能保存：\(error.localizedDescription)" }
            }
            do { scanner.wearable.didSaveHistory(count: try vitals.merge(history.vitals), total: history.vitals.count) }
            catch { scanner.wearable.didSaveHistory(count: nil, total: history.vitals.count, error: error.localizedDescription) }
        }
        .onReceive(scanner.encryptedBand.$batchID.dropFirst()) { _ in
            scanner.encryptedBand.save(in: context, vitals: vitals)
        }
        .onChange(of: scanner.latestVitals) { _, samples in
            let spaced = samples.filter { sample in
                let previous = vitals.samples.last { $0.device == sample.device && $0.kind == sample.kind && $0.origin == sample.origin }
                return previous.map { sample.date.timeIntervalSince($0.date) >= 60 } ?? true
            }
            guard !spaced.isEmpty else { return }
            do { try vitals.merge(spaced) } catch { errorMessage = "体征未能保存：\(error.localizedDescription)" }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-monitor") { tab = .monitoring }
            if ProcessInfo.processInfo.arguments.contains("-preview-health") { tab = .health }
            #endif
            #if targetEnvironment(macCatalyst)
            try? await Task.sleep(for: .milliseconds(500))
            if ProcessInfo.processInfo.arguments.contains("-compact-preview"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 390, height: 600)
                scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(x: 480, y: 40, width: 430, height: 810)))
            }
            #endif
            let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            #if DEBUG
            if testing, ProcessInfo.processInfo.arguments.contains("-ui-testing-device-sleep"),
               let sample = SampleSleepRecords.makeMonth().first {
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-dense-bio") {
                    BIONightPerformanceFixture.make().forEach { context.insert(SleepRecord($0)) }
                } else {
                var payload = sample.payload
                payload.source = .band; payload.metadata = SleepMetadata(externalSource: "设备界面测试示例 · 非真实数据")
                context.insert(SleepRecord(payload))
                }
                try? context.save()
            }
            #endif
            guard !hasSeededDemo || testing else { return }
            do {
                if records.isEmpty {
                    SampleSleepRecords.makeMonth().forEach { context.insert($0) }
                    try context.save()
                }
                hasSeededDemo = true
            } catch {
                context.rollback()
                errorMessage = error.localizedDescription
            }
        }
        .alert("记录未能保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(SleepPalette.ink)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(SleepPalette.muted) }
        }
    }
}

struct SourceTag: View {
    let source: SleepDataSource
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(source == .sample ? SleepPalette.awake : SleepPalette.teal).frame(width: 5, height: 5)
            Text(source.label).font(.system(size: 11, weight: .medium)).foregroundStyle(SleepPalette.muted)
        }
    }
}

struct MetricHelp: Identifiable {
    let title: String
    let body: String
    var references: [SleepReference] = []
    var id: String { title }
}

struct MetricHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let help: MetricHelp
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    SectionHeading(title: help.title)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("关闭说明")
                }.padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(help.body).font(.system(size: 15)).foregroundStyle(SleepPalette.muted).lineSpacing(6)
                        if !help.references.isEmpty {
                            Divider()
                            Text("参考资料").font(.system(size: 14, weight: .semibold))
                            ForEach(help.references) { reference in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(reference.title).font(.system(size: 13, weight: .medium))
                                    Text("原文：\(reference.originalTitle)").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                                    Text(reference.author).font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                                }
                            }
                        }
                    }.padding(26).padding(.top, -8).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }.background(SleepPalette.background)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

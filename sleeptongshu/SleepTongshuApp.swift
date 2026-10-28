import SwiftUI
import SwiftData

@main
struct SleepTongshuApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
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
                RootTabView().modelContainer(container).tint(SleepPalette.teal).preferredColorScheme(.light)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            } else {
                ContentUnavailableView("无法打开本地记录", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "请重新启动 App。原有记录不会被自动删除。"))
            }
        }
    }
}

enum SleepPalette {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.975)
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.25)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.54)
    static let teal = Color(red: 0.08, green: 0.49, blue: 0.42)
    static let mint = Color(red: 0.37, green: 0.73, blue: 0.67)
    static let deep = Color(red: 0.30, green: 0.37, blue: 0.77)
    static let rem = Color(red: 0.66, green: 0.57, blue: 0.88)
    static let awake = Color(red: 0.91, green: 0.59, blue: 0.36)
    static let line = Color(red: 0.88, green: 0.90, blue: 0.92)
}

extension SleepStage {
    var color: Color {
        switch self { case .awake: SleepPalette.awake; case .rem: SleepPalette.rem; case .light: SleepPalette.mint; case .deep: SleepPalette.deep; case .unspecified: SleepPalette.mint; case .unobserved: SleepPalette.line }
    }
}

enum SleepTab: Hashable { case sleep, monitoring, trends }

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [SleepRecord]
    @AppStorage("hasSeededDemoV1") private var hasSeededDemo = false
    @State private var tab = SleepTab.sleep
    @State private var errorMessage: String?
    @StateObject private var phone = PhoneSleepMonitor()
    @StateObject private var scanner = BandScanner()
    @StateObject private var vitals = WearableVitalsStore.appStore()

    var body: some View {
        TabView(selection: $tab) {
            SleepDashboardView().tabItem { Label("睡眠", systemImage: "moon.zzz.fill") }.tag(SleepTab.sleep)
            MonitoringView().tabItem { Label("监测与设备", systemImage: "waveform.path") }.tag(SleepTab.monitoring)
            TrendsView().tabItem { Label("趋势", systemImage: "chart.bar.xaxis") }.tag(SleepTab.trends)
        }
        .environmentObject(phone)
        .environmentObject(scanner)
        .environmentObject(vitals)
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
    var id: String { title }
}

struct MetricHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let help: MetricHelp
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(title: help.title)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .accessibilityLabel("关闭说明")
            }
            Text(help.body).font(.system(size: 16)).foregroundStyle(SleepPalette.muted).lineSpacing(6)
            Spacer(minLength: 0)
        }.padding(26).padding(.top, 18).presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}

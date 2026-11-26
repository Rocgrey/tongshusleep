import SwiftUI
import SwiftData
import Charts

// Navigation shares the existing stores and model container; no second data stack.
enum GroveModule: String, Identifiable {
    case monitoring, trends, health
    var id: String { rawValue }
}

struct GroveModuleSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SleepGrove").font(.caption.weight(.semibold)).foregroundStyle(SleepPalette.muted)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("返回主页").accessibilityIdentifier("closeGroveModule")
            }.padding(.horizontal, 20)
            content()
        }.background(SleepPalette.background).presentationDragIndicator(.visible)
            .accessibilityElement(children: .contain).accessibilityIdentifier("groveModuleSurface")
    }
}

struct GroveModuleContent: View {
    let module: GroveModule
    var body: some View {
        GroveModuleSheet {
            switch module {
            case .monitoring: MonitoringView()
            case .trends: TrendsView()
            case .health: NavigationStack { HealthOverviewView() }
            }
        }
    }
}

struct GrovePageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SleepGrove").font(.caption.weight(.semibold)).foregroundStyle(SleepPalette.teal)
            Text(title).font(.largeTitle.bold()).foregroundStyle(SleepPalette.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GroveFeatureRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint = SleepPalette.teal
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
                .frame(width: 52, height: 56).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(SleepPalette.ink)
                Text(subtitle).font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SleepPalette.muted)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct GroveSleepShortcuts: View {
    @Binding var module: GroveModule?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 12) {
            shortcut("监测与设备", "sensor.fill", .monitoring, SleepPalette.teal)
            shortcut("趋势", "chart.xyaxis.line", .trends, SleepPalette.deep)
            shortcut("健康", "heart.fill", .health, SleepPalette.rose)
        }
    }
    private func shortcut(_ title: String, _ icon: String, _ destination: GroveModule, _ color: Color) -> some View {
        Button { module = destination } label: {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(SleepPalette.ink)
            }.frame(maxWidth: .infinity, minHeight: 72).padding(8)
                .background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityIdentifier("grove-" + destination.rawValue)
    }
}

struct GroveRelaxView: View {
    var isSelected = true
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var routes: AppRoutes
    @Environment(\.scenePhase) private var scenePhase
    @State private var route: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    NavigationLink { GoodnightView() } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            ContentCover(name: "kepu-02", ratio: 2)
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("今晚的晚安卡").font(.title3.bold())
                                    Text("放下今天，轻轻说一声晚安").font(.caption).foregroundStyle(SleepPalette.muted)
                                }
                                Spacer(); Image(systemName: "arrow.up.right")
                            }
                        }.foregroundStyle(SleepPalette.ink)
                    }.buttonStyle(.plain)
                    GrovePageHeading(title: "让今晚，慢下来", subtitle: "留一点时间，给呼吸和安静")
                    SectionHeading(title: "睡前的小练习")
                    NavigationLink { BreathingView() } label: {
                        GroveFeatureRow(title: "4-7-8 呼吸", subtitle: "吸气 4 秒 · 屏息 7 秒 · 呼气 8 秒", icon: "wind")
                    }.buttonStyle(.plain).accessibilityIdentifier("groveBreathing")
                    Divider()
                    NavigationLink { WhiteNoiseView() } label: {
                        GroveFeatureRow(title: "声音陪伴", subtitle: "选择音色，让声音按时渐弱停下", icon: "waveform", tint: SleepPalette.deep)
                    }.buttonStyle(.plain).accessibilityIdentifier("groveNoise")
                    ForEach(content.items.filter { ["noise", "breathing", "goodnight", "story"].contains($0.kind) }) { item in
                        NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(.plain)
                    }
                    NavigationLink { ReminderSettingsView() } label: {
                        GroveFeatureRow(title: "设置睡前提醒", subtitle: "到点提醒，点击后自主开始监测或放松", icon: "bell.badge", tint: SleepPalette.awake)
                    }.buttonStyle(.plain)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .task(id: "\(isSelected)|\(routes.deliveryID)|\(routes.target ?? "")") {
                    guard isSelected else { return }
                    if ["breathing", "noise", "goodnight"].contains(routes.target ?? "") { route = routes.target; routes.target = nil }
                }
                .groveCatalogRefresh(isSelected: isSelected)
                .sheet(isPresented: Binding(get: { route != nil }, set: { if !$0 { route = nil } })) {
                    NavigationStack {
                        Group {
                            if route == "breathing" { BreathingView() }
                            else if route == "noise" { WhiteNoiseView() }
                            else { GoodnightView() }
                        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { route = nil } } }
                    }
                }
        }
    }
}

struct GroveProductsView: View {
    var isSelected = true
    @EnvironmentObject private var content: ContentStore
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ProductIntroductionView()
                    if let message = content.message { Text(message).font(.caption).foregroundStyle(SleepPalette.muted) }
                    if content.isLoading { ProgressView("正在更新商品") }
                    let products = content.items.filter { $0.kind == "product" }
                    if products.isEmpty {
                        ContentUnavailableView("暂无已发布商品", systemImage: "bag", description: Text("商品发布后会在这里展示，可以下拉刷新。"))
                    }
                    ForEach(products) { item in
                        ProductTile(item: item)
                        if !item.body.isEmpty { Text(item.body).font(.body).foregroundStyle(SleepPalette.muted).lineSpacing(6) }
                    }
                    Label("购买将在京东完成", systemImage: "arrow.up.right.square").font(.caption).foregroundStyle(SleepPalette.muted)
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .groveCatalogRefresh(isSelected: isSelected)
        }
    }
}

private struct GroveCatalogRefresh: ViewModifier {
    let isSelected: Bool
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    func body(content view: Content) -> some View {
        view.refreshable { await content.refresh(client: account.client, force: true) }
            .task(id: isSelected && scenePhase == .active) {
                guard isSelected, scenePhase == .active else { return }
                while !Task.isCancelled {
                    await content.refresh(client: account.client)
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
    }
}
extension View {
    func groveCatalogRefresh(isSelected: Bool) -> some View { modifier(GroveCatalogRefresh(isSelected: isSelected)) }
}

struct GroveCenterView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var module: GroveModule?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GrovePageHeading(title: "用户中心", subtitle: "你的记录、设备与休息习惯")
                    Button { account.open(.profile) } label: {
                        GroveFeatureRow(title: account.session?.user.username ?? "我的账号", subtitle: "账号资料与健康记录同步", icon: "person.crop.circle.fill")
                    }.buttonStyle(.plain).accessibilityIdentifier("groveAccount")
                    Divider()
                    SectionHeading(title: "记录与设备")
                    Button { module = .monitoring } label: {
                        GroveFeatureRow(title: "监测与设备", subtitle: "设备连接、手机监测与本地数据", icon: "sensor.fill")
                    }.buttonStyle(.plain)
                    Button { module = .health } label: {
                        GroveFeatureRow(title: "身体状态", subtitle: "从系统健康读取真实记录", icon: "heart.text.clipboard", tint: SleepPalette.rose)
                    }.buttonStyle(.plain)
                    Divider()
                    SectionHeading(title: "为自己设定节奏")
                    NavigationLink { ReminderSettingsView() } label: {
                        GroveFeatureRow(title: "睡眠计划与提醒", subtitle: "每日内容、睡前时间与通知设置", icon: "bell", tint: SleepPalette.awake)
                    }.buttonStyle(.plain)
                    NavigationLink { AppSettingsView() } label: {
                        GroveFeatureRow(title: "设置", subtitle: "外观、候选语音与本机存储", icon: "gearshape", tint: SleepPalette.deep)
                    }.buttonStyle(.plain).accessibilityIdentifier("enhancedSettings")
                    Text("SleepGrove · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption).foregroundStyle(SleepPalette.muted).frame(maxWidth: .infinity).padding(.top, 20)
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .sheet(item: $module) { GroveModuleContent(module: $0) }
        }
    }
}

struct GroveSelfAssessmentView: View {
    @Query(sort: \SleepRecord.end, order: .reverse) private var records: [SleepRecord]
    @State private var record: SleepRecord?
    var body: some View {
        List {
            Section {
                Text("已有 AIS 自评总分时，可以选一晚保存。设备不会自动生成自评分；这里不提供未经核实的新问卷。")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted)
            }
            let available = records.filter { $0.isVisible && $0.source != .sample }
            if available.isEmpty { Text("先保存一晚真实睡眠记录，再添加自评。").foregroundStyle(SleepPalette.muted) }
            ForEach(available) { night in
                Button { record = night } label: { RecordRow(record: night) }.buttonStyle(.plain)
            }
        }.navigationTitle("睡眠自评").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .sheet(item: $record) { SleepAISView(record: $0) }
    }
}

/// A compact projection of the existing HealthKit store, never a second estimate algorithm.
struct GroveHealthSummary: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("healthManualProfile") private var manualProfile = false
    @AppStorage("healthReferenceAge") private var ageText = ""
    @State private var showsHealth = false
    private var age: ExploratoryAgeEstimate? {
        let metrics: [HealthMetric] = [.sleep, .steps, .restingHeart, .hrv]
        return FitnessAge.exploratory(Dictionary(uniqueKeysWithValues: metrics.map { ($0, health.days(for: $0)) }),
            actualAge: manualProfile ? Int(ageText) : health.snapshot?.age, now: .now)
    }
    var body: some View {
        let metrics: [HealthMetric] = [.steps, .restingHeart, .hrv]
        let available = metrics.filter { !health.days(for: $0).isEmpty }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading(title: "活动与恢复", subtitle: "来自系统健康 · 各项按自己的记录日期展示")
                    Spacer(minLength: 4)
                    Button { showsHealth = true } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("查看完整身体状态")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), alignment: .leading)], alignment: .leading, spacing: 20) {
                    ForEach(available) { metric in
                        let days = Array(health.days(for: metric).suffix(7))
                        if let latest = days.last {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(metric.title, systemImage: metric.symbol).font(.caption).foregroundStyle(SleepPalette.muted)
                                Text(latest.value.formatted(.number.precision(.fractionLength(0...1))) + " " + metric.unit)
                                    .font(.headline).foregroundStyle(SleepPalette.ink)
                                Text(latest.date.formatted(.dateTime.month().day())).font(.caption2).foregroundStyle(SleepPalette.muted)
                                Chart(days) { day in
                                    LineMark(x: .value("日期", day.date), y: .value(metric.title, day.value))
                                        .foregroundStyle(metric == .steps ? SleepPalette.teal : SleepPalette.rose)
                                    PointMark(x: .value("日期", day.date), y: .value(metric.title, day.value))
                                        .foregroundStyle(metric == .steps ? SleepPalette.teal : SleepPalette.rose).symbolSize(14)
                                }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 44)
                                    .accessibilityLabel("最近 \(days.count) 个有效记录日的\(metric.title)变化")
                            }
                        }
                    }
                }
                if let age {
                    HStack(alignment: .firstTextBaseline) {
                        Text("探索性健康年龄").font(.subheadline)
                        Spacer()
                        Text("\(age.age)").font(.title.bold()).monospacedDigit() + Text(" 岁").font(.caption)
                    }
                    Text("自定义趋势估算，尚未验证，不代表真实身体年龄。\(age.date.formatted(.dateTime.month().day())) 更新；可在身体状态中查看计算依据。")
                        .font(.caption).foregroundStyle(SleepPalette.muted)
                }
            }.sheet(isPresented: $showsHealth) { GroveModuleContent(module: .health) }
        }
    }
}

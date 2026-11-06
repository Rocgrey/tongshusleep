import SwiftUI
import Charts
import SwiftData

struct HealthOverviewView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    var embedded = false
    @State private var showsSources = false
    @State private var showsAccess = false
    @State private var detail: HealthMetric?
    @State private var help: MetricHelp?
    @AppStorage("healthManualProfile") private var manualProfile = false
    @AppStorage("healthReferenceAge") private var ageText = ""
    @AppStorage("healthReferenceSex") private var sexRaw = HealthReferenceSex.unspecified.rawValue

    private var age: Int? { manualProfile ? Int(ageText) : health.snapshot?.age }
    private var sex: HealthReferenceSex { manualProfile ? HealthReferenceSex(rawValue: sexRaw) ?? .unspecified : health.snapshot?.referenceSex ?? .unspecified }
    private var estimate: (estimate: FitnessAgeEstimate, vo2: Double, count: Int)? {
        FitnessAge.current(health.days(for: .vo2), now: .now, age: age, sex: sex)
    }
    private var exploratoryAge: ExploratoryAgeEstimate? {
        let metrics: [HealthMetric] = [.sleep, .steps, .restingHeart, .hrv]
        return FitnessAge.exploratory(Dictionary(uniqueKeysWithValues: metrics.map { ($0, health.days(for: $0)) }),
                                      actualAge: age, now: .now)
    }
    private var available: Int { HealthMetric.allCases.filter { !health.days(for: $0).isEmpty }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                heading
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-health") {
                    Label("界面测试示例 · 非真实健康数据", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
                #endif
                if let error = health.storageError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                if health.isLoading { refreshProgress }
                if let message = health.message {
                    Label(message, systemImage: health.messageIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(health.messageIsError ? SleepPalette.awake : SleepPalette.teal).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("healthRefreshMessage")
                }
                healthConnection
                if available > 0 { latestReadings }
                Divider()
                ageOverview
                Divider()
                metricGrid
                Divider()
                longTermChange
                Divider()
                recovery
                dataFooter
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 112)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .navigationTitle(embedded ? "健康概览" : "").navigationBarTitleDisplayMode(.inline)
            .toolbar(embedded ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $showsSources) { HealthSourceSelectionView() }
            .sheet(isPresented: $showsAccess) { HealthAccessHelpView() }
            .sheet(item: $help) { MetricHelpSheet(help: $0) }
            .sheet(item: $detail) { metric in HealthMetricDetailView(metric: metric) }
            .refreshable { await health.refresh(in: context) }
            .task { await health.refreshIfNeeded(in: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await health.refreshIfNeeded(in: context) } }
            }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("身体状态").font(.system(size: 28, weight: .bold))
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
            }
            Spacer(minLength: 0)
            Button { showsSources = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 19)).frame(width: 44, height: 44).background(.white, in: Circle())
            }.accessibilityLabel("健康设置").accessibilityIdentifier("healthSources").help("健康设置")
            Button { Task { await health.refresh(in: context) } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 18)).frame(width: 44, height: 44).background(.white, in: Circle())
            }.disabled(health.isLoading).accessibilityLabel("刷新系统健康").accessibilityIdentifier("refreshHealth").help("刷新系统健康")
        }
    }

    private var healthConnection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.clipboard.fill").font(.system(size: 23)).foregroundStyle(SleepPalette.rose)
                    .frame(width: 48, height: 48).background(SleepPalette.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("从系统健康读取").font(.system(size: 15, weight: .semibold))
                    Text(health.snapshot == nil ? "等待首次读取" : available == 0 ? "读取已结束 · 暂无可用记录" : "已读到 \(available) 项健康数据")
                        .font(.system(size: 12)).foregroundStyle(available > 0 ? SleepPalette.teal : SleepPalette.muted)
                        .accessibilityIdentifier("healthReadStatus")
                }
                Spacer(minLength: 0)
            }
            Text("统一读取最近 90 天的记录，无需选择设备。最大摄氧量也会读取；设备或配套 App 需先将数据写入系统健康，才会显示。")
                .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            Button { Task { await health.refresh(in: context) } } label: {
                Label(health.snapshot == nil ? "读取系统健康" : "更新健康数据", systemImage: "heart.fill")
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(health.isLoading).accessibilityIdentifier("readHealthOverview")
            if let snapshot = health.snapshot {
                HStack(spacing: 0) {
                    readStat("数据项目", value: "\(available)", tint: SleepPalette.teal)
                    readStat("记录来源", value: "\(snapshot.sources.count)", tint: SleepPalette.deep)
                    readStat("睡眠晚数", value: "\(snapshot.sleepRecords?.count ?? health.days(for: .sleep).count)", tint: SleepPalette.rose)
                }.padding(.vertical, 6)
                Text("上次读取 \(snapshot.readAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
            Button { showsAccess = true } label: { Label("没有数据？查看授权与同步步骤", systemImage: "questionmark.circle") }
                .font(.system(size: 12)).accessibilityIdentifier("healthAccessHelp")
        }.padding(.vertical, 4)
    }

    private var refreshProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("正在更新，已有数据仍可查看")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text("\(Int((health.progressValue ?? 0) * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
            }
            ProgressView(value: health.progressValue)
                .tint(SleepPalette.teal)
            Text(health.progress).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
        }.padding(14).background(SleepPalette.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("healthReadProgress")
    }

    private func readStat(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var latestReadings: some View {
        let metrics = Array([HealthMetric.hrv, .heart, .steps, .sleep, .oxygen].filter { !health.days(for: $0).isEmpty }.prefix(3))
        return HStack(alignment: .top, spacing: 12) {
            ForEach(metrics) { metric in
                Button { detail = metric } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(metric.title, systemImage: metric.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(metric.healthTint)
                        Text(health.days(for: metric).last.map { format($0.value, metric: metric) } ?? "—")
                            .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(SleepPalette.ink)
                        Text(metric.unit).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                        Text(health.days(for: metric).last?.date.formatted(.dateTime.month().day()) ?? "")
                            .font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("healthLatest-\(metric.rawValue)")
            }
        }
    }

    private var ageOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("身体年龄参考", systemImage: "figure.mind.and.body").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { showAgeHelp() } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("身体年龄参考怎么算").accessibilityIdentifier("fitnessAgeHelp")
            }
            HStack(spacing: 22) {
                HealthAgeDial(completed: exploratoryAge?.signals.count ?? 0, total: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(exploratoryAge.map { "约\($0.age)" } ?? "数据不足")
                        .font(.system(size: exploratoryAge == nil ? 26 : 40, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(SleepPalette.teal).accessibilityIdentifier("fitnessAgeValue")
                    Text(exploratoryAge == nil ? "探索性估算暂不可用" : "岁 · 探索性参考值").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    Text(age.map { "实际年龄 \($0) 岁" } ?? "实际年龄未读取到").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
                Spacer(minLength: 0)
            }
            Text("探索性健康年龄 · 不是医学或全身生物年龄").font(.system(size: 12, weight: .medium))
            if let exploratoryAge {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SleepPalette.awake)
                    Text("自定义实验算法，未经医学验证；数据变化会让结果上下波动，不代表身体真的变老或变年轻。")
                        .foregroundStyle(SleepPalette.muted)
                }.font(.system(size: 12)).lineSpacing(4)
                Text("按 \(exploratoryAge.date.formatted(.dateTime.month().day())) 的 \(exploratoryAge.signals.count) 项数据计算：\(exploratoryAge.signals.map { "\($0.title) \($0.value.formatted(.number.precision(.fractionLength(0...1)))) \($0.unit)" }.joined(separator: " · "))。每次系统健康更新后重算。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                Text("实际年龄 \(exploratoryAge.actualAge) 岁 · 趋势调整 \(exploratoryAge.age - exploratoryAge.actualAge > 0 ? "+" : "")\(exploratoryAge.age - exploratoryAge.actualAge) 岁")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(SleepPalette.muted)
            } else {
                Text(age == nil ? "先在健康设置中填写实际年龄，并确保最近 7 天至少有两类完整数据（睡眠、步数、静息心率或 HRV）。" : "最近 7 天至少需要两类同一天的完整数据。普通心率不等同于静息心率。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: age == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(age == nil ? SleepPalette.muted : SleepPalette.teal)
                    Text(age == nil ? "实际年龄未填写" : "实际年龄 \(age!) 岁")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                }
            }
            if let estimate {
                Label("研究参考心肺年龄：\(estimate.estimate.display) 岁", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(SleepPalette.teal)
                FitnessAgeScale(estimate: estimate.estimate, actualAge: age)
                Text("近 30 天有 \(estimate.count) 天最大摄氧量记录；此研究参考只作对照，不是全身生物年龄。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            }
            if exploratoryAge == nil {
                Text("近期数据不足时不强行补算。普通心率不能替代静息心率，设备也可能尚未同步睡眠或 HRV。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                ViewThatFits(in: .horizontal) {
                    HStack { ageActions }
                    VStack(alignment: .leading, spacing: 12) { ageActions }
                }
            }
        }
    }
    @ViewBuilder private var ageActions: some View {
        Button { showsAccess = true } label: { Label("健康权限指引", systemImage: "heart.text.clipboard") }
            .font(.system(size: 12)).accessibilityIdentifier("ageAccessHelp")
        Button { showsSources = true } label: { Label("补充参考资料", systemImage: "person.crop.circle") }
            .font(.system(size: 12)).accessibilityIdentifier("configureFitnessAge")
    }

    private var longTermChange: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "长期变化", subtitle: "最近 30 天与前 30 天比较")
            let change = FitnessAge.change(health.days(for: .vo2), now: .now)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("心肺能力变化").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    Text(change.map { signed($0) + "%" } ?? "数据不足").font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(SleepPalette.teal).accessibilityIdentifier("fitnessChangeValue")
                }
                Spacer()
                Button {
                    help = MetricHelp(title: "能看出衰老速度吗？", body: "短期的心率、HRV、睡眠和最大摄氧量变化，不能可靠换算成身体每年老几岁。当前没有经过验证的全身生物年龄模型，因此不输出衰老速度或“逆龄倍数”。\n\n这里显示系统健康中的心肺能力变化：（最近 30 天最大摄氧量日值中位数 ÷ 前 30 天中位数 − 1）× 100%。每段至少 3 个不同日期，今天未结束的数据不参加。设备或测量方式改变也会影响比较；正数表示该指标上升，不表示全身年轻了。")
                } label: {
                    VStack(alignment: .trailing, spacing: 7) {
                        Label("衰老速度", systemImage: "info.circle").font(.system(size: 12))
                        Text("暂不可评估").font(.system(size: 14, weight: .medium))
                    }.foregroundStyle(SleepPalette.muted).padding(.vertical, 8)
                }.accessibilityIdentifier("agingPaceHelp")
            }
            let days = health.days(for: .vo2)
            if !days.isEmpty {
                Chart(days) { day in
                    PointMark(x: .value("日期", day.date), y: .value("最大摄氧量", day.value)).symbolSize(18).foregroundStyle(SleepPalette.teal)
                }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                    .chartYAxis { AxisMarks(position: .leading) }.chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120).accessibilityLabel("最大摄氧量长期变化图")
            }
            Text(change == nil ? "最近 30 天和前 30 天，各需至少 3 天最大摄氧量记录。" : "正数表示最大摄氧量日值中位数上升。这是心肺指标变化，不是变年轻的速度。")
                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "最近的恢复线索", subtitle: "观察自己的变化，不用与别人比")
            ForEach([HealthMetric.hrv, .restingHeart, .sleep]) { metric in
                let change = HealthOverviewAnalysis.change(health.days(for: metric), now: .now)
                Button { detail = metric } label: {
                    HStack(spacing: 12) {
                        Image(systemName: metric.symbol).font(.system(size: 18)).foregroundStyle(metric.healthTint).frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title).font(.system(size: 14, weight: .medium))
                            Text(change.map { "最近两周 \(format($0.recent, metric: metric)) \(metric.unit)" } ?? "两段各需至少 7 天记录")
                                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer(minLength: 4)
                        Text(change.map { signed($0.recent - $0.previous) } ?? "—").font(.system(size: 18, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    }.contentShape(Rectangle()).padding(.vertical, 5)
                }.buttonStyle(.plain)
            }
            Text("与前两周比较，每日先取中位数，睡眠用每日时长。HRV 上下波动不一定是心理压力，也受呼吸、运动、测量条件等影响。")
                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
        }
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "健康记录", subtitle: "\(available) 项有可展示数据 · 点开看详情")
            if available == 0 {
                ContentUnavailableView("等待健康记录", systemImage: "heart.text.clipboard",
                                       description: Text("请先读取系统健康。若仍为空，请在健康 App 中允许 sleeptongshu 读取信息，并确认设备记录已同步。"))
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(HealthMetric.allCases.filter { !health.days(for: $0).isEmpty }) { metric in
                    HealthMetricTile(metric: metric, days: health.days(for: metric), sourceLabel: health.sourceSummary(for: metric),
                                     truncated: health.snapshot?.truncatedMetrics.contains(metric) == true) { detail = metric }
                }
            }
        }
    }
    private var dataFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let readAt = health.snapshot?.readAt {
                Label("上次读取 \(readAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
            }
            Text("只读取你允许的项目，本机保存，不写回系统健康。回到本页时会检查更新，也可下拉刷新；未读取到不等于身体没有该项数据。")
            Text("步数和运动时间采用系统每日统计；睡眠每晚自动保留一份较完整的记录。其他体征汇总可用样本，设备或测量方式的变化也会影响趋势。")
            ForEach(health.snapshot?.notices ?? [], id: \.self) { notice in Text(notice) }
        }.font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
    }
    private func showAgeHelp() {
        help = MetricHelp(title: "身体年龄参考怎么算？", body: FitnessAge.exploratoryExplanation + "\n\n另有一项研究参考：如果系统健康提供最大摄氧量，且年龄、参考分组和最近 30 天至少 3 天记录齐全，可展示独立的心肺参考年龄。它不是本探索算法，也不是全身生物年龄。\n\n" + FitnessAge.explanation,
                          references: [SleepReference(title: "《通过运动测试建立的心肺能力参考标准》（译名）", originalTitle: FitnessAge.referenceTitle, author: FitnessAge.referenceAuthors)])
    }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(1))) }
    private func format(_ value: Double, metric: HealthMetric) -> String { value.formatted(.number.precision(.fractionLength(metric == .steps ? 0 : 1))) }
}

extension HealthMetric {
    var healthTint: Color {
        switch self {
        case .heart, .restingHeart, .systolic, .diastolic: Color(red: 0.78, green: 0.33, blue: 0.34)
        case .sleep, .hrv: SleepPalette.deep
        case .steps, .exercise: Color(red: 0.59, green: 0.43, blue: 0.14)
        default: SleepPalette.teal
        }
    }
}

struct HealthAgeDial: View {
    let completed: Int
    var total = 4
    var body: some View {
        ZStack {
            Circle().stroke(SleepPalette.line, lineWidth: 9)
            ForEach(0..<total, id: \.self) { index in
                Circle().trim(from: Double(index) / Double(total) + 0.025, to: Double(index + 1) / Double(total) - 0.025)
                    .stroke(index < completed ? SleepPalette.teal : SleepPalette.line, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 3) {
                Text("\(completed)/\(total)").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.teal)
                Text("可用指标").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            }
        }.frame(width: 108, height: 108).padding(5)
            .accessibilityLabel("探索性参考可使用 \(completed) 项指标，共 \(total) 项")
    }
}

struct FitnessAgeScale: View {
    let estimate: FitnessAgeEstimate?
    let actualAge: Int?
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - 12)
                ZStack(alignment: .leading) {
                    Capsule().fill(SleepPalette.line).frame(height: 5)
                    if let actualAge, (20...79).contains(actualAge) {
                        Rectangle().fill(SleepPalette.muted).frame(width: 2, height: 18)
                            .offset(x: width * min(1, max(0, Double(actualAge - 25) / 50)) + 5)
                    }
                    if let estimate {
                        Circle().fill(SleepPalette.teal).frame(width: 12, height: 12)
                            .offset(x: width * min(1, max(0, (estimate.years - 25) / 50)))
                    }
                }.frame(height: 20)
            }.frame(height: 20).accessibilityHidden(true)
            HStack {
                Text("≤25 岁")
                Spacer()
                Text("心肺参考标尺")
                Spacer()
                Text("≥75 岁")
            }.font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            if estimate != nil { Text("圆点：心肺参考年龄　竖线：实际年龄").font(.system(size: 10)).foregroundStyle(SleepPalette.muted) }
        }
    }
}

struct HealthMetricTile: View {
    let metric: HealthMetric
    let days: [HealthDay]
    let sourceLabel: String
    let truncated: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(metric.title, systemImage: metric.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(metric.healthTint)
                Text(days.last.map { $0.value.formatted(.number.precision(.fractionLength(metric == .steps || metric == .exercise ? 0 : 1))) } ?? "—")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(SleepPalette.ink)
                Text(metric.unit).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                if let last = days.last {
                    Text("\(last.date.formatted(.dateTime.month().day())) · \(metric.isCumulative ? "当日记录合计" : metric == .sleep ? "睡着时长" : "样本中位数")")
                        .font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    Chart(Array(days.suffix(14))) { day in
                        BarMark(x: .value("日期", day.date), y: .value(metric.title, day.value)).foregroundStyle(metric.healthTint.opacity(0.7))
                            .cornerRadius(2)
                    }.chartYScale(domain: .automatic(includesZero: metric.isCumulative || metric == .sleep))
                        .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 38).accessibilityHidden(true)
                } else {
                    Text(truncated ? "记录过多，暂不合计" : "暂无可展示记录").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    Color.clear.frame(height: 28)
                }
                Text(sourceLabel).font(.system(size: 10)).foregroundStyle(SleepPalette.muted).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(metric.healthTint.opacity(0.6)).padding(14) }
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(metric.healthTint.opacity(0.08)) }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("healthMetric-\(metric.rawValue)")
    }
}

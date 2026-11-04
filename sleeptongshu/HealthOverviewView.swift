import SwiftUI
import Charts

struct HealthOverviewView: View {
    @EnvironmentObject private var health: HealthOverviewStore
    var embedded = false
    @State private var showsSources = false
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
                if health.isLoading {
                    HStack(spacing: 10) { ProgressView(); Text(health.progress).font(.system(size: 13)) }
                        .padding(.vertical, 8).accessibilityIdentifier("healthReadProgress")
                }
                if health.snapshot == nil { firstRead }
                ageOverview
                Divider()
                longTermChange
                Divider()
                recovery
                Divider()
                metricGrid
                dataFooter
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 40)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .navigationTitle(embedded ? "健康概览" : "").navigationBarTitleDisplayMode(.inline)
            .toolbar(embedded ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $showsSources) { HealthSourceSelectionView() }
            .sheet(item: $help) { MetricHelpSheet(help: $0) }
            .sheet(item: $detail) { metric in HealthMetricDetailView(metric: metric) }
            .alert("系统健康", isPresented: Binding(get: { health.message != nil && !showsSources }, set: { if !$0 { health.message = nil } })) {
                Button("知道了", role: .cancel) { health.message = nil }
            } message: { Text(health.message ?? "") }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("身体状态").font(.system(size: 28, weight: .bold))
                Text("看见变化，照顾好自己").font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
            }
            Spacer(minLength: 0)
            Button { showsSources = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 19)).frame(width: 44, height: 44).background(.white, in: Circle())
            }.accessibilityLabel("健康数据来源与参考资料").accessibilityIdentifier("healthSources").help("选择数据来源与参考资料")
            Button { Task { await health.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 18)).frame(width: 44, height: 44).background(.white, in: Circle())
            }.disabled(health.isLoading).accessibilityLabel("刷新系统健康").accessibilityIdentifier("refreshHealth").help("刷新系统健康")
        }
    }

    private var firstRead: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("让已有的健康记录在这里相遇", systemImage: "heart.text.clipboard").font(.system(size: 15, weight: .semibold))
            Text("从系统健康读取最近 90 天的记录，你可以分别选择睡眠、体征和活动的来源与设备。所有计算在本机完成。")
                .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
            Button { Task { await health.refresh() } } label: {
                Label("读取系统健康", systemImage: "heart.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(health.isLoading).accessibilityIdentifier("readHealthOverview")
        }.padding(.vertical, 4)
    }

    private var ageOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("身体年龄参考", systemImage: "figure.mind.and.body").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { showAgeHelp() } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("身体年龄参考怎么算").accessibilityIdentifier("fitnessAgeHelp")
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(estimate?.estimate.display ?? "—").font(.system(size: 56, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(SleepPalette.teal).accessibilityIdentifier("fitnessAgeValue")
                Text("岁").font(.system(size: 15)).foregroundStyle(SleepPalette.muted)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("实际年龄").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                    Text(age.map { "\($0) 岁" } ?? "未填写").font(.system(size: 20, weight: .medium, design: .rounded))
                }
            }
            Text("心肺参考年龄 · 不等于全身生物年龄").font(.system(size: 12, weight: .medium))
            FitnessAgeScale(estimate: estimate?.estimate, actualAge: age)
            if let estimate {
                Text("近 30 天有 \(estimate.count) 天记录，最大摄氧量中位数 \(estimate.vo2.formatted(.number.precision(.fractionLength(1)))) mL/kg/min。")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                Text("\(health.source(for: .vo2)?.label ?? "所选来源") · \(sex.title)")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            } else {
                Text(ageMissingReason).font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                Button { showsSources = true } label: { Label("选择来源与参考资料", systemImage: "slider.horizontal.3") }
                    .font(.system(size: 13)).accessibilityIdentifier("configureFitnessAge")
            }
        }
    }
    private var ageMissingReason: String {
        if age == nil || sex == .unspecified { return "先读取或填写实际年龄与参考分组，再选择有最大摄氧量记录的设备。资料不够时不显示估算年龄。" }
        if !(20...79).contains(age!) { return "目前参考表只覆盖 20～79 岁，超出范围暂不估算。" }
        return "最近 30 个完整自然日需要至少 3 天最大摄氧量记录。没有读到时，不能用心率或睡眠时长代替计算年龄。"
    }

    private var longTermChange: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "长期变化", subtitle: "同一来源，最近 30 天与前 30 天比较")
            let change = FitnessAge.change(health.days(for: .vo2), now: .now)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("心肺能力变化").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    Text(change.map { signed($0) + "%" } ?? "—").font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(SleepPalette.teal).accessibilityIdentifier("fitnessChangeValue")
                }
                Spacer()
                Button {
                    help = MetricHelp(title: "能看出衰老速度吗？", body: "短期的心率、HRV、睡眠和最大摄氧量变化，不能可靠换算成身体每年老几岁。当前没有经过验证的全身生物年龄模型，因此不输出衰老速度或“逆龄倍数”。\n\n这里显示的是所选同一来源的心肺能力变化：（最近 30 天最大摄氧量日值中位数 ÷ 前 30 天中位数 − 1）× 100%。每段至少 3 个不同日期，今天未结束的数据不参加。正数表示该指标上升，不表示全身年轻了。")
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
            Text(change == nil ? "每段至少需要 3 天最大摄氧量记录。缺少资料时保留空白，不补算衰老速度。" : "正数表示最大摄氧量日值中位数上升。这是心肺指标变化，不是变年轻的速度。")
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
            HStack {
                SectionHeading(title: "健康记录", subtitle: "\(available) 项有可展示数据 · 点开看详情")
                Spacer(minLength: 0)
                Button { showsSources = true } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 40, height: 40) }
                    .accessibilityLabel("选择各项健康数据来源")
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(HealthMetric.allCases) { metric in
                    HealthMetricTile(metric: metric, days: health.days(for: metric), source: health.source(for: metric),
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
            Text("只读取你允许的项目，本机保存，不写回系统健康。快照需手动刷新，可能与系统最新记录不同；未读取到不等于身体没有该项数据。")
            Text("累计项目仅统计所选来源。区间重叠、跨日且无法核对、超出读取上限的记录不生成日合计，避免重复相加。")
        }.font(.system(size: 11)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
    }
    private func showAgeHelp() {
        help = MetricHelp(title: "身体年龄参考怎么算？", body: FitnessAge.explanation,
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
    let source: HealthDataSource?
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
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 28).accessibilityHidden(true)
                } else {
                    Text(truncated ? "记录过多，暂不合计" : "暂无可展示记录").font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    Color.clear.frame(height: 28)
                }
                Text(source?.deviceName ?? "尚未选择设备").font(.system(size: 10)).foregroundStyle(SleepPalette.muted).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 185, alignment: .topLeading).padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("healthMetric-\(metric.rawValue)")
    }
}

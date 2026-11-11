import SwiftUI
import SwiftData

struct SleepDashboardView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var health: HealthOverviewStore
    @EnvironmentObject private var deviceSteps: DeviceStepsStore
    @EnvironmentObject private var deviceVitals: WearableVitalsStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Query(sort: \SleepRecord.end, order: .reverse) private var storedRecords: [SleepRecord]
    @State private var sourceOverride: SleepDashboardSource?
    private var source: SleepDashboardSource {
        sourceOverride ?? SleepDashboardSource.preferred(records: storedRecords, hasDeviceData: !deviceSteps.rows.isEmpty || !deviceVitals.visibleSamples.isEmpty, hasReadHealth: health.snapshot?.sleepReadAt != nil)
    }
    private var records: [SleepRecord] { storedRecords.filter { source.includes($0) } }
    private var systemSleepSelected: Bool { source == .health }
    @State private var selectedID: UUID?
    @State private var showsHistory = false
    @State private var showsEditor = false
    @State private var showsAIS = false
    @State private var help: MetricHelp?
    @AppStorage("sleepGoalHours") private var goal = 8.0

    private var selected: SleepRecord? {
        records.first { $0.id == selectedID }
            ?? (systemSleepSelected ? records.first(where: \.hasSleepDuration) : nil)
            ?? records.first { $0.source != .sample } ?? records.first
    }
    private var selectedIndex: Int { records.firstIndex { $0.id == selected?.id } ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    brandHeader
                    Picker("睡眠来源", selection: Binding(get: { source }, set: { sourceOverride = $0; selectedID = nil })) {
                        ForEach(SleepDashboardSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("sleepDashboardSource")
                    if systemSleepSelected { SystemSleepImportView() }
                    else {
                        DisclosureGroup("从系统健康读取（可选）") { SystemSleepImportView().padding(.top, 12) }
                            .font(.subheadline).accessibilityIdentifier("optionalSystemHealth")
                    }
                    DeviceStepsSummaryView()
                    AutomaticSyncStatusView()
                    if let record = selected {
                        dateNavigation(record)
                        if let night = record.metadata?.bioNight, !record.hasSleepDuration {
                            BIONightView(record: record, night: night)
                        } else {
                        overview(record)
                        if record.source == .healthKit { SystemSleepSourceView(record: record) }
                        if let phone = record.metadata?.phone { PhoneReportView(night: phone) }
                        stages(record)
                        if let night = record.metadata?.bioNight { BIONightView(record: record, night: night) }
                        else { vitals(record) }
                        analysis(record)
                        }
                        if record.source != .sample {
                            Button { showsAIS = true } label: { Label("睡眠自评", systemImage: "list.clipboard") }
                                .font(.subheadline).accessibilityIdentifier("openSleepAIS")
                        }
                        if record.source == .sample {
                            Label("当前为预览记录，真实睡眠单独保存。可在本地数据中移除预览记录。", systemImage: "info.circle")
                                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                        }
                    } else if source == .device {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("暂无设备睡眠记录", systemImage: "moon.zzz").font(.headline).foregroundStyle(SleepPalette.ink)
                            Text("设备尚未返回可用的睡眠结果。已有体征或睡眠原始输入时，不推算睡眠时长和分期；无需先读取系统健康。")
                                .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } else {
                        ContentUnavailableView {
                            Label(systemSleepSelected ? "暂无系统睡眠" : "从第一晚开始", systemImage: "moon.zzz")
                        } description: { Text(systemSleepSelected ? HealthOverviewStore.noSleepMessage : "添加睡眠时间，逐渐了解自己的节奏。") }
                        actions: { Button("添加记录") { showsEditor = true }.buttonStyle(.borderedProminent) }
                        .padding(.vertical, 40)
                    }
                    if !systemSleepSelected { DeviceRecentVitalsView() }
                }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 26)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SleepPalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await health.refreshSleepIfNeeded(in: context)
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.refreshSleepIfNeeded(in: context) } } }
            .sheet(isPresented: $showsEditor) { SleepEditorView() }
            .sheet(isPresented: $showsAIS) { if let record = selected { SleepAISView(record: record) } }
            .sheet(item: $help) { MetricHelpSheet(help: $0) }
            .sheet(isPresented: $showsHistory) {
                NavigationStack {
                    List(records) { record in
                        Button { selectedID = record.id; showsHistory = false } label: {
                            RecordRow(record: record)
                        }.buttonStyle(.plain)
                    }
                    .navigationTitle("睡眠记录").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showsHistory = false } } }
                }.presentationDragIndicator(.visible)
            }
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("sleeptongshu").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(SleepPalette.ink)
                Text("睡眠同书 · 每一晚，都值得了解").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
            Spacer(minLength: 8)
            Button { showsEditor = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    .frame(width: 42, height: 42).background(SleepPalette.surface, in: Circle())
            }.accessibilityLabel("添加睡眠记录").accessibilityIdentifier("addSleep")
        }
    }

    private func dateNavigation(_ record: SleepRecord) -> some View {
        HStack {
            Button { selectedID = records[selectedIndex + 1].id } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36)
            }.disabled(selectedIndex + 1 >= records.count).accessibilityLabel("上一晚")
            Spacer(minLength: 0)
            Button { showsHistory = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar").font(.system(size: 12))
                    VStack(spacing: 3) {
                        Text(record.day.formatted(.dateTime.month().day())).font(.subheadline.weight(.semibold))
                        Text(record.displayClock(record.start) + "–" + record.displayClock(record.end))
                            .font(.caption).foregroundStyle(SleepPalette.muted)
                    }
                }
            }.accessibilityLabel("选择睡眠日期")
            Spacer(minLength: 0)
            Button { selectedID = records[selectedIndex - 1].id } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36)
            }.disabled(selectedIndex == 0).accessibilityLabel("下一晚")
        }.foregroundStyle(SleepPalette.ink).padding(.horizontal, -9).padding(.vertical, -8)
    }

    private func overview(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    SourceTag(source: record.source)
                    if record.source == .band, let name = record.metadata?.externalSource {
                        Text(name).font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("给身体，一晚好眠").font(.system(size: 19, weight: .bold)).foregroundStyle(SleepPalette.ink)
                    Text(record.source == .phone ? "估算睡眠时长" : "总睡眠时长").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    if !record.hasSleepDuration {
                        Text(record.onlyInBed ? "仅有卧床记录" : record.metadata?.bioNight != nil ? "夜间观测" : "待估算").font(.title2.weight(.semibold)).foregroundStyle(SleepPalette.ink)
                    } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(record.asleepMinutes / 60)").font(.system(size: 41, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("小时").font(.system(size: 13)).padding(.trailing, 3)
                        Text("\(record.asleepMinutes % 60)").font(.system(size: 41, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("分").font(.system(size: 13))
                    }.foregroundStyle(SleepPalette.ink).minimumScaleFactor(0.75).lineLimit(1)
                        .accessibilityElement(children: .ignore).accessibilityLabel(SleepRecord.durationText(record.asleepMinutes))
                        .accessibilityIdentifier("totalSleepDuration")
                    }
                }
                Spacer(minLength: 8)
                if record.source != .healthKit && record.metadata?.bioNight == nil { Button {
                    help = SleepMetricGuide.score(record)
                } label: { scoreRing(record) }.buttonStyle(.plain).accessibilityLabel("睡眠参考分说明") }
            }
            if record.hasSleepDuration { VStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SleepPalette.teal.opacity(0.1))
                        Capsule().fill(SleepPalette.teal).frame(width: proxy.size.width * min(1, Double(record.asleepMinutes) / (goal * 60)))
                    }
                }.frame(height: 4)
                HStack {
                    Text("睡眠目标 \(goal.formatted(.number.precision(.fractionLength(0...1)))) 小时")
                    Spacer()
                    Text(Double(record.asleepMinutes) >= goal * 60 ? "已达成" : "还差 \(SleepRecord.durationText(max(0, Int(goal * 60) - record.asleepMinutes)))")
                }.font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            } }
            LazyVGrid(columns: [GridItem(dynamicType.isAccessibilitySize ? .flexible() : .adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 14) {
                timeValue(record.source == .phone ? "估算入睡" : "入睡时间", value: record.source == .phone ? record.metadata?.phone?.estimatedOnset.map(SleepRecord.clock) ?? "--" : record.sleepOnset.map(record.displayClock) ?? "--", symbol: "moon.fill")
                timeValue(record.source == .phone ? "结束采集" : "睡眠结束", value: record.sleepEnd.map(record.displayClock) ?? "--", symbol: "sun.max.fill")
                Button { help = SleepMetricGuide.efficiency(record) } label: {
                    timeValue("睡眠效率", value: record.efficiency.map { "\($0)%" } ?? "--", symbol: "leaf.fill", showsInfo: true)
                }.buttonStyle(.plain).accessibilityLabel("睡眠效率说明")
            }
        }
        .padding(.vertical, 10)
    }

    private func scoreRing(_ record: SleepRecord) -> some View {
        ZStack {
            Circle().stroke(SleepPalette.teal.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(record.score ?? 0) / 100)
                .stroke(SleepPalette.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(record.score.map(String.init) ?? "--").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("参考分").font(.system(size: 10))
            }.foregroundStyle(SleepPalette.teal)
        }.frame(width: 82, height: 82).padding(.top, 24)
    }

    private func timeValue(_ title: String, value: String, symbol: String, showsInfo: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Label(title, systemImage: symbol)
                if showsInfo { Image(systemName: "info.circle") }
            }.font(.caption).foregroundStyle(SleepPalette.muted)
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(SleepPalette.ink)
        }
    }

    private func stages(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                SectionHeading(title: "睡眠阶段", subtitle: "看见身体整夜的恢复节奏")
                Spacer()
                Button {
                    help = SleepMetricGuide.stages(record)
                } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }.accessibilityLabel("睡眠阶段说明")
            }
            if record.source == .healthKit && !record.hasStages {
                Text(record.onlyInBed ? "仅有卧床记录，不能据此生成睡眠时长或分期。" : "未分期睡眠 · 只展示来源实际记录的睡眠时长，不推算深睡、浅睡或 REM。")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            } else if !record.segments.isEmpty {
                StageTimeline(record: record)
                SleepStageBalance(record: record)
                if record.segments.contains(where: { [.unobserved, .unspecified].contains($0.stage) }) {
                    Text("未分期睡眠 \(record.minutes(.unspecified)) 分 · 未记录 \(record.minutes(.unobserved)) 分。缺口不会计作清醒或深睡；分期比例可能不可用。")
                        .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                }
                if record.hasStages { LazyVGrid(columns: [GridItem(dynamicType.isAccessibilitySize ? .flexible() : .adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 14) {
                    ForEach([SleepStage.deep, .light, .rem, .awake]) { stage in
                        Button { help = SleepMetricGuide.stage(stage, record: record) } label: { VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 4) { Circle().fill(stage.color).frame(width: 5, height: 5); Text(stage.label).font(.system(size: 10)) }
                            Text(stage == .awake && record.awakeMinutes == nil || record.source == .healthKit && stage != .awake && !record.segments.contains(where: { $0.stage == stage }) ? "--" : "\(record.minutes(stage))").font(.title3.weight(.semibold)) + Text(" 分").font(.caption)
                            Text(stage == .awake ? "清醒时段" : record.share(stage).map { "\($0)%" } ?? "--")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(SleepPalette.muted)
                        }.foregroundStyle(SleepPalette.ink).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("\(stage.label)说明")
                    }
                } }
                if record.hasStages {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([SleepStage.deep, .light, .rem]) { stage in
                            Button { help = SleepMetricGuide.stage(stage, record: record) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Circle().fill(stage.color).frame(width: 7, height: 7).padding(.top, 5)
                                    Text(stage.label).font(.system(size: 12, weight: .medium))
                                    Spacer(minLength: 4)
                                    Text(SleepMetricGuide.referenceText(stage)).font(.system(size: 11)).multilineTextAlignment(.trailing)
                                    Image(systemName: "info.circle").font(.system(size: 12))
                                }.frame(minHeight: 44).contentShape(Rectangle()).foregroundStyle(SleepPalette.muted)
                            }.buttonStyle(.plain).accessibilityLabel("\(stage.label)参考范围")
                        }
                        Text("成人的一般参考。年龄和设备会影响结果，不必每晚都达到。")
                            .font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                    }
                }
            } else {
                Text(record.source == .manual ? "手动记录包含睡眠时间，暂无睡眠分期。" : "此来源未提供睡眠分期；手机声音与体动不能区分深睡、浅睡或 REM。")
                    .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).padding(.vertical, 22)
            }
        }
    }

    private func vitals(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "夜间健康体征", subtitle: "睡着以后，身体也在告诉你一些事")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                metric("平均心率", value: record.averageHeartRate.map { String(format: "%.0f", $0) } ?? "--", unit: "次/分", icon: "heart.fill", color: SleepPalette.awake,
                       explanation: "睡眠期间的平均心率。关注多晚的个人趋势比比较单次数字更有意义。没有测量数据时显示 --。")
                metric("平均血氧", value: record.averageSpO2.map { String(format: "%.1f", $0) } ?? "--", unit: "%", icon: "drop.fill", color: SleepPalette.deep,
                       explanation: "睡眠期间的平均血氧饱和度。佩戴松紧、动作和传感器贴合会影响结果；平均值不能反映所有短暂波动。")
            }.background(SleepPalette.line).clipShape(RoundedRectangle(cornerRadius: 8))
            Button { help = SleepMetricGuide.stage(.awake, record: record) } label: {
                HStack {
                    Label("夜间清醒", systemImage: "eye")
                    Spacer()
                    Text(record.awakenings.map { "\($0) 次" } ?? "--")
                    Image(systemName: "info.circle")
                }.frame(minHeight: 44).contentShape(Rectangle()).font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
            }.buttonStyle(.plain).accessibilityLabel("夜间清醒说明")
            if !record.heartSamples.isEmpty {
                Text("睡眠心率变化").font(.system(size: 12, weight: .medium)).foregroundStyle(SleepPalette.muted).padding(.top, 5)
                HeartRateChart(samples: record.heartSamples)
            }
        }
    }

    private func metric(_ title: String, value: String, unit: String, icon: String, color: Color, explanation: String) -> some View {
        Button { help = MetricHelp(title: title, body: explanation) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title).foregroundStyle(SleepPalette.muted)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle").font(.system(size: 9)).foregroundStyle(SleepPalette.muted.opacity(0.7))
                }.font(.system(size: 11))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.ink)
                    Text(unit).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(SleepPalette.surface)
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(value)\(unit)，查看说明")
    }

    private func analysis(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "这一晚的小结")
            if record.hasSleepDuration {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(SleepPalette.teal).padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.asleepMinutes >= 420 ? "睡眠时长比较充足" : "给睡眠再留一点时间").font(.system(size: 15, weight: .semibold))
                    Text("\(record.source == .phone ? "手机信号估算约" : "这一晚睡了") \(SleepRecord.durationText(record.asleepMinutes))。\(record.asleepMinutes >= 420 ? "多数成年人可参考每晚 7–9 小时，再结合白天精神状态调整。" : "可以尝试把睡前准备提前一些，观察连续几天的变化。")")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                }
            }
            } else {
                Text(record.onlyInBed ? "仅有卧床记录，不能据此判断入睡时间、睡眠时长或睡眠阶段。" : "本次仅记录采集时段与环境信号，暂不能判断睡眠时长或睡眠质量。建议按监测页面的摆放提示完成整晚采集。")
                    .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
            }
            if let share = record.deepShare {
                Divider()
                HStack { Text("深睡占比").foregroundStyle(SleepPalette.muted); Spacer(); Text("\(share)%").fontWeight(.semibold) }.font(.system(size: 13))
                Text("深睡时间 ÷ 睡着的总时间。每晚有所不同，连续几晚一起看更有用。")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
            if !record.note.isEmpty { Divider(); Label(record.note, systemImage: "note.text").font(.system(size: 13)) }
            Text("体征与睡眠阶段供个人观察，不用于医疗诊断。")
                .font(.system(size: 10)).foregroundStyle(SleepPalette.muted).padding(.top, 4)
        }.foregroundStyle(SleepPalette.ink)
    }
}

struct RecordRow: View {
    let record: SleepRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.fill").foregroundStyle(SleepPalette.deep).frame(width: 34, height: 34)
                .background(SleepPalette.deep.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(record.day.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.system(size: 13, weight: .medium))
                Text("\(record.displayClock(record.start)) – \(record.displayClock(record.end)) · \(record.source.label)")
                    .font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            }
            Spacer(minLength: 4)
            Text(record.hasSleepDuration ? SleepRecord.durationText(record.asleepMinutes) : record.onlyInBed ? "仅有卧床记录" : record.metadata?.bioNight != nil ? "夜间观测" : "待估算").font(.system(size: 13, weight: .semibold, design: .rounded))
        }.foregroundStyle(SleepPalette.ink).padding(.vertical, 5).contentShape(Rectangle())
    }
}

struct TrendsView: View {
    @Query(sort: \SleepRecord.end) private var storedRecords: [SleepRecord]
    private var records: [SleepRecord] { storedRecords.filter(\.isVisible) }
    @State private var days = 7
    @State private var stepsMode = false
    @State private var metric = TrendMetric.duration
    @State private var detail: SleepRecord?
    @State private var sourceFilter: String?
    @AppStorage("sleepGoalHours") private var goal = 8.0

    private var periodRecords: [SleepRecord] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: .now))!
        let source = sourceFilter ?? records.last(where: { $0.source != .sample })?.seriesKey ?? SleepDataSource.sample.rawValue
        return records.filter { $0.day >= start && $0.end <= .now && $0.seriesKey == source }
    }
    private var durations: [Int] { SleepTrendDay.summarize(periodRecords).map(\.asleepMinutes) }
    private var average: Int { durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stepsMode ? "活动趋势" : "睡眠趋势").font(.system(size: 27, weight: .bold)).foregroundStyle(SleepPalette.ink)
                        Text(stepsMode ? "让每一天的活动都看得见" : "比起某一晚，更在意每一天的节奏").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    }
                    Picker("统计内容", selection: $stepsMode) { Text("睡眠").tag(false); Text("步数").tag(true) }
                        .pickerStyle(.segmented).accessibilityIdentifier("trendCategory")
                    Picker("时间范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented)
                        .accessibilityIdentifier("trendPeriod")
                    if stepsMode {
                        AccountStepsSection(days: days)
                    } else {
                        sleepTrends
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .sheet(item: $detail) { record in RecordDetailView(record: record) }
        }
    }

    @ViewBuilder private var sleepTrends: some View {
        Picker("数据来源", selection: $sourceFilter) {
            Text("自动选择来源").tag(nil as String?)
            ForEach(Array(Set(records.map(\.seriesKey))).sorted(), id: \.self) { key in
                Text(records.first { $0.seriesKey == key }?.seriesLabel ?? key).tag(Optional(key))
            }
        }.font(.system(size: 12))
        Text("不同来源分别统计，示例不会与真实记录混合。手机时长为信号估算，未能估算的记录不计入平均。")
            .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
        if periodRecords.isEmpty {
            ContentUnavailableView("暂无这段时间的记录", systemImage: "chart.bar", description: Text("添加睡眠记录后查看趋势。"))
        } else {
            VStack(alignment: .leading, spacing: 15) {
                if let record = periodRecords.last { SourceTag(source: record.source) }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日均睡眠时长").font(.subheadline).foregroundStyle(SleepPalette.muted)
                        Text(durations.isEmpty ? "--" : SleepRecord.durationText(average)).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.ink)
                    }
                    Spacer()
                    Text("\(periodRecords.count) 条记录").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                }
                Picker("统计指标", selection: $metric) { ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("trendMetric")
                if durations.isEmpty {
                    Text("这段时间仅有卧床记录，尚无可统计的真实睡眠时长。").font(.subheadline).foregroundStyle(SleepPalette.muted)
                } else { SleepTrendChart(records: periodRecords, metric: metric, goal: goal) }
                Text("按睡眠结束日汇总；同一天的夜间睡眠与午睡合并计算时长。没有睡眠记录的日期不计入日均。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                Label(metric == .duration ? "虚线为你的睡眠目标" : "缺少睡眠阶段的记录不参与此项统计", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            }
            Divider()
            HStack(spacing: 12) {
                trendStat("最长一天", value: durations.max().map(SleepRecord.durationText) ?? "--")
                Spacer()
                trendStat("达成目标", value: durations.isEmpty ? "--" : "\(durations.filter { Double($0) >= goal * 60 }.count) 天")
            }
            SleepRegularityChart(records: periodRecords)
            SectionHeading(title: "每日记录", subtitle: "点开一晚，查看完整数据")
            LazyVStack(spacing: 0) {
                ForEach(periodRecords.reversed()) { record in
                    Button { detail = record } label: { RecordRow(record: record) }.buttonStyle(.plain)
                    Divider().padding(.vertical, 8)
                }
            }
        }
    }

    private func trendStat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.ink)
        }
    }
}

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let record: SleepRecord
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var help: MetricHelp?
    var body: some View {
        NavigationStack {
            List {
                Section { RecordRow(record: record) }
                if !record.isVisible { Section { Text("此系统记录已归档，不参与睡眠统计；独立备注仍保留。") } }
                if record.source == .healthKit { Section("系统记录来源") { SystemSleepSourceView(record: record) } }
                if let phone = record.metadata?.phone { Section { PhoneReportView(night: phone) } }
                if let night = record.metadata?.bioNight { Section { BIONightView(record: record, night: night) } }
                if !record.segments.isEmpty {
                    Section("睡眠阶段") {
                        if record.source != .healthKit || record.hasStages {
                            StageTimeline(record: record).padding(.vertical, 16)
                        } else {
                            Text(record.onlyInBed ? "仅有卧床记录" : "未分期睡眠 · 不推算深睡、浅睡或 REM")
                        }
                        ForEach(SleepStage.allCases.filter { stage in record.segments.contains { $0.stage == stage } }) { stage in
                            Button { help = SleepMetricGuide.stage(stage, record: record) } label: {
                                HStack {
                                    Text(stage.label)
                                    Spacer()
                                    Text(SleepRecord.durationText(record.minutes(stage)))
                                    if let share = record.share(stage) { Text("\(share)%") }
                                    Image(systemName: "info.circle")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("指标与计算依据") {
                    Button { help = SleepMetricGuide.efficiency(record) } label: {
                        LabeledContent("睡眠效率 · 查看说明", value: record.efficiency.map { "\($0)%" } ?? "--")
                    }
                    if record.source != .healthKit { Button { help = SleepMetricGuide.score(record) } label: {
                        LabeledContent("参考分 · 查看算法", value: record.score.map(String.init) ?? "--")
                    } }
                }
                Section("健康体征") {
                    LabeledContent("平均心率", value: record.averageHeartRate.map { String(format: "%.0f 次/分", $0) } ?? "暂无数据")
                    LabeledContent("平均血氧", value: record.averageSpO2.map { String(format: "%.1f%%", $0) } ?? "暂无数据")
                }
                if !record.note.isEmpty { Section("睡前笔记") { Text(record.note) } }
                Section { Button("删除这条记录", role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle("睡眠详情").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $help) { MetricHelpSheet(help: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("删除后可通过之前的备份恢复", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) {
                    context.delete(record)
                    do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
            .alert("无法删除", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

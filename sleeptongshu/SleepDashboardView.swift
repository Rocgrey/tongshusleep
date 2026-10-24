import SwiftUI
import SwiftData

struct SleepDashboardView: View {
    @Query(sort: \SleepRecord.end, order: .reverse) private var records: [SleepRecord]
    @State private var selectedID: UUID?
    @State private var showsHistory = false
    @State private var showsEditor = false
    @State private var help: MetricHelp?
    @AppStorage("sleepGoalHours") private var goal = 8.0

    private var selected: SleepRecord? { records.first { $0.id == selectedID } ?? records.first }
    private var selectedIndex: Int { records.firstIndex { $0.id == selected?.id } ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    brandHeader
                    if let record = selected {
                        dateNavigation(record)
                        overview(record)
                        stages(record)
                        vitals(record)
                        analysis(record)
                        if record.source == .sample {
                            Label("示例记录仅供预览，尚未从手环获取数据。", systemImage: "info.circle")
                                .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("从第一晚开始", systemImage: "moon.zzz")
                        } description: { Text("添加睡眠时间，逐渐了解自己的节奏。") }
                        actions: { Button("添加记录") { showsEditor = true }.buttonStyle(.borderedProminent) }
                        .padding(.vertical, 40)
                    }
                }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 26)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SleepPalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsEditor) { SleepEditorView() }
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
                    .frame(width: 42, height: 42).background(.white, in: Circle())
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
                    Text(Calendar.current.isDateInToday(record.end) ? "昨夜" : record.end.formatted(.dateTime.month().day()))
                        .font(.system(size: 14, weight: .semibold))
                    Text(record.end.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
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
                    Text("给身体，一晚好眠").font(.system(size: 19, weight: .bold)).foregroundStyle(SleepPalette.ink)
                    Text("总睡眠时长").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(record.asleepMinutes / 60)").font(.system(size: 41, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("小时").font(.system(size: 13)).padding(.trailing, 3)
                        Text("\(record.asleepMinutes % 60)").font(.system(size: 41, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("分").font(.system(size: 13))
                    }.foregroundStyle(SleepPalette.ink).minimumScaleFactor(0.75).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    help = MetricHelp(title: "睡眠参考分", body: "参考分由睡眠时长（60%）与睡眠效率（40%）计算。时长部分以 8 小时为满分。这是 App 自定义的观察指标，并非小米、苹果或医疗机构评分；手动记录没有睡眠阶段，因此不生成分数。")
                } label: { scoreRing(record) }.buttonStyle(.plain).accessibilityLabel("睡眠参考分说明")
            }
            VStack(spacing: 7) {
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
            }
            HStack(spacing: 0) {
                timeValue("入睡时间", value: SleepRecord.clock(record.start), symbol: "moon.fill")
                Spacer()
                Rectangle().fill(SleepPalette.teal.opacity(0.12)).frame(width: 1, height: 32)
                Spacer()
                timeValue("起床时间", value: SleepRecord.clock(record.end), symbol: "sun.max.fill")
                Spacer()
                Rectangle().fill(SleepPalette.teal.opacity(0.12)).frame(width: 1, height: 32)
                Spacer()
                timeValue("睡眠效率", value: record.efficiency.map { "\($0)%" } ?? "--", symbol: "leaf.fill")
            }
        }
        .padding(20).background(Color(red: 0.90, green: 0.95, blue: 0.93), in: RoundedRectangle(cornerRadius: 8))
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

    private func timeValue(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.ink)
        }
    }

    private func stages(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                SectionHeading(title: "睡眠阶段", subtitle: "看见身体整夜的恢复节奏")
                Spacer()
                Button {
                    help = MetricHelp(title: "关于睡眠阶段", body: "深睡、浅睡和快速眼动（REM）会在一晚中交替出现。REM 与梦境、记忆加工有关，深睡参与身体恢复。手环通过传感器估算阶段，不能替代临床睡眠检查。每段色条都对应记录中的真实时间区间；示例来源表示这些区间是模拟数据。")
                } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }.accessibilityLabel("睡眠阶段说明")
            }
            if record.hasStages {
                StageTimeline(record: record)
                HStack(alignment: .top, spacing: 8) {
                    ForEach([SleepStage.deep, .light, .rem, .awake]) { stage in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 4) { Circle().fill(stage.color).frame(width: 5, height: 5); Text(stage.label).font(.system(size: 10)) }
                            Text("\(record.minutes(stage))").font(.system(size: 20, weight: .semibold, design: .rounded)) + Text(" 分").font(.system(size: 10))
                        }.foregroundStyle(SleepPalette.ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("手动记录包含睡眠时间，暂无睡眠分期。")
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
                       explanation: "睡眠期间的平均血氧饱和度。腕部松紧、动作和传感器贴合会影响结果；平均值不能反映所有短暂波动。")
                metric("平均呼吸率", value: record.averageRespiratoryRate.map { String(format: "%.1f", $0) } ?? "--", unit: "次/分", icon: "wind", color: SleepPalette.teal,
                       explanation: "睡眠期间每分钟平均呼吸次数。只有数据来源确实提供测量时才显示，不从其他指标猜测。")
                metric("夜间清醒", value: record.awakenings.map(String.init) ?? "--", unit: "次", icon: "eye", color: SleepPalette.rem,
                       explanation: "入睡后被记录为清醒的时间段数量。短暂清醒很常见，不等于整夜睡眠差。起始清醒段不计入夜间清醒次数。")
            }.background(SleepPalette.line).clipShape(RoundedRectangle(cornerRadius: 8))
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
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white)
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(value)\(unit)，查看说明")
    }

    private func analysis(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "这一晚的小结")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(SleepPalette.teal).padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.asleepMinutes >= 420 ? "睡眠时长比较充足" : "给睡眠再留一点时间").font(.system(size: 15, weight: .semibold))
                    Text(record.asleepMinutes >= 420 ? "这一晚睡了 \(SleepRecord.durationText(record.asleepMinutes))。多数成年人可参考每晚 7–9 小时，再结合白天精神状态调整。" : "这一晚睡了 \(SleepRecord.durationText(record.asleepMinutes))。可以尝试把睡前准备提前一些，观察连续几天的变化。")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(4)
                }
            }
            if let share = record.deepShare {
                Divider()
                HStack { Text("深睡占比").foregroundStyle(SleepPalette.muted); Spacer(); Text("\(share)%").fontWeight(.semibold) }.font(.system(size: 13))
                Text("按深睡时长 ÷ 总睡眠时长计算。单晚比例自然波动，建议结合多晚观察。")
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
                Text(record.end.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.system(size: 13, weight: .medium))
                Text("\(SleepRecord.clock(record.start)) – \(SleepRecord.clock(record.end)) · \(record.source.label)")
                    .font(.system(size: 10)).foregroundStyle(SleepPalette.muted)
            }
            Spacer(minLength: 4)
            Text(SleepRecord.durationText(record.asleepMinutes)).font(.system(size: 13, weight: .semibold, design: .rounded))
        }.foregroundStyle(SleepPalette.ink).padding(.vertical, 5).contentShape(Rectangle())
    }
}

struct TrendsView: View {
    @Query(sort: \SleepRecord.end) private var records: [SleepRecord]
    @State private var days = 7
    @State private var metric = TrendMetric.duration
    @State private var detail: SleepRecord?
    @AppStorage("sleepGoalHours") private var goal = 8.0

    private var periodRecords: [SleepRecord] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: .now))!
        return records.filter { $0.end >= start && $0.end <= .now }
    }
    private var average: Int { periodRecords.isEmpty ? 0 : periodRecords.map(\.asleepMinutes).reduce(0, +) / periodRecords.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("睡眠趋势").font(.system(size: 27, weight: .bold)).foregroundStyle(SleepPalette.ink)
                        Text("比起某一晚，更在意每一天的节奏").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                    }
                    Picker("时间范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented)
                        .accessibilityIdentifier("trendPeriod")
                    if periodRecords.isEmpty {
                        ContentUnavailableView("暂无这段时间的记录", systemImage: "chart.bar", description: Text("添加睡眠记录后查看趋势。"))
                    } else {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("平均睡眠时长").font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
                                    Text(SleepRecord.durationText(average)).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(SleepPalette.ink)
                                }
                                Spacer()
                                Text("\(periodRecords.count) 条记录").font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                            }
                            Picker("统计指标", selection: $metric) { ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.segmented).accessibilityIdentifier("trendMetric")
                            SleepTrendChart(records: periodRecords, metric: metric, goal: goal)
                            Label(metric == .duration ? "虚线为你的睡眠目标" : "缺少睡眠阶段的记录不参与此项统计", systemImage: "info.circle")
                                .font(.system(size: 11)).foregroundStyle(SleepPalette.muted)
                        }
                        Divider()
                        HStack(spacing: 12) {
                            trendStat("最长一晚", value: SleepRecord.durationText(periodRecords.map(\.asleepMinutes).max() ?? 0))
                            Spacer()
                            trendStat("达成目标", value: "\(periodRecords.filter { Double($0.asleepMinutes) >= goal * 60 }.count) 晚")
                        }
                        SectionHeading(title: "每日记录", subtitle: "点开一晚，查看完整数据")
                        LazyVStack(spacing: 0) {
                            ForEach(periodRecords.reversed()) { record in
                                Button { detail = record } label: { RecordRow(record: record) }.buttonStyle(.plain)
                                Divider().padding(.vertical, 8)
                            }
                        }
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .sheet(item: $detail) { record in RecordDetailView(record: record) }
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
    var body: some View {
        NavigationStack {
            List {
                Section { RecordRow(record: record) }
                if record.hasStages {
                    Section("睡眠阶段") {
                        StageTimeline(record: record).padding(.vertical, 16)
                        ForEach(SleepStage.allCases) { stage in
                            LabeledContent(stage.label, value: SleepRecord.durationText(record.minutes(stage)))
                        }
                    }
                }
                Section("健康体征") {
                    LabeledContent("平均心率", value: record.averageHeartRate.map { String(format: "%.0f 次/分", $0) } ?? "暂无数据")
                    LabeledContent("平均血氧", value: record.averageSpO2.map { String(format: "%.1f%%", $0) } ?? "暂无数据")
                    LabeledContent("平均呼吸率", value: record.averageRespiratoryRate.map { String(format: "%.1f 次/分", $0) } ?? "暂无数据")
                }
                if !record.note.isEmpty { Section("睡前笔记") { Text(record.note) } }
                Section { Button("删除这条记录", role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle("睡眠详情").navigationBarTitleDisplayMode(.inline)
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

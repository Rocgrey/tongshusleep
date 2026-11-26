import SwiftUI
import Charts

/// A local self-report, deliberately separate from device stages and sleep uploads.
struct PSQIView: View {
    @EnvironmentObject private var account: AccountStore
    @StateObject private var history = PSQIHistory()
    @State private var takingTest = false
    @State private var selected: PSQIEntry?
    @State private var error: String?
    private var scope: String { "\(account.client.serviceID)|\(account.session?.user.id.description ?? "local")" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroveSectionBanner(title: "了解自己的睡眠", subtitle: "回顾近 1 个月，而不是只看昨晚", symbol: "moon.stars.fill", color: .lavender)
                Text("匹兹堡睡眠质量指数 · PSQI").font(.title2.bold())
                Text("18 项计分内容，汇总为 7 个方面，总分 0–21。分数越高，表示自己感受到的睡眠困扰越多。中文题目采用便于理解的表述。").foregroundStyle(SleepPalette.muted)
                Button { takingTest = true } label: {
                    Label("开始睡眠自测", systemImage: "pencil.and.list.clipboard").frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).tint(GroveColor.lavender.tint).foregroundStyle(SleepPalette.onAccent).accessibilityIdentifier("startPSQI")
                Text("仅作科普参考，不作诊断。困扰方向和改善建议根据你的回答整理，并非 PSQI 官方的失眠类型划分。结果只保存在本机，不随睡眠记录自动上传。")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
                if let message = history.message { Text(message).foregroundStyle(SleepPalette.rose) }
                if history.entries.count > 1 {
                    Text("自己的变化，比比较更重要").font(.headline)
                    Chart(history.entries.reversed()) { entry in
                        LineMark(x: .value("日期", entry.date), y: .value("PSQI", entry.result.total)).foregroundStyle(GroveColor.lavender.tint)
                        PointMark(x: .value("日期", entry.date), y: .value("PSQI", entry.result.total)).foregroundStyle(GroveColor.coral.tint)
                    }.chartYScale(domain: 0...21).frame(height: 150).accessibilityLabel("本机 PSQI 自测历史，0 到 21 分")
                }
                if history.entries.isEmpty { Text("完成后，这里会留下你的自测记录。").font(.subheadline).foregroundStyle(SleepPalette.muted) }
                ForEach(history.entries) { entry in
                    HStack {
                        Button { selected = entry } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                    Text(entry.result.quality).font(.caption).foregroundStyle(SleepPalette.muted)
                                }
                                Spacer(); Text("\(entry.result.total) / 21").font(.headline).foregroundStyle(GroveColor.lavender.tint)
                            }
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { do { try history.delete(entry.id) } catch { self.error = error.localizedDescription } } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }.accessibilityLabel("删除这次自测")
                    }.padding(.vertical, 8)
                    Divider()
                }
                DisclosureGroup("计分依据与参考资料") { PSQIReference() }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).navigationTitle("睡眠自测").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task(id: scope) { takingTest = false; selected = nil; history.load(service: account.client.serviceID, userID: account.session?.user.id) }
            .sheet(isPresented: $takingTest) {
                NavigationStack { PSQIForm { answers in selected = try history.save(answers); takingTest = false } }
            }
            .navigationDestination(isPresented: Binding(get: { selected != nil && !takingTest }, set: { if !$0 { selected = nil } })) { if let selected { PSQIResultView(entry: selected) } }
            .alert("自测记录", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") { error = nil } } message: { Text(error ?? "") }
    }
}

private struct PSQIForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let save: ([String: Double]) throws -> Void
    @State private var index = 0
    @State private var answers: [String: Double] = [:]
    @State private var number = ""
    @State private var clock = Calendar.current.startOfDay(for: .now)
    @State private var error: String?
    private var question: PSQIQuestion { PSQI.questions[index] }
    private var scene: PSQIQuestionScene { .forQuestion(question.id) }
    @FocusState private var editingNumber: Bool
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProgressView(value: Double(index + 1), total: 18).tint(scene.color.tint).id("psqiQuestionTop")
                    .accessibilityLabel("第 \(index + 1) 项，共 18 项")
                PSQIQuestionArtwork(questionID: question.id).id(question.id)
                    .transition(.opacity)
                Text("\(index + 1) / 18 · \(question.title)").font(.subheadline.weight(.semibold)).foregroundStyle(scene.color.tint)
                Text(question.text).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text("请根据近 1 个月的通常情况回答。").font(.caption).foregroundStyle(SleepPalette.muted)
                switch question.input {
                case .clock:
                    DatePicker("通常时间", selection: $clock, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
                        .onChange(of: clock) { _, date in let c = Calendar.current.dateComponents([.hour, .minute], from: date); answers[question.id] = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) }
                    Button("确认这个时间") { storeClock() }.buttonStyle(.bordered)
                case .minutes, .hours:
                    HStack {
                        TextField(question.input == .minutes ? "分钟" : "小时，可填小数", text: $number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).focused($editingNumber).accessibilityIdentifier("psqiNumber")
                            .onChange(of: number) { _, value in answers[question.id] = Double(value.replacingOccurrences(of: ",", with: ".")) }
                        Text(question.input == .minutes ? "分钟" : "小时")
                    }
                default:
                    ForEach(Array(question.options.enumerated()), id: \.offset) { offset, title in
                        Button { answers[question.id] = Double(offset) } label: {
                            HStack {
                                Image(systemName: answers[question.id] == Double(offset) ? "checkmark.circle.fill" : "circle")
                                Text(title).multilineTextAlignment(.leading); Spacer(minLength: 0)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 48)
                                .background(answers[question.id] == Double(offset) ? scene.color.wash : SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(answers[question.id] == Double(offset) ? scene.color.tint : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).foregroundStyle(answers[question.id] == Double(offset) ? scene.color.tint : SleepPalette.ink)
                            .accessibilityIdentifier("psqiOption\(offset)")
                    }
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(SleepPalette.rose) }
                Text("仅作科普参考，不作诊断").font(.caption).foregroundStyle(SleepPalette.muted)
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(SleepPalette.background)
            .onChange(of: index) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo("psqiQuestionTop", anchor: .top) }
            }
        }.safeAreaInset(edge: .bottom) { navigationControls }
            .navigationTitle("近一个月的睡眠").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍后再做") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成输入") { editingNumber = false } }
            }
            .onAppear { restore() }
    }
    private var navigationControls: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "arrow.left").frame(minWidth: 44, minHeight: 44) }
                .disabled(index == 0).accessibilityLabel("上一项")
            Spacer(minLength: 12)
            Button {
                if question.input == .clock { storeClock() }
                guard answers[question.id] != nil else { error = "请先填写这一项。"; return }
                if let value = answers[question.id], question.input == .minutes || question.input == .hours {
                    let limit = question.input == .hours ? 24.0 : 1440.0
                    guard value.isFinite, value >= 0, value <= limit else { error = "请输入 0 到 \(Int(limit)) 之间的数字。"; return }
                }
                if index < 17 { move(1) } else { do { try save(answers) } catch { self.error = error.localizedDescription } }
            } label: { Label(index == 17 ? "查看结果" : "下一项", systemImage: index == 17 ? "chart.bar.fill" : "arrow.right") }
                .buttonStyle(.borderedProminent).tint(scene.color.tint).foregroundStyle(SleepPalette.onAccent).accessibilityIdentifier("psqiNext")
        }.buttonBorderShape(.roundedRectangle(radius: 8)).controlSize(.large)
            .padding(.horizontal, 22).padding(.vertical, 12).background(.regularMaterial)
    }
    private func storeClock() { let c = Calendar.current.dateComponents([.hour, .minute], from: clock); answers[question.id] = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) }
    private func move(_ step: Int) { editingNumber = false; index += step; error = nil; restore() }
    private func restore() {
        number = answers[question.id].map { String($0) } ?? ""
        if question.input == .clock {
            let minutes = Int(answers[question.id] ?? (question.id == "q1" ? 23 * 60 : 7 * 60))
            clock = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
    }
}

private struct PSQIResultView: View {
    let entry: PSQIEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                    Text("自测界面测试答案 · 非真实健康结论").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                #endif
                HStack {
                    GroveProgressRings(values: [Double(entry.result.total) / 21], symbol: "moon.stars.fill")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(entry.result.total) / 21").font(.largeTitle.bold())
                        Text("PSQI 自测分数").font(.caption)
                        Text(entry.result.quality).font(.headline)
                    }
                }.groveWash(.lavender)
                Text("分数越高表示自述困扰越多，不是睡眠表现的百分制评分。原研究常以超过 5 分提示值得进一步关注，不能据此判断疾病或严重程度。")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted)
                VStack(alignment: .leading, spacing: 18) {
                    Text("七个方面，各 0–3 分").font(.headline)
                    ForEach(Array(entry.result.components.enumerated()), id: \.offset) { offset, value in
                        let color = GroveColor.allCases[offset % 5]
                        VStack(spacing: 8) {
                            HStack { Text(PSQI.componentNames[offset]); Spacer(); Text("\(value) / 3").monospacedDigit().foregroundStyle(color.tint) }.font(.subheadline)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(color.wash)
                                    Capsule().fill(color.tint).frame(width: geometry.size.width * Double(value) / 3)
                                }
                            }.frame(height: 9)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("\(PSQI.componentNames[offset])，\(value) 分，最高 3 分")
                    }
                }
                Text("你更值得照顾的方向").font(.title2.bold())
                Text(entry.result.direction).font(.headline).foregroundStyle(GroveColor.coral.tint)
                ForEach(entry.result.concerns, id: \.self) { concern in
                    VStack(alignment: .leading, spacing: 8) { Text(concern.title).font(.headline); Text(concern.suggestion).font(.subheadline) }.groveWash(.honey)
                }
                if entry.result.concerns.isEmpty { Text("继续保持规律作息；即使自测分数不高，若长期疲惫或困扰影响生活，也值得寻求专业帮助。") }
                Text("困扰方向由入睡耗时、夜间醒来频率与睡眠时长整理，不是官方失眠分型。仅作科普参考，不作诊断。").font(.caption).foregroundStyle(SleepPalette.muted)
                PSQIReference()
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).navigationTitle("这次自测").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PSQIReference: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7 个方面各 0–3 分：主观质量、入睡耗时、睡眠时长、睡眠效率、睡眠干扰、助眠药物、白天状态。睡眠效率 = 实际睡眠 ÷ 卧床时间 × 100%。本问卷按习惯钟点计算卧床时间，适用于通常的一次主睡眠。")
            Text("参考文章：匹兹堡睡眠质量指数：精神科实践与研究的新工具（The Pittsburgh Sleep Quality Index: A New Instrument for Psychiatric Practice and Research）。作者：Daniel J. Buysse、Charles F. Reynolds III、Timothy H. Monk、Susan R. Berman、David J. Kupfer，1989。")
        }.font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
    }
}

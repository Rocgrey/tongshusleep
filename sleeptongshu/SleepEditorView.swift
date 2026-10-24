import SwiftUI
import SwiftData

struct SleepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var start = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)!
    @State private var end = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
    @State private var note = ""
    @State private var error: String?
    private var valid: Bool { end > start && end.timeIntervalSince(start) <= 24 * 3600 && end <= Date() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("入睡", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("起床", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    if valid { LabeledContent("记录时长", value: SleepRecord.durationText(Int(end.timeIntervalSince(start) / 60))) }
                } header: { Text("睡眠时间") } footer: {
                    Text(valid ? "手动记录只保存你填写的睡眠时间，不推测阶段、评分或健康体征。" : "起床时间须晚于入睡时间，且两者相隔不超过 24 小时。")
                }
                Section("睡前笔记（可选）") {
                    TextField("例如：晚饭后散步，睡前没有喝咖啡", text: $note, axis: .vertical)
                        .lineLimit(3...5).accessibilityIdentifier("sleepNote")
                        .onChange(of: note) { _, value in if value.count > 2000 { note = String(value.prefix(2000)) } }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("添加睡眠").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.semibold).disabled(!valid).accessibilityIdentifier("saveSleep")
                }
            }
        }
    }

    private func save() {
        let payload = SleepPayload(id: UUID(), start: start, end: end, source: .manual, segments: [], heartSamples: [],
                                   averageHeartRate: nil, averageSpO2: nil, averageRespiratoryRate: nil, note: note)
        do {
            try payload.validate()
            context.insert(SleepRecord(payload))
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            self.error = error.localizedDescription
        }
    }
}

import SwiftUI
import SwiftData

/// Questionnaire totals remain a separate user entry; device refreshes retain them.
struct SleepAISView: View {
    let record: SleepRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    private var score: Int? { Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var valid: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || score.map { (0...24).contains($0) } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("AIS 总分（0～24，选填）", text: $value).keyboardType(.numberPad).accessibilityIdentifier("sleepAIS")
                } header: { Text("睡眠自评") } footer: {
                    Text("完成过 AIS 问卷后可填写总分；设备不会自动生成这项结果。保存到本晚记录，自动同步开启时随记录更新。留空不修改已保存的总分。")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("睡眠自评").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            var metadata = record.metadata ?? SleepMetadata(); metadata.aisScore = score ?? metadata.aisScore
                            record.metadataData = try JSONEncoder().encode(metadata)
                            try context.save(); dismiss()
                        } catch { context.rollback(); self.error = error.localizedDescription }
                    }.disabled(!valid).accessibilityIdentifier("saveSleepAIS")
                }
            }.onAppear { value = record.metadata?.aisScore.map(String.init) ?? "" }
        }
    }
}

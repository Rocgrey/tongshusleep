import SwiftUI
import SwiftData

/// A deliberate, single-record upload. Existing collection and local storage stay independent.
struct SleepUploadView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [SleepRecord]
    let recordID: UUID
    @State private var isi = ""
    @State private var ais = ""
    @State private var isLoading = false
    @State private var completed = false
    @State private var message: String?
    @State private var showsError = false
    private let receipts = SleepUploadReceipts()
    private var record: SleepRecord? { records.first { $0.id == recordID } }
    private var alreadyUploaded: Bool {
        guard let user = account.session?.user else { return false }
        return completed || receipts.contains(service: account.client.serviceID, userID: user.id, recordID: recordID)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let record, let user = account.session?.user {
                    Section("上传到此账号") {
                        Label(user.username, systemImage: "person.crop.circle")
                        Text(user.email).foregroundStyle(SleepPalette.muted)
                    }
                    Section("这晚睡眠") {
                        LabeledContent("日期", value: record.end.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("来源", value: record.source.label)
                        LabeledContent("睡眠时长", value: record.hasSleepDuration ? SleepRecord.durationText(record.asleepMinutes) : "未记录")
                        LabeledContent("参考分", value: record.score.map(String.init) ?? "未记录")
                    }
                    Section {
                        TextField("ISI 总分（0～28，选填）", text: $isi).keyboardType(.numberPad).accessibilityIdentifier("uploadISI")
                        TextField("AIS 总分（0～24，选填）", text: $ais).keyboardType(.numberPad).accessibilityIdentifier("uploadAIS")
                    } header: { Text("睡眠问卷结果") }
                    footer: { Text("只有完成过对应问卷时才填写总分；未填写的结果不会被补算。") }
                    Section {
                        Button { Task { await upload(record) } } label: {
                            HStack {
                                if isLoading { ProgressView() } else { Image(systemName: alreadyUploaded ? "checkmark.icloud" : "icloud.and.arrow.up") }
                                Text(isLoading ? "正在上传" : alreadyUploaded ? "这条记录已上传" : "上传这条记录")
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.disabled(isLoading || alreadyUploaded).accessibilityIdentifier("submitSleepUpload")
                        if let message { Text(message).font(.system(size: 13)).foregroundStyle(SleepPalette.teal).accessibilityIdentifier("uploadMessage") }
                    } footer: { Text("本次仅上传这条记录的时间、时长、已有睡眠阶段和已填写的问卷总分、笔记；本机原记录保留。") }
                } else { ContentUnavailableView("记录暂不可用", systemImage: "moon.zzz") }
            }.disabled(isLoading).scrollContentBackground(.hidden).background(SleepPalette.background)
                .navigationTitle("睡眠上报").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isLoading) } }
                .interactiveDismissDisabled(isLoading)
                .alert("上传未完成", isPresented: $showsError) { Button("知道了", role: .cancel) { } }
                    message: { Text(message ?? "请稍后重试。") }
        }
    }
    @MainActor private func upload(_ record: SleepRecord) async {
        guard !isLoading, !alreadyUploaded else { return }
        account.checkExpiry()
        guard let session = account.session else { account.open(.upload(recordID)); return }
        isLoading = true
        defer { isLoading = false }
        do {
            func score(_ value: String, maximum: Int) throws -> Int? {
                if value.isEmpty { return nil }
                guard let result = Int(value), (0...maximum).contains(result) else { throw APIError.validation("问卷总分超出范围，请检查。") }
                return result
            }
            let request = try SleepUploadRequest(record: record, isi: score(isi, maximum: 28), ais: score(ais, maximum: 24))
            let result = try await SleepUploadAPI(client: account.client).upload(request)
            guard result.id > 0, result.user_id == session.user.id else { throw APIError.invalidResponse }
            receipts.save(service: account.client.serviceID, userID: session.user.id, recordID: recordID, remoteID: result.id)
            guard account.session?.accessToken == session.accessToken else { return }
            completed = true
            message = "上传成功，可在平台查看。本机记录已保留。"
        } catch {
            if (error as? APIError)?.isUnauthorized == true { return }
            message = error.localizedDescription
            showsError = true
        }
    }
}

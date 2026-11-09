import Foundation
import CryptoKit

/// Only fields already defined by SleepRecordCreate are sent. Unknown stages stay absent.
struct SleepUploadRequest: Codable {
    let record_date: String
    let sleep_start_time: String
    let sleep_end_time: String
    let total_duration_minutes: Int?
    let sleep_score: Int?
    let deep_sleep_minutes: Int?
    let light_sleep_minutes: Int?
    let rem_minutes: Int?
    let awake_times: Int?
    let ais_score: Int?
    let notes: String?

    init(record: SleepRecord, ais: Int? = nil, timeZone: TimeZone = .current) throws {
        try record.payload.validate()
        guard record.source != .sample else { throw APIError.validation("示例记录不上传，请选择自己的睡眠记录。") }
        guard ais.map({ (0...24).contains($0) }) ?? true else {
            throw APIError.validation("AIS 总分范围为 0～24。")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = record.source == .healthKit ? record.displayTimeZone : timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        record_date = record.metadata?.healthSleep?.endDay ?? formatter.string(from: record.end)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sleep_start_time = formatter.string(from: record.source == .healthKit ? record.sleepOnset ?? record.start : record.start)
        sleep_end_time = formatter.string(from: record.source == .healthKit ? record.sleepEnd ?? record.end : record.end)
        total_duration_minutes = record.hasSleepDuration ? record.asleepMinutes : nil
        sleep_score = record.score
        let stagesComplete = record.hasStages && !record.segments.contains { [.unspecified, .unobserved, .inBed].contains($0.stage) }
        func stageMinutes(_ stage: SleepStage) -> Int? {
            guard stagesComplete, record.source != .healthKit || record.segments.contains(where: { $0.stage == stage }) else { return nil }
            return record.minutes(stage)
        }
        deep_sleep_minutes = stageMinutes(.deep)
        light_sleep_minutes = stageMinutes(.light)
        rem_minutes = stageMinutes(.rem)
        awake_times = record.awakenings
        ais_score = ais
        notes = record.note.isEmpty ? nil : record.note
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

struct SleepUploadResult: Decodable {
    let id: Int
    let user_id: Int
}

/// Account and health calls use the same client, so 401 invalidates the same login state.
@MainActor
struct SleepUploadAPI {
    let client: APIClient
    func upload(_ request: SleepUploadRequest) async throws -> SleepUploadResult {
        let data = try await client.request("health/sleep-record", method: "POST", body: request.encoded(), authenticated: true)
        return try APIJSON.decode(SleepUploadResult.self, from: data)
    }
}

/// Receipts prevent repeat taps across launches, scoped to server + account + local record.
/// The server has no idempotency key; a timeout is never automatically retried.
struct SleepUploadReceipts {
    var defaults: UserDefaults = .standard
    private func key(service: String, userID: Int, recordID: UUID) -> String {
        let scope = "\(service)|\(userID)|\(recordID)"
        return "sleepUploadV1." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func contains(service: String, userID: Int, recordID: UUID) -> Bool {
        defaults.integer(forKey: key(service: service, userID: userID, recordID: recordID)) > 0
    }
    func save(service: String, userID: Int, recordID: UUID, remoteID: Int) {
        defaults.set(remoteID, forKey: key(service: service, userID: userID, recordID: recordID))
    }
}

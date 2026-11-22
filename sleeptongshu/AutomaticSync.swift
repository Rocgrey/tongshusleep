import Foundation
import Combine
import CryptoKit

struct SyncVital: Codable {
    var id: String
    var kind: String
    var value: Double
    var recorded_at: Double
    var unit: String
    init(_ value: WearableVital) {
        id = WearableVital.deviceKey(value.id); kind = value.kind.rawValue
        self.value = value.value; recorded_at = value.date.timeIntervalSince1970; unit = value.displayUnit
    }
}
struct SyncStage: Codable {
    var stage: String
    var start: Double
    var end: Double
}
struct SyncDetails: Codable {
    var source: String
    var time_zone: String
    var start: Double? = nil
    var end: Double? = nil
    var average_heart_rate: Double? = nil
    var average_spo2: Double? = nil
    var average_respiratory_rate: Double? = nil
    var average_hrv: Double? = nil
    var average_stress: Double? = nil
    var average_systolic: Double? = nil
    var average_diastolic: Double? = nil
    var sleep_efficiency: Int? = nil
    var awake_minutes: Int? = nil
    var sleep_input_minutes: Int? = nil
    var average_basis: String? = nil
    var stages: [SyncStage] = []
}
struct DeviceSyncRequest: Codable {
    var record_key: String
    var kind: String
    var record_date: String
    var revision_at: Double = 0
    var device_id: String? = nil
    var device_name: String? = nil
    var sleep: SleepUploadRequest? = nil
    var steps: StepUploadRequest? = nil
    var vitals: [SyncVital] = []
    var details: SyncDetails
    func encoded() throws -> Data { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return try e.encode(self) }
    var fingerprint: String { WearableVital.deviceKey((try? encoded().base64EncodedString()) ?? record_key) }

    static func sleep(_ record: SleepRecord) throws -> Self {
        let night = record.metadata?.bioNight
        let observation = night != nil && !record.hasSleepDuration
        let sleepVitals = night?.samples.filter { sample in record.segments.contains { $0.stage.isAsleep && sample.date >= $0.start && sample.date < $0.end } } ?? []
        func mean(_ kind: VitalKind) -> Double? {
            if observation { return night?.mean(kind) }
            let values = sleepVitals.filter { $0.kind == kind }.map(\.value)
            return values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)
        }
        var details = SyncDetails(source: record.source.rawValue, time_zone: record.displayTimeZone.identifier,
            start: record.start.timeIntervalSince1970, end: record.end.timeIntervalSince1970,
            average_heart_rate: observation ? night?.mean(.heart) : record.averageHeartRate,
            average_spo2: observation ? night?.mean(.oxygen) : record.averageSpO2,
            average_respiratory_rate: observation ? night?.mean(.respiration) : record.averageRespiratoryRate,
            average_hrv: mean(.hrv), average_stress: mean(.stress),
            average_systolic: mean(.systolic), average_diastolic: mean(.diastolic),
            sleep_efficiency: record.efficiency, awake_minutes: record.awakeMinutes,
            sleep_input_minutes: night?.sleepInputMinutes,
            average_basis: observation ? "夜间实际采样均值，尚未识别睡眠区间" : "来源实际记录的睡眠期间均值")
        details.stages = record.segments.map { SyncStage(stage: $0.stage.rawValue, start: $0.start.timeIntervalSince1970, end: $0.end.timeIntervalSince1970) }
        var request = Self(record_key: "sleep|\(record.id.uuidString)", kind: observation ? "night_observation" : "sleep",
            record_date: night?.endDay ?? record.metadata?.healthSleep?.endDay ?? record.metadata?.encryptedBand?.endDay ?? dateLabel(record),
            device_id: night?.device, device_name: record.metadata?.externalSource ?? record.source.label, details: details)
        if !observation {
            request.sleep = try SleepUploadRequest(record: record)
            request.sleep?.extra_meta = details
        }
        request.vitals = (night?.samples ?? []).map(SyncVital.init)
        return request
    }
    private static func dateLabel(_ record: SleepRecord) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = record.displayTimeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: record.end)
    }
    static func step(_ day: DeviceStepDay) -> Self {
        Self(record_key: "steps|\(day.id)", kind: "steps", record_date: day.day, device_id: day.device, device_name: day.deviceName,
             steps: StepUploadRequest(record_date: day.day, steps: day.steps, source: "wearable", source_id: day.device,
                data_time: StepDates.format(day.readAt, time: true), timezone: day.dayBasis == "北京时间（UTC+8）" ? "Asia/Shanghai" : "device-date"),
             details: SyncDetails(source: "wearable", time_zone: day.dayBasis))
    }
    static func healthStep(_ day: LocalStepDay) -> Self {
        Self(record_key: "health-steps|\(day.date)", kind: "steps", record_date: day.date, steps: day.request,
             details: SyncDetails(source: "healthkit", time_zone: StepDates.timeZone.identifier))
    }
    static func vitalDays(_ samples: [WearableVital]) -> [Self] {
        Dictionary(grouping: samples.filter { $0.kind.isVisible && $0.kind.accepts($0.value) }) { "\($0.device)|\(StepDates.format($0.date))" }
            .compactMap { key, values in
                guard let first = values.first else { return nil }
                return Self(record_key: "vitals|\(key)", kind: "vitals", record_date: StepDates.format(first.date), device_id: first.device,
                    device_name: first.deviceLabel, vitals: values.sorted { $0.id < $1.id }.map(SyncVital.init),
                    details: SyncDetails(source: "wearable", time_zone: StepDates.timeZone.identifier))
            }
    }
}
struct DeviceSyncReceipt: Decodable { var id: Int; var user_id: Int; var applied: Bool }
struct SyncCapabilities: Decodable { var device_sync_version: Int; var idempotent: Bool }
struct SyncRemoteRecord: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var record_key: String; var revision_at: Double; var kind: String }
    var user_id: Int
    var sleep_record_id: Int?
    var payload: Payload
}
struct SyncRemotePage: Decodable, Sendable { var total: Int; var items: [SyncRemoteRecord] }
@MainActor protocol AutomaticSyncServing {
    func available(token: String) async throws -> Bool
    func inventory(start: String, end: String, userID: Int, token: String) async throws -> [SyncRemoteRecord]
    func upload(_ request: DeviceSyncRequest, token: String) async throws -> DeviceSyncReceipt
}
@MainActor struct AutomaticSyncAPI: AutomaticSyncServing {
    let client: APIClient
    func inventory(start: String, end: String, userID: Int, token: String) async throws -> [SyncRemoteRecord] {
        var rows: [SyncRemoteRecord] = [], page = 1
        while true {
            let bytes = try await client.request("health/device-records", authenticated: true, token: token,
                query: [.init(name: "start_date", value: start), .init(name: "end_date", value: end),
                        .init(name: "page", value: String(page)), .init(name: "page_size", value: "100")])
            let result = try await SyncPreparationWorker.shared.decodeInventory(bytes)
            guard result.items.allSatisfy({ $0.user_id == userID }) else { throw APIError.invalidResponse }
            rows += result.items
            if rows.count >= result.total { return rows }
            guard !result.items.isEmpty, page < 100 else { throw APIError.invalidResponse }
            page += 1
        }
    }
    func available(token: String) async throws -> Bool {
        let data = try await client.request("health/sync-capabilities", authenticated: true, token: token)
        let result = try APIJSON.decode(SyncCapabilities.self, from: data)
        return result.device_sync_version == 1 && result.idempotent
    }
    func upload(_ request: DeviceSyncRequest, token: String) async throws -> DeviceSyncReceipt {
        let body = try await SyncPreparationWorker.shared.encode(request)
        let data = try await client.request("health/device-sync", method: "POST", body: body, authenticated: true, token: token)
        return try APIJSON.decode(DeviceSyncReceipt.self, from: data)
    }
}
struct SyncStamp: Codable { var fingerprint: String; var revision: Double; var confirmed = false }

/// Persist the revision BEFORE sending. A timeout retries the identical request;
/// account/service scopes and captured tokens prevent cross-account late completions.
@MainActor final class AutomaticSyncStore: ObservableObject {
    @Published private(set) var message = "登录后自动同步已有记录"
    @Published private(set) var isBusy = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastVerifiedAt: Date?
    private var scope = ""
    private var stamps: [String: SyncStamp] = [:]
    private let directory: URL?
    private var generation = UUID()
    private var tokenIdentity = ""
    private var changedAt: Date?
    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AutomaticSync", isDirectory: true)) { self.directory = directory }
    private func bind(_ next: String, token: String = "") {
        guard next != scope || token != tokenIdentity else { return }
        tokenIdentity = token
        generation = UUID(); scope = next; isBusy = false; lastSyncedAt = nil; lastVerifiedAt = nil; changedAt = nil
        stamps = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: SyncStamp].self, from: $0) } ?? [:]
    }
    private var url: URL? { directory?.appendingPathComponent(WearableVital.deviceKey(scope) + ".json") }
    private func persist() throws {
        guard let directory, let url else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(stamps).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func reset() { bind(""); stamps = [:]; message = "登录后继续自动同步" }
    func sync(_ requests: [DeviceSyncRequest], session: AccountSession?, service: String, api: any AutomaticSyncServing, force: Bool = false, fingerprints: [String: String]? = nil) async {
        guard let session else { reset(); return }
        bind("\(service)|\(session.user.id)", token: session.accessToken)
        guard !isBusy, force || changedAt.map({ Date.now.timeIntervalSince($0) > 30 }) ?? true else { return }
        let operation = generation
        func fingerprint(_ request: DeviceSyncRequest) -> String { fingerprints?[request.record_key] ?? request.fingerprint }
        guard !requests.isEmpty else { message = "暂无需要同步的真实记录"; return }
        let verify = force || lastVerifiedAt.map { Date.now.timeIntervalSince($0) >= 900 } ?? true
        let needsUpload = requests.contains { stamps[$0.record_key]?.fingerprint != fingerprint($0) || stamps[$0.record_key]?.confirmed != true }
        guard verify || needsUpload else { return }
        isBusy = true; message = verify ? "正在核对平台中的记录" : "正在自动同步记录"
        defer {
            if operation == generation {
                isBusy = false
                // Local troubleshooting only: no token, contact details or health measurements.
                struct Status: Encodable {
                    var userID: Int; var verifiedAt: Date?; var syncedAt: Date?; var pendingDates: [String]
                }
                if let folder = directory?.appendingPathComponent("status", isDirectory: true) {
                    let pendingDates = Set(requests.filter { stamps[$0.record_key]?.confirmed != true }.map(\.record_date)).sorted()
                    let status = Status(userID: session.user.id, verifiedAt: lastVerifiedAt, syncedAt: lastSyncedAt, pendingDates: pendingDates)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    if let data = try? JSONEncoder().encode(status) {
                        try? data.write(to: folder.appendingPathComponent("latest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                }
            }
        }
        do {
            guard try await api.available(token: session.accessToken) else { throw APIError.validation("平台同步功能尚未启用，本机记录已保留。") }
            guard operation == generation, !Task.isCancelled else { return }
            if verify, let firstDay = requests.map(\.record_date).min(), let lastDay = requests.map(\.record_date).max() {
                // A local receipt is not proof that the current server still has its row.
                let remote = try await api.inventory(start: firstDay, end: lastDay, userID: session.user.id, token: session.accessToken)
                guard operation == generation, !Task.isCancelled else { return }
                let indexed = Dictionary(remote.map { ($0.payload.record_key, $0) }, uniquingKeysWith: { a, b in
                    a.payload.revision_at >= b.payload.revision_at ? a : b
                })
                for request in requests {
                    guard let stamp = stamps[request.record_key], stamp.confirmed else { continue }
                    let saved = indexed[request.record_key]
                    if saved.map({ $0.payload.revision_at < stamp.revision || (request.kind == "sleep" && $0.sleep_record_id == nil) }) ?? true {
                        stamps[request.record_key]?.confirmed = false
                    }
                }
                try persist(); lastVerifiedAt = .now
            }
            let pending = requests.filter { stamps[$0.record_key]?.fingerprint != fingerprint($0) || stamps[$0.record_key]?.confirmed != true }
                .sorted { ($0.kind == "sleep" ? 0 : 1) < ($1.kind == "sleep" ? 0 : 1) }
            message = "正在自动同步 \(pending.count) 份记录"
            var rejected = 0
            for var request in pending {
                guard operation == generation, !Task.isCancelled else { return }
                let fingerprint = fingerprint(request)
                if stamps[request.record_key]?.fingerprint != fingerprint {
                    let previous = stamps[request.record_key]?.revision ?? 0
                    stamps[request.record_key] = SyncStamp(fingerprint: fingerprint, revision: max(Date.now.timeIntervalSince1970, previous + 0.001))
                }
                try persist()
                request.revision_at = stamps[request.record_key]!.revision
                do {
                    let receipt = try await api.upload(request, token: session.accessToken)
                    guard operation == generation else { return }
                    guard receipt.id > 0, receipt.user_id == session.user.id else { throw APIError.invalidResponse }
                    stamps[request.record_key]?.confirmed = true; try persist()
                } catch APIError.business(let status, _) where [400, 409, 422].contains(status) {
                    guard operation == generation else { return }
                    rejected += 1
                }
            }
            if rejected > 0 {
                changedAt = .now
                message = "其余记录已同步，\(rejected) 份记录暂未被平台接收。本机保留，稍后重试。"
            } else {
                lastSyncedAt = .now; changedAt = nil; message = "已自动同步到当前账号"
            }
        } catch {
            guard operation == generation else { return }
            changedAt = .now
            if case APIError.business(404, _) = error { message = "平台尚未部署自动同步接口，本机记录已保留，稍后自动重试。" }
            else { message = error.localizedDescription + " 本机记录已保留，稍后自动重试。" }
        }
    }
}

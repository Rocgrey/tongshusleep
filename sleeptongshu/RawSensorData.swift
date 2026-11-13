import Foundation
import SwiftProtobuf
import Combine

enum RawCapturePolicy {
    static let types: [UInt32] = [16, 2, 1, 512]
    static let maxPacketsPerType = 256
}

/// Manufacturer realtime_data.proto uses fixed32 words. Signed presentation matches
/// Android int values; notification bytes retain the original unsigned wire encoding.
struct RawSensorPacket: Codable, Equatable {
    var sensorType: UInt32
    var sensorSeconds: UInt32
    var sensorSeq: UInt32
    var sensorDataList: [Int64]
    var receivedAt: Double?
    var notificationBase64: String?
    init(_ value: IW_RtSensorData, notification: Data, receivedAt: Date = .now) throws {
        guard value.hasType, value.hasTime, value.time.hasSeconds, value.hasSeq,
              !value.data.isEmpty, value.data.count <= 4096 else { throw SleepDataError.invalidRecord }
        sensorType = value.type; sensorSeconds = value.time.seconds; sensorSeq = value.seq
        sensorDataList = value.data.map { Int64(Int32(bitPattern: $0)) }
        self.receivedAt = receivedAt.timeIntervalSince1970
        notificationBase64 = notification.base64EncodedString()
    }
    var sensorName: String {
        switch sensorType {
        case 1: "ECG · 心电"; case 2: "PPG · 光学脉搏波"; case 8: "GYRO · 转动"
        case 16: "ACC · 加速度"; case 512: "BIOZ · 生物电阻抗"
        default: "类型 \(sensorType) · 尚未解释"
        }
    }
    var packetKey: String { "\(sensorType)|\(sensorSeconds)|\(sensorSeq)" }
}

struct RawSensorBatchRequest: Codable {
    var upload_id: String
    var capture_id: String
    var device_id: String
    var device_name: String
    var source = "ios_ble"
    var timestamp_encoding = "device_seconds_unverified"
    var packets: [RawSensorPacket]
    static func captureID(_ report: WearableProbeReport) -> String {
        WearableVital.deviceKey("\(report.deviceKey)|\(report.startedAt.timeIntervalSince1970)")
    }
    static func make(_ report: WearableProbeReport) -> [Self] {
        guard report.finishedAt != nil || report.rawSensorFinishedAt != nil,
              let packets = report.rawSensorPackets, !packets.isEmpty else { return [] }
        let capture = captureID(report)
        return stride(from: 0, to: packets.count, by: 100).map { start in
            Self(upload_id: "\(capture)|\(start / 100)", capture_id: capture, device_id: report.deviceKey,
                 device_name: report.deviceName, packets: Array(packets[start..<min(start+100, packets.count)]))
        }
    }
}
struct RawSensorReceipt: Decodable { var id: Int; var user_id: Int; var upload_id: String; var packet_count: Int; var applied: Bool }

/// History channel IDs are a different namespace from realtime sensor bit flags.
/// Keep exact device records (including quality markers), not just filtered vitals.
struct ProbeReportUpload: Codable {
    var report: WearableProbeReport
    var capture_id: String { RawSensorBatchRequest.captureID(report) }
    var report_key: String { "probe|\(capture_id)" }
    enum CodingKeys: String, CodingKey { case capture_id, report_key }
    init(report: WearableProbeReport) { self.report = report }
    init(from decoder: any Swift.Decoder) throws { report = try WearableProbeReport(from: decoder) }
    func encode(to encoder: any Swift.Encoder) throws {
        try report.encode(to: encoder)
        var keys = encoder.container(keyedBy: CodingKeys.self)
        try keys.encode(capture_id, forKey: .capture_id)
        try keys.encode(report_key, forKey: .report_key)
    }
}
struct ProbeReportReceipt: Decodable {
    var id: Int; var user_id: Int; var upload_id: String; var report_key: String
    var record_count: Int; var channel_count: Int; var applied: Bool
}

enum RawSensorPendingStorage {
    static var directory: URL { WearableProbeStorage.directory.appendingPathComponent("raw-pending", isDirectory: true) }
    static func save(_ report: WearableProbeReport) throws {
        let batches = RawSensorBatchRequest.make(report)
        guard !batches.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for batch in batches {
            let file = directory.appendingPathComponent(WearableVital.deviceKey(batch.upload_id) + ".json")
            // Captures are immutable; preserve the first batch and receipt digest across restarts.
            if !FileManager.default.fileExists(atPath: file.path) {
                try JSONEncoder().encode(batch).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
    }
    static var historyDirectory: URL { WearableProbeStorage.directory.appendingPathComponent("probe-pending", isDirectory: true) }
    static func saveHistory(_ report: WearableProbeReport) throws {
        guard report.finishedAt != nil,
              WearableHistoryDecoder.isBIO(model: report.observedModel, firmware: report.observedFirmware) else { return }
        let batch = ProbeReportUpload(report: report)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let file = historyDirectory.appendingPathComponent(WearableVital.deviceKey(batch.report_key) + ".json")
        if !FileManager.default.fileExists(atPath: file.path) {
            try JSONEncoder().encode(batch).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }
    static func loadHistory() throws -> [ProbeReportUpload] {
        guard FileManager.default.fileExists(atPath: historyDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
                try JSONDecoder().decode(ProbeReportUpload.self, from: Data(contentsOf: $0))
            }
    }
    /// First authenticated uploader owns a locally collected capture. Subsequent
    /// account switches cannot silently send those same files to another account.
    static func claim(capture: String, scope: String, base: URL = WearableProbeStorage.directory) throws -> Bool {
        let directory = base.appendingPathComponent("raw-owners", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(WearableVital.deviceKey(capture) + ".json")
        if FileManager.default.fileExists(atPath: file.path) { return try JSONDecoder().decode(String.self, from: Data(contentsOf: file)) == scope }
        try JSONEncoder().encode(scope).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        return true
    }
    static func load() throws -> [RawSensorBatchRequest] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
                try JSONDecoder().decode(RawSensorBatchRequest.self, from: Data(contentsOf: $0))
            }
    }
}

/// Small cached metadata lets retries skip acknowledged files without decoding their
/// potentially multi-megabyte contents again. Payloads are loaded only when sent.
struct RawPendingUpload {
    var file: URL
    var capture: String
    var uploadID: String
    var history: Bool
    var count: Int
    var channels: Int
    func receiptKey(owner: String) -> String {
        "rawSensorReceiptV1." + WearableVital.deviceKey("\(owner)|\(uploadID)")
    }
}

extension WearableProbeWorker {
    func prepareUploads(_ report: WearableProbeReport?, bootstrap: Bool) throws {
        if bootstrap {
            let files = (try? FileManager.default.contentsOfDirectory(at: WearableProbeStorage.directory, includingPropertiesForKeys: nil)) ?? []
            for file in files.filter({ $0.lastPathComponent.hasPrefix("probe-") && $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                let previous = try JSONDecoder().decode(WearableProbeReport.self, from: Data(contentsOf: file))
                if previous.finishedAt != nil, WearableHistoryDecoder.isBIO(model: previous.observedModel, firmware: previous.observedFirmware) {
                    try RawSensorPendingStorage.save(previous); try RawSensorPendingStorage.saveHistory(previous); break
                }
            }
        }
        if let report {
            try RawSensorPendingStorage.save(report); try RawSensorPendingStorage.saveHistory(report)
        }
    }

    func pendingUploads(owner: String, defaults: UserDefaults, base: URL = WearableProbeStorage.directory) throws -> (uploads: [RawPendingUpload], otherAccount: Bool) {
        var uploads: [RawPendingUpload] = []
        var otherAccount = false
        for (name, history) in [("raw-pending", false), ("probe-pending", true)] {
            let folder = base.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let item: RawPendingUpload
                if let cached = pendingMetadata[file] { item = cached }
                else {
                    let data = try Data(contentsOf: file)
                    if history {
                        let batch = try JSONDecoder().decode(ProbeReportUpload.self, from: data)
                        item = RawPendingUpload(file: file, capture: batch.capture_id, uploadID: batch.report_key,
                                                history: true, count: batch.report.records.count, channels: batch.report.channels.count)
                    } else {
                        let batch = try JSONDecoder().decode(RawSensorBatchRequest.self, from: data)
                        item = RawPendingUpload(file: file, capture: batch.capture_id, uploadID: batch.upload_id,
                                                history: false, count: batch.packets.count, channels: 0)
                    }
                    pendingMetadata[file] = item
                }
                guard try RawSensorPendingStorage.claim(capture: item.capture, scope: owner, base: base) else {
                    otherAccount = true; continue
                }
                if !defaults.bool(forKey: item.receiptKey(owner: owner)) { uploads.append(item) }
            }
        }
        return (uploads, otherAccount)
    }

    func uploadBody(_ item: RawPendingUpload) throws -> Data {
        let data = try Data(contentsOf: item.file)
        if item.history {
            return try JSONEncoder().encode(JSONDecoder().decode(ProbeReportUpload.self, from: data))
        }
        return try JSONEncoder().encode(JSONDecoder().decode(RawSensorBatchRequest.self, from: data))
    }

    func saveReceipt(_ data: Data, key: String) throws {
        let directory = WearableProbeStorage.directory.appendingPathComponent("raw-receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(WearableVital.deviceKey(key) + ".json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func saveSyncStatus(_ message: String, userID: Int) {
        let value: [String: Any] = ["status": message, "user_id": userID, "updated_at": Date.now.timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            try? data.write(to: WearableProbeStorage.directory.appendingPathComponent("raw-sync-status.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }
}

/// Retryable batches are immutable after capture. Receipts are scoped by service/user.
@MainActor final class RawSensorSyncStore: ObservableObject {
    @Published private(set) var message = "连接后自动采集；登录并开启自动同步后上传"
    private let defaults: UserDefaults
    private var importedPreviousReport = false
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func sync(_ report: WearableProbeReport?, account: AccountStore) async {
        guard let session = account.session else { reset(); return }
        do {
            await Task.yield()
            try Task.checkCancellation()
            try await WearableProbeWorker.shared.prepareUploads(report, bootstrap: !importedPreviousReport)
            importedPreviousReport = true
            let owner = "\(account.client.serviceID)|\(session.user.id)"
            let pending = try await WearableProbeWorker.shared.pendingUploads(owner: owner, defaults: defaults)
            guard account.session?.accessToken == session.accessToken else { return }
            // Nothing changed: leave the existing UI status alone on the 15s retry.
            guard !pending.uploads.isEmpty else { return }
            for item in pending.uploads {
                try Task.checkCancellation()
                let body = try await WearableProbeWorker.shared.uploadBody(item)
                try Task.checkCancellation()
                guard account.session?.accessToken == session.accessToken else { return }
                setMessage(item.history ? "正在同步历史原文（睡眠输入、心跳间隔等）" : "正在同步原始信号批次")
                let data = try await account.client.request(item.history ? "health/probe-reports" : "health/raw-sensor-batches", method: "POST",
                    body: body, authenticated: true, token: session.accessToken, requestTimeout: item.history ? 60 : 30)
                guard account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                if item.history {
                    let receipt = try APIJSON.decode(ProbeReportReceipt.self, from: data)
                    guard receipt.user_id == session.user.id, receipt.upload_id == item.uploadID,
                          receipt.report_key == item.uploadID, receipt.record_count == item.count,
                          receipt.channel_count == item.channels, receipt.id > 0 else { throw APIError.invalidResponse }
                } else {
                    let receipt = try APIJSON.decode(RawSensorReceipt.self, from: data)
                    guard receipt.user_id == session.user.id, receipt.upload_id == item.uploadID,
                          receipt.packet_count == item.count, receipt.id > 0 else { throw APIError.invalidResponse }
                }
                let key = item.receiptKey(owner: owner)
                try await WearableProbeWorker.shared.saveReceipt(data, key: key)
                defaults.set(true, forKey: key)
            }
            guard account.session?.accessToken == session.accessToken else { return }
            setMessage("原始信号与历史原文同步完成；尚未换算睡眠阶段" + (pending.otherAccount ? "；其他账号的采集已隔离" : ""))
        } catch is CancellationError { return }
        catch {
            guard account.session?.accessToken == session.accessToken else { return }
            setMessage(error.localizedDescription + " 原始信号保存在本机，稍后重试。")
        }
        if account.session?.accessToken == session.accessToken {
            await WearableProbeWorker.shared.saveSyncStatus(message, userID: session.user.id)
        }
    }
    private func setMessage(_ value: String) { if message != value { message = value } }
    func reset() { setMessage("登录后按自动同步设置处理原始信号") }
}

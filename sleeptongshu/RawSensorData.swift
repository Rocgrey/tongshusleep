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

/// Retryable batches are immutable after capture. Receipts are scoped by service/user.
@MainActor final class RawSensorSyncStore: ObservableObject {
    @Published private(set) var message = "连接后自动采集；登录并开启自动同步后上传"
    private let defaults: UserDefaults
    private var importedPreviousReport = false
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func sync(_ report: WearableProbeReport?, account: AccountStore) async {
        guard let session = account.session else { reset(); return }
        defer {
            if account.session?.accessToken == session.accessToken {
                // A small local diagnostic contains status only, never credentials.
                let value: [String: Any] = ["status": message, "user_id": session.user.id, "updated_at": Date.now.timeIntervalSince1970]
                if let data = try? JSONSerialization.data(withJSONObject: value) {
                    try? data.write(to: WearableProbeStorage.directory.appendingPathComponent("raw-sync-status.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
                }
            }
        }
        do {
            if !importedPreviousReport {
                // Upgrade: queue the latest completed BIO report, even if a newer
                // incomplete attempt is currently displayed. Never regenerate its IDs.
                let files = (try? FileManager.default.contentsOfDirectory(at: WearableProbeStorage.directory, includingPropertiesForKeys: nil)) ?? []
                for file in files.filter({ $0.lastPathComponent.hasPrefix("probe-") && $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    let previous = try JSONDecoder().decode(WearableProbeReport.self, from: Data(contentsOf: file))
                    if previous.finishedAt != nil, WearableHistoryDecoder.isBIO(model: previous.observedModel, firmware: previous.observedFirmware) {
                        try RawSensorPendingStorage.save(previous); try RawSensorPendingStorage.saveHistory(previous); break
                    }
                }
                importedPreviousReport = true
            }
            if let report { try RawSensorPendingStorage.save(report); try RawSensorPendingStorage.saveHistory(report) }
            let batches = try RawSensorPendingStorage.load()
            let history = try RawSensorPendingStorage.loadHistory()
            guard !batches.isEmpty || !history.isEmpty else { return }
            let owner = "\(account.client.serviceID)|\(session.user.id)"
            var belongingToCurrent = false
            var otherAccount = false
            for batch in batches {
                try Task.checkCancellation()
                guard try RawSensorPendingStorage.claim(capture: batch.capture_id, scope: owner) else { otherAccount = true; continue }
                belongingToCurrent = true
                let scope = WearableVital.deviceKey("\(account.client.serviceID)|\(session.user.id)|\(batch.upload_id)")
                let receiptKey = "rawSensorReceiptV1.\(scope)"
                if defaults.bool(forKey: receiptKey) { continue }
                message = "正在同步原始信号批次"
                let data = try await account.client.request("health/raw-sensor-batches", method: "POST",
                    body: JSONEncoder().encode(batch), authenticated: true, token: session.accessToken)
                guard account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                let receipt = try APIJSON.decode(RawSensorReceipt.self, from: data)
                guard receipt.user_id == session.user.id, receipt.upload_id == batch.upload_id,
                      receipt.packet_count == batch.packets.count, receipt.id > 0 else { throw APIError.invalidResponse }
                try saveReceipt(data, key: receiptKey)
                defaults.set(true, forKey: receiptKey)
            }
            for batch in history {
                try Task.checkCancellation()
                guard try RawSensorPendingStorage.claim(capture: batch.capture_id, scope: owner) else { otherAccount = true; continue }
                belongingToCurrent = true
                let key = "rawSensorReceiptV1." + WearableVital.deviceKey("\(owner)|\(batch.report_key)")
                if defaults.bool(forKey: key) { continue }
                message = "正在同步历史原文（睡眠输入、心跳间隔等）"
                let data = try await account.client.request("health/probe-reports", method: "POST",
                    body: JSONEncoder().encode(batch), authenticated: true, token: session.accessToken, requestTimeout: 60)
                guard account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                let receipt = try APIJSON.decode(ProbeReportReceipt.self, from: data)
                guard receipt.user_id == session.user.id, receipt.upload_id == batch.report_key,
                      receipt.report_key == batch.report_key, receipt.record_count == batch.report.records.count,
                      receipt.channel_count == batch.report.channels.count, receipt.id > 0 else { throw APIError.invalidResponse }
                try saveReceipt(data, key: key)
                defaults.set(true, forKey: key)
            }
            guard account.session?.accessToken == session.accessToken else { return }
            message = belongingToCurrent ? "原始信号与历史原文同步完成；尚未换算睡眠阶段" : "没有待传到当前账号的原始记录"
            if otherAccount { message += "；其他账号的采集已隔离" }
        } catch is CancellationError { return }
        catch {
            guard account.session?.accessToken == session.accessToken else { return }
            message = error.localizedDescription + " 原始信号保存在本机，稍后重试。"
        }
    }
    private func saveReceipt(_ data: Data, key: String) throws {
        let directory = WearableProbeStorage.directory.appendingPathComponent("raw-receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(WearableVital.deviceKey(key) + ".json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    func reset() { message = "登录后按自动同步设置处理原始信号" }
}

import Foundation
import SwiftProtobuf
import Combine

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
    static func make(_ report: WearableProbeReport) -> [Self] {
        guard report.finishedAt != nil, let packets = report.rawSensorPackets, !packets.isEmpty else { return [] }
        let capture = WearableVital.deviceKey("\(report.deviceKey)|\(report.startedAt.timeIntervalSince1970)")
        return stride(from: 0, to: packets.count, by: 100).map { start in
            Self(upload_id: "\(capture)|\(start / 100)", capture_id: capture, device_id: report.deviceKey,
                 device_name: report.deviceName, packets: Array(packets[start..<min(start+100, packets.count)]))
        }
    }
}
struct RawSensorReceipt: Decodable { var id: Int; var user_id: Int; var upload_id: String; var packet_count: Int; var applied: Bool }

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
    @Published private(set) var message = "原始信号默认不采集；可开启下一次连接的短时验证"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func sync(_ report: WearableProbeReport?, account: AccountStore) async {
        guard let session = account.session else { reset(); return }
        do {
            if let report { try RawSensorPendingStorage.save(report) }
            let batches = try RawSensorPendingStorage.load()
            guard !batches.isEmpty else { return }
            for batch in batches {
                try Task.checkCancellation()
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
                defaults.set(true, forKey: receiptKey)
            }
            guard account.session?.accessToken == session.accessToken else { return }
            message = "原始信号已同步到当前账号；尚未换算睡眠阶段"
        } catch is CancellationError { return }
        catch {
            guard account.session?.accessToken == session.accessToken else { return }
            message = error.localizedDescription + " 原始信号保存在本机，稍后重试。"
        }
    }
    func reset() { message = "登录后按自动同步设置处理原始信号" }
}

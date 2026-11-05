import Foundation

struct WearableProbeChannel: Codable, Identifiable {
    var type: Int
    var name: String
    var state = "尚未查询"
    var available: UInt64 = 0
    var received = 0
    var requestedStart: UInt32? = nil
    var requestedEnd: UInt32? = nil
    var id: Int { type }
}

struct WearableProbeRecord: Codable, Identifiable {
    var type: Int
    var sequence: UInt32
    var receivedAt: Date
    var protobufJSON: String
    var protobufBase64: String? = nil
    var heartRate: Double?
    var oxygen: Double?
    var steps: UInt32?
    var id: String { "\(type)-\(sequence)" }
}

struct WearableProbeReport: Codable {
    var schemaVersion = 1
    var startedAt = Date.now
    var finishedAt: Date?
    var deviceName: String
    var deviceKey: String
    var userReportedFirmware: String?
    var observedModel: String?
    var observedFirmware: String?
    var observedAlgorithm: String?
    var batteryLevel0To9: UInt32?
    var currentSteps: UInt32?
    var services: [String] = []
    var characteristics: [String: [String]] = [:]
    var channels: [WearableProbeChannel] = [
        .init(type: 0, name: "健康与睡眠输入"), .init(type: 2, name: "心电"),
        .init(type: 3, name: "光学脉搏波"), .init(type: 4, name: "心跳间隔"),
        .init(type: 6, name: "血氧"), .init(type: 8, name: "温度"),
        .init(type: 16, name: "转动信号"), .init(type: 17, name: "三轴加速度")
    ]
    var records: [WearableProbeRecord] = []
    var events: [String] = []
    var rejectedFrames = 0
    var note = "本报告是有数量和时长限制的接入验证，不是完整历史备份。心跳间隔最多请求最近一个目录块的 288 包，健康记录最多 120 包，其他通道各 8 包；总计最多 512 包、2 MB。目录范围不保证覆盖整夜，未返回不代表硬件不支持。睡眠输入不是睡眠阶段；波形的单位、采样率及设备时间仍需核对，不生成自研分期或计步结果。报告仅保存在本机。"
}

enum WearableProbeStorage {
    static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wearable-validation", isDirectory: true) }
    static func save(_ report: WearableProbeReport) throws -> URL {
        let directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("probe-\(Int(report.startedAt.timeIntervalSince1970 * 1000))-\(report.deviceKey.prefix(8)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }
    static func latest() -> (WearableProbeReport, URL)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url), let report = try? JSONDecoder().decode(WearableProbeReport.self, from: data) { return (report, url) }
        }
        return nil
    }
}

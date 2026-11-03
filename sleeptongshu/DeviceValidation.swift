import Foundation
import CoreFoundation
import Combine

struct ValidationField: Codable, Identifiable {
    var path: String
    var occurrences = 0
    var values = 0
    var minimum: Double?
    var maximum: Double?
    var examples: [String] = []
    var id: String { path }

    var meaning: String {
        let key = path.components(separatedBy: ".").last ?? path
        switch key {
        case "heartValue", "heart": return "心率结果；不是连续脉搏波。"
        case "OxygenValue", "oxygen": return "血氧结果；不是原始光学信号。"
        case "hrvValue", "hrv": return "设备的 HRV 结果；单位及计算方式尚未确认。"
        case "systolic", "diastolic": return "设备估计的血压结果。"
        case "stress": return "设备压力值，计算方式尚未确认。"
        case "RespirationRate", "respiration": return "设备返回的呼吸率字段；零值或占位值不代表有效测量。"
        case "ecgs", "ppgs": return "历史数组；字段名不能证明是原始心电或脉搏波，采样率和单位待确认。"
        case "points", "line", "SLE_LINE", "type": return "设备已经计算的睡眠阶段，不是用于重新分期的传感器信号。"
        case "time", "Time", "start", "end", "sleepTime", "wakeTime": return "设备记录的时间。"
        default: return "已记录字段的类型或数值范围，具体含义待确认。"
        }
    }
}

enum ValidationInventory {
    // Retired estimates and device credentials stay outside diagnostic exports too.
    static func excludes(_ key: String) -> Bool {
        let lower = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return ["glucose", "bloodsugar", "cholesterol", "triglycer", "uric", "hdl", "ldl", "lipid",
                "password", "token", "secret", "address", "mac", "deviceid", "uuid", "血糖", "血脂", "尿酸"]
            .contains { lower.contains($0) }
    }

    static func collect(_ snapshots: [[String: Any]]) -> [ValidationField] {
        var output: [String: ValidationField] = [:]
        func visit(_ value: Any, path: String, depth: Int) {
            guard depth <= 6, output.count < 500 || output[path] != nil else { return }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() where !excludes(key) {
                    visit(dictionary[key]!, path: path.isEmpty ? key : "\(path).\(key)", depth: depth + 1)
                }
                return
            }
            var field = output[path] ?? ValidationField(path: path)
            field.occurrences += 1
            if let array = value as? [Any] {
                field.values += array.count
                for item in array.prefix(2048) {
                    if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
                        let number = number.doubleValue
                        field.minimum = min(field.minimum ?? number, number)
                        field.maximum = max(field.maximum ?? number, number)
                        if field.examples.count < 8 { field.examples.append(String(number)) }
                    }
                }
                if field.examples.isEmpty { field.examples = ["数组，共 \(array.count) 项；范围最多检查前 2048 项"] }
            } else if let number = value as? NSNumber {
                field.values += 1
                if CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
                    field.minimum = min(field.minimum ?? number.doubleValue, number.doubleValue)
                    field.maximum = max(field.maximum ?? number.doubleValue, number.doubleValue)
                }
                if field.examples.count < 4 { field.examples.append(number.stringValue) }
            } else if let string = value as? String {
                field.values += 1
                if field.examples.count < 4 { field.examples.append(String(string.prefix(100))) }
            } else if let data = value as? Data {
                field.values += data.count
                if field.examples.isEmpty { field.examples = ["二进制，\(data.count) 字节"] }
            }
            output[path] = field
        }
        for snapshot in snapshots.prefix(5000) { visit(snapshot, path: "", depth: 0) }
        return output.values.sorted { $0.path < $1.path }
    }
}

struct ValidationSignalBlock: Codable, Identifiable {
    var kind: String
    var date: String
    var time: String
    var number: Int
    var raw: Data
    var converted: Data
    var receivedAt: Date
    var id: String { "\(kind)|\(date)|\(time)|\(number)" }
    var littleEndianValues: [Int] {
        let bytes = [UInt8](converted)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: bytes.count, by: 2).map { Int(bytes[$0]) | (Int(bytes[$0 + 1]) << 8) }
    }
}

struct DeviceValidationReport: Codable, Identifiable {
    var version = 1
    var id = UUID()
    var startedAt = Date()
    var finishedAt: Date?
    var deviceKey: String
    var firmware = "尚未返回"
    var status = "正在连接设备"
    var transportStatus = "历史同步尚未完成"
    var rrStatus = "尚未请求"
    var waveStatus = "尚未观察"
    var motionStatus = "未请求：现有体动接口限定特定项目，尚未确认此设备适用"
    var events: [String] = []
    var fields: [ValidationField] = []
    var blocks: [ValidationSignalBlock] = []
    var wavePreview: [Double] = []
    var waveSampleCount = 0
    var sleepRecords: [SleepPayload] = []
    var vitals: [WearableVital] = []
    var rejectedSleeps = 0
    var captureLimitReached = false
    var inventoryTruncated = false
    var origin = "真实设备验证"
    var bluetoothServices: [String: [String]] = [:]
    var capabilityCodes: [String: Int] = [:]

    var conclusion: String {
        if blocks.contains(where: { !$0.converted.isEmpty || !$0.raw.isEmpty }) || waveSampleCount > 0 {
            return "已收到候选信号。仍需确认单位、采样率和整夜连续性，暂不能据此重新计算深睡、浅睡或快速眼动。"
        }
        return "本次尚未取得可用于自主睡眠分期的原始信号。没有回包不等于设备不支持，也可能尚未生成记录或接口不适配。"
    }

    var summary: String {
        """
        sleeptongshu · 设备数据验证
        来源：\(origin)
        状态：\(status)
        开始：\(startedAt.formatted(date: .numeric, time: .standard))
        固件：\(firmware)
        历史传输：\(transportStatus)
        逐次心跳：\(rrStatus)
        脉搏波：\(waveStatus)；收到 \(waveSampleCount) 点
        体动：\(motionStatus)
        有效睡眠：\(sleepRecords.count) 段；有效体征：\(vitals.count) 条
        历史字段：\(fields.count) 类；候选信号：\(blocks.count) 块
        \(conclusion)

        历史字段来自同步后读取的 SDK 本地历史库，可能包含此前缓存；不是逐包蓝牙抓包。字段范围包含占位值，不等于有效体征。
        心跳间隔转换值只按 SDK 的双字节小端格式展开，单位及缩放尚未确认，不标为毫秒。脉搏波回调名称也不能证明此型号的实际采样率。
        字段样例和波形预览有限；信号探测有时间、块数及大小上限，不代表整晚完整记录。
        \(captureLimitReached ? "信号达到采集上限，报告为部分数据。" : "")
        \(inventoryTruncated ? "历史字段快照达到上限，仅分析部分窗口。" : "")

        \(events.joined(separator: "\n"))
        """
    }
}

@MainActor
final class DeviceValidationStore: ObservableObject {
    @Published private(set) var report: DeviceValidationReport?
    @Published private(set) var storageError: String?
    private let directory: URL?
    private var lastSaved = Date.distantPast
    private var lastCheckpoint = Date.distantPast
    private var encodedBytes = 0
    private var blockIDs: Set<String> = []
    var exportURL: URL? { directory?.appendingPathComponent("device-validation.json") }

    init(directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Diagnostics", isDirectory: true)) {
        self.directory = directory
        if let url = exportURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 6_000_000 else { throw SleepDataError.tooLarge }
                report = try JSONDecoder().decode(DeviceValidationReport.self, from: data)
                if report?.finishedAt == nil {
                    report?.status = "上次验证中断，已保留收到的数据"
                    report?.finishedAt = .now
                }
            } catch { storageError = "上次验证报告无法打开，原文件已保留。" }
        }
    }

    func begin(device: UUID, services: [String: [String]] = [:]) {
        report = DeviceValidationReport(deviceKey: WearableVital.deviceKey(device.uuidString))
        report?.bluetoothServices = services
        encodedBytes = 0; blockIDs = []; lastCheckpoint = .distantPast
        save(force: true)
    }

    func receive(_ snapshot: [String: Any]) {
        guard report != nil, report?.finishedAt == nil else { return }
        switch snapshot["kind"] as? String {
        case "identity":
            report?.firmware = snapshot["firmware"] as? String ?? "尚未返回"
            report?.capabilityCodes = snapshot["capabilities"] as? [String: Int] ?? [:]
        case "state":
            if snapshot["limit"] as? Bool == true { report?.captureLimitReached = true }
            if let state = snapshot["rr"] as? String { report?.rrStatus = state }
            if let state = snapshot["transport"] as? String { report?.transportStatus = state }
            if let state = snapshot["wave"] as? String { report?.waveStatus = state }
        case "rr":
            let block = ValidationSignalBlock(kind: "rr", date: snapshot["date"] as? String ?? "", time: snapshot["time"] as? String ?? "",
                number: (snapshot["number"] as? NSNumber)?.intValue ?? 0,
                raw: snapshot["raw"] as? Data ?? Data(), converted: snapshot["converted"] as? Data ?? Data(), receivedAt: .now)
            let bytes = block.raw.count + block.converted.count
            guard bytes > 0, !blockIDs.contains(block.id) else { return }
            guard (report?.blocks.count ?? 0) < 180, bytes <= 32768, encodedBytes + bytes <= 500_000 else {
                report?.captureLimitReached = true; save(force: false); return
            }
            encodedBytes += bytes; blockIDs.insert(block.id)
            report?.blocks.append(block)
        case "wave":
            let values = (snapshot["values"] as? [NSNumber] ?? []).prefix(2048).map(\.doubleValue).filter { $0.isFinite }
            guard !values.isEmpty else { return }
            report?.waveSampleCount += values.count
            let room = max(0, 600 - (report?.wavePreview.count ?? 0))
            report?.wavePreview.append(contentsOf: values.prefix(room))
            report?.waveStatus = "已收到主动回调；单位、采样率及信号质量待确认"
        case "inventory":
            report?.fields = ValidationInventory.collect(snapshot["windows"] as? [[String: Any]] ?? [])
            report?.inventoryTruncated = snapshot["truncated"] as? Bool ?? false
        default: break
        }
        save(force: false)
    }

    func checkpoint() {
        guard report != nil, Date.now.timeIntervalSince(lastCheckpoint) >= 3 else { return }
        lastCheckpoint = .now
        save(force: true)
    }

    func note(_ event: String) {
        guard report != nil else { return }
        report?.status = event
        report?.events.append("\(Date.now.formatted(date: .omitted, time: .standard)) \(event)")
        if (report?.events.count ?? 0) > 80 { report?.events.removeFirst() }
        save(force: false)
    }

    func finish(download: VeepooDecodedSleep?, status: String) {
        guard report != nil else { return }
        if let download {
            report?.sleepRecords = Array(download.records.prefix(30))
            report?.vitals = Array(download.vitals.prefix(3000))
            if download.records.count > 30 || download.vitals.count > 3000 { report?.captureLimitReached = true }
            report?.rejectedSleeps = download.rejected
        }
        report?.status = status
        report?.finishedAt = .now
        save(force: true)
    }

    @discardableResult
    func save(force: Bool) -> Bool {
        guard let report, let directory, let exportURL else { return false }
        guard force || Date.now.timeIntervalSince(lastSaved) >= 2 else { return true }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            guard data.count <= 6_000_000 else { throw SleepDataError.tooLarge }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: exportURL, options: [.atomic, .completeFileProtection])
            lastSaved = .now; storageError = nil
            return true
        } catch { storageError = "验证报告未能保存：\(error.localizedDescription)"; return false }
    }

    #if DEBUG
    func loadPreview(withSignals: Bool = false) {
        report = DeviceValidationReport(deviceKey: "ui-fixture", status: "示例报告 · 非真实测量", rrStatus: "等待回包超时，尚不能确定是否支持",
            waveStatus: "未观察到主动回调", origin: "界面测试示例")
        report?.fields = ValidationInventory.collect([["history": ["heartValue": 64, "ppgs": [63, 64, 65], "OxygenValue": 98]]])
        report?.finishedAt = .now
        if withSignals {
            report?.blocks = [ValidationSignalBlock(kind: "rr", date: "2026-01-01", time: "00:00:00", number: 1,
                raw: Data([1, 2]), converted: Data([0x20, 3, 0x40, 3, 0x10, 3, 0x50, 3]), receivedAt: .now)]
            report?.rrStatus = "界面测试候选信号，不代表设备支持"
        }
    }
    #endif
}

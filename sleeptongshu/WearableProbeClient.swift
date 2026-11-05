import Foundation
import CoreBluetooth
import Combine
import SwiftProtobuf

enum WearableProbeProtocol {
    static func infoRequest() throws -> WearableFrame {
        var request = IW_DeviceInfoRequest()
        request.reserved = 123
        request.operation = .read
        return WearableFrame(opcode: 0, payload: try request.serializedData())
    }
    static func realtimeRequest(battery: Bool) throws -> WearableFrame {
        var request = IW_RtSubscriber()
        if battery { request.battery = .onlyOnce } else { request.health = .onlyOnce }
        return WearableFrame(opcode: 0x70, payload: try request.serializedData())
    }
    static func historyRequest(type: Int, range: ClosedRange<UInt32>? = nil, stop: Bool = false) throws -> WearableFrame {
        guard let type = IW_HisDataType(rawValue: type) else { throw VeepooImportError.malformed }
        var request = IW_HisSubscriber()
        if stop {
            request.operation = .stopSync
            var value = IW_HisStopSync(); value.type = type
            request.stopSync = value
        } else if let range {
            request.operation = .startSync
            var block = IW_HisBlock(); block.startSeq = range.lowerBound; block.endSeq = range.upperBound
            var value = IW_HisStartSync(); value.type = type; value.block = [block]
            request.startSync = value
        } else {
            request.operation = .itSync
            var value = IW_HisITSync(); value.type = type
            request.itSync = value
        }
        return WearableFrame(opcode: 0x80, payload: try request.serializedData())
    }
    static func sampleRange(_ indexes: [IW_HisIndex], limit: UInt32) -> ClosedRange<UInt32>? {
        guard limit > 0, let index = indexes.filter({ $0.startSeq <= $0.endSeq }).max(by: { $0.endSeq < $1.endSeq }) else { return nil }
        let offset = min(index.endSeq - index.startSeq, limit - 1)
        return (index.endSeq - offset)...index.endSeq
    }

    static func record(_ value: IW_HisData, type: Int, receivedAt: Date = .now) throws -> WearableProbeRecord {
        var record = WearableProbeRecord(type: type, sequence: value.seq, receivedAt: receivedAt, protobufJSON: try value.jsonString())
        record.protobufBase64 = try value.serializedData().base64EncodedString()
        if case .health(let health) = value.data {
            if health.hasHrData, VitalKind.heart.accepts(Double(health.hrData.avgBpm)) { record.heartRate = Double(health.hrData.avgBpm) }
            if health.hasBxoyData, VitalKind.oxygen.accepts(Double(health.bxoyData.agvOxy)) { record.oxygen = Double(health.bxoyData.agvOxy) }
            if health.hasPedoData { record.steps = health.pedoData.step }
        }
        return record
    }
}

@MainActor
final class WearableProbeClient: ObservableObject {
    @Published private(set) var report: WearableProbeReport?
    @Published private(set) var reportURL: URL?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "等待连接设备"
    @Published private(set) var battery: DeviceBatteryReading?
    var onRealtimeVitals: (([(VitalKind, Double)]) -> Void)?
    private var task: Task<Void, Never>?
    private var decoder = WearableFrameDecoder()
    private weak var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var awaitingWrite = false
    private var writeError: String?
    private var answers: Set<String> = []
    private var indexes: [Int: [IW_HisIndex]] = [:]
    private var received: [Int: Set<UInt32>] = [:]
    private var failedTypes: Set<Int> = []
    private var activeType: Int?
    private var activeRange: ClosedRange<UInt32>?
    private var storedBytes = 0
    private var generation = UUID()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-probe") {
                var fixture = WearableProbeReport(deviceName: "BPH6-6886 · 界面测试示例", deviceKey: "ui-fixture",
                                                   userReportedFirmware: "78.1.0.41 · 算法 1.11.2")
                fixture.finishedAt = .now
                fixture.currentSteps = 4312
                fixture.observedFirmware = "78.1.0.41"
                fixture.channels[0].received = 3; fixture.channels[0].state = "本段读取完成"
                fixture.channels[3].state = "查询未响应，尚不能确认支持情况"
                fixture.records = [62.0, 65, 63].enumerated().map {
                    WearableProbeRecord(type: 0, sequence: UInt32($0.offset), receivedAt: .now, protobufJSON: "{}", heartRate: $0.element)
                }
                fixture.note = "这些是界面测试示例，不是实际设备读取结果。"
                report = fixture; battery = DeviceBatteryReading(gridLevel: 7, maximum: 9)
                status = "界面测试示例 · 非真实设备数据"
            }
            return
        }
        #endif
        if let (report, url) = WearableProbeStorage.latest() { self.report = report; reportURL = url }
    }

    func prepare(name: String, id: UUID, services: [String], characteristics: [String: [String]]) {
        cancel()
        generation = UUID()
        decoder = WearableFrameDecoder(); answers = []; indexes = [:]; received = [:]; failedTypes = []
        activeType = nil; activeRange = nil; storedBytes = 0; battery = nil; reportURL = nil
        report = WearableProbeReport(deviceName: name, deviceKey: WearableVital.deviceKey(id.uuidString),
                                     userReportedFirmware: WearableGatt.reportedFirmware(for: name),
                                     services: services, characteristics: characteristics)
        status = "已识别数据通道 · 正在开启接收"
        checkpoint()
    }

    func start(peripheral: CBPeripheral, writer: CBCharacteristic) {
        guard !isBusy, report?.finishedAt == nil else { return }
        self.peripheral = peripheral; self.writer = writer; awaitingWrite = false; writeError = nil
        isBusy = true
        let session = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == session { self.finish() } }
            do {
                self.status = "正在读取型号与固件"
                _ = try await self.ask(try WearableProbeProtocol.infoRequest(), key: "info")
                self.status = "正在读取电量与当天步数"
                _ = try await self.ask(try WearableProbeProtocol.realtimeRequest(battery: true), key: "battery")
                _ = try await self.ask(try WearableProbeProtocol.realtimeRequest(battery: false), key: "health")
                for type in self.report?.channels.map(\.type) ?? [] {
                    try Task.checkCancellation()
                    self.activeType = type; self.activeRange = nil
                    let name = self.report?.channels.first { $0.type == type }?.name ?? "历史数据"
                    self.status = "正在检查\(name)"
                    self.channel(type, state: "正在查询")
                    let replied = try await self.ask(try WearableProbeProtocol.historyRequest(type: type), key: "index-\(type)")
                    guard !self.failedTypes.contains(type) else { continue }
                    guard replied else { self.channel(type, state: "查询未响应，尚不能确认支持情况"); continue }
                    let table = self.indexes[type] ?? []
                    guard let range = WearableProbeProtocol.sampleRange(table, limit: type == 4 ? 288 : type == 0 ? 120 : 8) else {
                        self.channel(type, state: table.isEmpty ? "设备返回空目录" : "目录范围无法识别"); continue
                    }
                    self.activeRange = range
                    if let index = self.report?.channels.firstIndex(where: { $0.type == type }) {
                        self.report?.channels[index].requestedStart = range.lowerBound
                        self.report?.channels[index].requestedEnd = range.upperBound
                    }
                    self.channel(type, state: type == 4 ? "正在读取心跳间隔历史，最多 288 包" : "正在读取最近的一段记录")
                    try await self.send(try WearableProbeProtocol.historyRequest(type: type, range: range))
                    let deadline = Date.now.addingTimeInterval(type == 4 ? 30 : 12)
                    while Date.now < deadline {
                        try Task.checkCancellation()
                        if self.failedTypes.contains(type) || self.hasAll(type: type, range: range) || self.storedBytes >= 2_000_000 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    try await self.send(try WearableProbeProtocol.historyRequest(type: type, stop: true))
                    self.decoder.discardIncomplete()
                    if !self.failedTypes.contains(type) {
                        let count = self.received[type]?.count ?? 0
                        self.channel(type, state: self.hasAll(type: type, range: range) ? "本段读取完成" : count > 0 ? "已收到部分记录，等待已结束" : "未收到记录，等待已结束")
                    }
                    self.checkpoint()
                }
                self.activeType = nil; self.activeRange = nil
                self.status = "本次验证完成 · 已收到 \(self.report?.records.count ?? 0) 条历史记录"
            } catch is CancellationError {
                guard self.generation == session else { return }
                self.status = "验证已结束，已收到的记录已保留"
            } catch {
                guard self.generation == session else { return }
                self.status = "读取中断：\(error.localizedDescription)"
                self.event(self.status)
            }
        }
    }

    func fail(_ message: String) { event(message); cancel(); status = message }

    func cancel() {
        task?.cancel(); task = nil
        if isBusy || (report != nil && report?.finishedAt == nil) {
            for index in report?.channels.indices ?? 0..<0 where report?.channels[index].state.hasPrefix("正在") == true {
                report?.channels[index].state = "读取中断，已收到的记录已保留"
            }
            if isBusy { status = "验证已结束，已收到的记录已保留" }
            finish()
        }
        generation = UUID()
        peripheral = nil; writer = nil; awaitingWrite = false
    }

    private func finish() {
        for index in report?.channels.indices ?? 0..<0 where report?.channels[index].state.hasPrefix("正在") == true {
            report?.channels[index].state = "读取已结束，本项未完成"
        }
        report?.finishedAt = .now
        report?.rejectedFrames = decoder.rejected
        isBusy = false
        checkpoint()
    }

    private func checkpoint() {
        guard let report else { return }
        do { reportURL = try WearableProbeStorage.save(report) }
        catch { status = "报告未能保存：\(error.localizedDescription)" }
    }

    private func channel(_ type: Int, state: String) {
        if let index = report?.channels.firstIndex(where: { $0.type == type }) { report?.channels[index].state = state }
    }
    private func event(_ value: String) { if (report?.events.count ?? 0) < 120 { report?.events.append(value) } }
    private func hasAll(type: Int, range: ClosedRange<UInt32>) -> Bool {
        let count = received[type]?.filter { range.contains($0) }.count ?? 0
        return UInt64(count) == UInt64(range.upperBound) - UInt64(range.lowerBound) + 1
    }

    private func ask(_ frame: WearableFrame, key: String) async throws -> Bool {
        answers.remove(key)
        try await send(frame)
        let deadline = Date.now.addingTimeInterval(4)
        while Date.now < deadline {
            try Task.checkCancellation()
            if answers.contains(key) { return true }
            try await Task.sleep(for: .milliseconds(80))
        }
        event("\(key)：等待响应超时")
        decoder.discardIncomplete()
        return false
    }

    private func send(_ frame: WearableFrame) async throws {
        try Task.checkCancellation()
        guard let peripheral, let writer, peripheral.state == .connected else { throw VeepooImportError.failure("设备已断开") }
        let mode: CBCharacteristicWriteType = writer.properties.contains(.write) ? .withResponse : .withoutResponse
        let size = max(1, peripheral.maximumWriteValueLength(for: mode))
        let bytes = frame.encoded()
        for start in stride(from: 0, to: bytes.count, by: size) {
            let deadline = Date.now.addingTimeInterval(3)
            while mode == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
                try Task.checkCancellation()
                guard Date.now < deadline else { throw VeepooImportError.failure("蓝牙发送繁忙") }
                try await Task.sleep(for: .milliseconds(20))
            }
            writeError = nil; awaitingWrite = mode == .withResponse
            peripheral.writeValue(Data(bytes[start..<min(start + size, bytes.count)]), for: writer, type: mode)
            while awaitingWrite {
                try Task.checkCancellation()
                guard Date.now < deadline else { throw VeepooImportError.failure("蓝牙读取请求未送达") }
                try await Task.sleep(for: .milliseconds(20))
            }
            if let writeError { throw VeepooImportError.failure(writeError) }
        }
    }

    func didWrite(error: Error?) { writeError = error?.localizedDescription; awaitingWrite = false }

    func receive(_ data: Data) {
        guard isBusy else { return }
        for frame in decoder.append(data) {
            do {
                switch frame.opcode {
                case 0:
                    let value = try IW_DeviceInfoResponse(serializedBytes: frame.payload)
                    report?.observedModel = value.hasModel ? value.model : nil
                    report?.observedFirmware = value.hasVersion ? value.version : nil
                    report?.observedAlgorithm = value.hasBpVersion ? value.bpVersion : nil
                    answers.insert("info")
                    if value.hasEncryptionStatus { event("设备返回加密状态原值：\(value.encryptionStatus)") }
                case 0x70:
                    let value = try IW_RtNotification(serializedBytes: frame.payload)
                    guard case .rtData(let rt) = value.data else { continue }
                    if rt.hasBattery {
                        report?.batteryLevel0To9 = rt.battery.level
                        battery = DeviceBatteryReading(gridLevel: Int(rt.battery.level), maximum: 9)
                        answers.insert("battery")
                    }
                    if rt.hasHealth { report?.currentSteps = rt.health.steps; answers.insert("health") }
                    if rt.hasHealthresult {
                        let value = rt.healthresult
                        var vitals: [(VitalKind, Double)] = []
                        if value.hasHr, VitalKind.heart.accepts(Double(value.hr)) { vitals.append((.heart, Double(value.hr))) }
                        if value.hasSpo2, VitalKind.oxygen.accepts(Double(value.spo2)) { vitals.append((.oxygen, Double(value.spo2))) }
                        if !vitals.isEmpty { onRealtimeVitals?(vitals) }
                    }
                case 0x80: try receiveHistory(IW_HisNotification(serializedBytes: frame.payload))
                default: event("收到未解析的操作码：\(frame.opcode)，\(frame.payload.count) 字节")
                }
            } catch { event("校验通过，但数据格式暂不能解析：\(error.localizedDescription)") }
        }
    }

    private func receiveHistory(_ notification: IW_HisNotification) throws {
        let type = notification.type.rawValue
        guard activeType == type, let index = report?.channels.firstIndex(where: { $0.type == type }) else { return }
        switch notification.data {
        case .indexTable(let table):
            indexes[type] = Array(table.index.prefix(128))
            report?.channels[index].available = table.index.reduce(UInt64(0)) {
                $0 + ($1.endSeq >= $1.startSeq ? UInt64($1.endSeq) - UInt64($1.startSeq) + 1 : 0)
            }
            answers.insert("index-\(type)")
        case .confirm(let value) where !value.ret:
            // A stop acknowledgement is unrelated to the next index query.
            guard value.operation != .stopSync else { return }
            failedTypes.insert(type); answers.insert("index-\(type)")
            channel(type, state: "设备拒绝本次请求，需核对权限或支持情况")
        case .hisData(let value):
            guard let range = activeRange, range.contains(value.seq) else { return }
            if case .status(let code) = value.data {
                if code != .statusOk { failedTypes.insert(type); channel(type, state: "设备返回状态 \(code.rawValue)，本项未完成") }
                return
            }
            guard value.data != nil || !value.unknownFields.data.isEmpty, received[type]?.contains(value.seq) != true else { return }
            let record = try WearableProbeProtocol.record(value, type: type)
            let bytes = record.protobufJSON.utf8.count + (record.protobufBase64?.utf8.count ?? 0)
            guard storedBytes + bytes <= 2_000_000, (report?.records.count ?? 0) < 512 else {
                storedBytes = 2_000_000; event("已达到本次记录上限"); return
            }
            received[type, default: []].insert(value.seq)
            report?.records.append(record); storedBytes += bytes
            report?.channels[index].received = received[type]?.count ?? 0
        default: break
        }
    }
}

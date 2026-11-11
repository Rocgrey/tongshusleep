import Foundation
import CoreBluetooth
import Combine

enum BLEReadState: Equatable {
    case unchecked, checking, unavailable, waiting, received, timedOut, failed(String)
    var label: String {
        switch self {
        case .unchecked: "尚未检查"
        case .checking: "正在检查"
        case .unavailable: "未发现可用的标准特征"
        case .waiting: "已请求，等待设备数据"
        case .received: "已读取"
        case .timedOut: "未收到数据，可重新读取"
        case .failed(let reason): reason
        }
    }
}

enum BLEStandardAccess {
    static func canRead(service: String, characteristic: String) -> Bool {
        [("180F", "2A19"), ("180A", "2A24"), ("180D", "2A37"), ("1810", "2A35"), ("1822", "2A5E"), ("1822", "2A5F")].contains { $0 == service && $1 == characteristic }
    }
    static func canSubscribe(service: String, characteristic: String) -> Bool {
        [("180D", "2A37"), ("1810", "2A35"), ("1822", "2A5E"), ("1822", "2A5F")].contains { $0 == service && $1 == characteristic }
    }
}

struct NearbyRing: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var id: UUID { peripheral.identifier }
}

@MainActor
final class RingScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [NearbyRing] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var connectingID: UUID?
    @Published private(set) var status = "尚未连接设备"
    @Published private(set) var battery: Int?
    @Published private(set) var modelNumber: String?
    @Published private(set) var liveHeartRate: Int?
    @Published private(set) var supportsHeartRate = false
    @Published private(set) var isInspecting = false
    @Published private(set) var batteryState = BLEReadState.unchecked
    @Published private(set) var modelState = BLEReadState.unchecked
    @Published private(set) var heartRateState = BLEReadState.unchecked
    @Published private(set) var discoveredServices: [String] = []
    @Published private(set) var discoveredCharacteristics: [String: [String]] = [:]
    @Published private(set) var readErrors: [String] = []
    @Published private(set) var veepooChannelDetected = false
    @Published private(set) var isHandingOff = false
    @Published private(set) var rememberedDevices: [RememberedDevice] = []
    @Published private(set) var latestVitals: [WearableVital] = []
    @Published private(set) var wearableChannelDetected = false
    @Published private(set) var wearableProbeAvailable = false
    let wearable = WearableProbeClient()
    let encryptedBand = EncryptedBandStore()
    @Published private(set) var encryptedBandChannelDetected = false
    private var wearableWriter: CBCharacteristic?
    private var wearableNotify: CBCharacteristic?
    private var wearableStarted = false
    private let rememberedStorage = RememberedDeviceStorage(defaults: .standard)
    private var pendingReconnect: RememberedDevice?
    private var inspectionTimeout: Task<Void, Never>?
    private var pendingServices: Set<String> = []
    private var inspectedAt: Date?
    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var selectedName: String?
    private var wantsScan = false
    private var scanTimeout: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?

    override init() {
        super.init()
        rememberedDevices = rememberedStorage.load().filter { $0.verifiedRing == true || $0.verifiedWearable == true || $0.verifiedConnection == true || RingDevicePolicy.recognizes(name: $0.name) }
        wearable.onRealtimeVitals = { [weak self] values in
            guard let self, let peripheral = self.connected else { return }
            self.latestVitals = values.map { self.makeVital($0.0, value: $0.1, peripheral: peripheral) }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.arguments.contains("-ui-testing-probe") {
            wearableProbeAvailable = true
        }
        #endif
    }

    func reconnect(_ device: RememberedDevice) {
        guard connected == nil, connectingID == nil, !isHandingOff else { return }
        pendingReconnect = device
        status = "正在重连已保存的设备…"
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { reconnectIfReady() }
    }

    private func reconnectIfReady() {
        guard let central, central.state == .poweredOn, let device = pendingReconnect else { return }
        pendingReconnect = nil
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [device.id]).first else {
            status = "系统未找到此设备，请重新搜索一次。原设备记录已保留。"
            return
        }
        connect(NearbyRing(peripheral: peripheral, name: device.name, rssi: 0))
    }

    func forget(_ device: RememberedDevice) {
        do { try encryptedBand.forget(device.id) }
        catch { status = "设备凭证未能移除，请重试。"; return }
        if pendingReconnect?.id == device.id { pendingReconnect = nil }
        rememberedDevices.removeAll { $0.id == device.id }
        rememberedStorage.save(rememberedDevices)
    }

    var diagnosticReport: String {
        var lines = ["sleeptongshu · 蓝牙读取诊断", "设备：\(connectedName ?? "未连接")",
                     "检查时间：\(inspectedAt?.formatted(date: .numeric, time: .standard) ?? "尚未检查")",
                     "状态：\(status)", "电量：\(batteryState.label)", "型号：\(modelNumber ?? modelState.label)",
                     "心率：\(heartRateState.label)",
                     "历史睡眠：\(wearableProbeAvailable ? "新设备接入结果见本地接入报告" : VeepooRingClient.enabled && veepooChannelDetected ? "通道检查完成后自动同步" : "未识别到受支持的数据通道")"]
        if discoveredServices.isEmpty { lines.append("尚未发现服务，或设备未开放服务。") }
        for service in discoveredServices {
            lines.append("服务 \(service)")
            lines += (discoveredCharacteristics[service] ?? []).map { "  \($0)" }
        }
        lines += readErrors.map { "读取提示：\($0)" }
        lines.append("仅读取已支持的标准数据及已识别通道的文档化查询；不修改新设备设置。历史记录另存于本地接入报告。")
        return lines.joined(separator: "\n")
    }

    func inspectDevice() {
        guard let connected, connected.state == .connected, !isInspecting else { return }
        inspectionTimeout?.cancel()
        wearable.cancel()
        encryptedBandChannelDetected = false
        wearableChannelDetected = false; wearableProbeAvailable = false; wearableWriter = nil; wearableNotify = nil; wearableStarted = false
        inspectedAt = .now
        isInspecting = true
        battery = nil; modelNumber = nil; liveHeartRate = nil; supportsHeartRate = false
        batteryState = .checking; modelState = .checking; heartRateState = .checking
        discoveredServices = []; discoveredCharacteristics = [:]; readErrors = []; pendingServices = []
        veepooChannelDetected = false
        latestVitals = []
        status = "已连接 · 正在检查可读取的数据"
        // Inventory all services, but only read/subscribe to explicitly supported standard characteristics.
        connected.discoverServices(nil)
        inspectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self else { return }
            let timedOut = [self.batteryState, self.modelState, self.heartRateState].contains { $0 == .checking || $0 == .waiting }
            if self.batteryState == .checking || self.batteryState == .waiting { self.batteryState = .timedOut }
            if self.modelState == .checking || self.modelState == .waiting { self.modelState = .timedOut }
            if self.heartRateState == .checking || self.heartRateState == .waiting { self.heartRateState = .timedOut }
            if self.isInspecting { self.recordError("服务检查超时，请重新读取或重连设备。") }
            self.isInspecting = false
            if timedOut && !self.wearableChannelDetected { self.status = "已连接 · 部分数据未收到，见下方状态" }
        }
    }

    private func recordError(_ message: String) {
        if !readErrors.contains(message) { readErrors.append(message) }
        if readErrors.count > 20 { readErrors.removeFirst() }
    }

    private func setState(_ state: BLEReadState, characteristic: CBCharacteristic) {
        switch (characteristic.service?.uuid.uuidString, characteristic.uuid.uuidString) {
        case ("180F", "2A19"): batteryState = state; if state != .received { battery = nil }
        case ("180A", "2A24"): modelState = state; if state != .received { modelNumber = nil }
        case ("180D", "2A37"): heartRateState = state; if state != .received { liveHeartRate = nil }
        default: break
        }
    }

    private func finishInspectionIfReady() {
        guard pendingServices.isEmpty else { return }
        isInspecting = false
        if batteryState == .checking { batteryState = .unavailable }
        if modelState == .checking { modelState = .unavailable }
        if heartRateState == .checking { heartRateState = .unavailable }
        status = encryptedBandChannelDetected ? "已连接 · 加密设备需验证已有绑定凭证" : wearableChannelDetected ? "已连接 · 自动读取数据，进度见下方" : veepooChannelDetected ? "已连接 · 即将自动同步" : "已连接 · 尚不支持此设备的睡眠与体征同步"
        if let connected {
            rememberedDevices.removeAll { $0.id == connected.identifier }
            rememberedDevices.insert(RememberedDevice(id: connected.identifier, name: connectedName ?? "设备", lastConnected: .now,
                                                       verifiedRing: veepooChannelDetected, verifiedWearable: wearableChannelDetected, verifiedConnection: true), at: 0)
            rememberedStorage.save(rememberedDevices)
        }
        if encryptedBandChannelDetected, let connected, encryptedBand.hasCredential(connected.identifier) {
            startEncryptedBandSync()
            return
        }
        if !wearableChannelDetected, !wearableStarted, let connected,
           WearableGatt.reportedFirmware(for: connectedName ?? "") != nil {
            wearableStarted = true; wearableProbeAvailable = true
            wearable.prepare(name: connectedName ?? "设备", id: connected.identifier,
                             services: discoveredServices, characteristics: discoveredCharacteristics)
            wearable.fail("已连接，但未发现兼容的数据接口；服务信息已存入报告")
        }
        if wearableChannelDetected, !wearableStarted, let connected, let wearableNotify {
            wearableStarted = true; wearableProbeAvailable = true
            wearable.prepare(name: connectedName ?? "设备", id: connected.identifier,
                             services: discoveredServices, characteristics: discoveredCharacteristics)
            let session = wearable.sessionID
            // CoreBluetooth need not emit another state callback for an already-active
            // subscription. Refreshing a connected device must start the read immediately.
            if wearableNotify.isNotifying, let wearableWriter {
                wearable.start(peripheral: connected, writer: wearableWriter)
            } else { connected.setNotifyValue(true, for: wearableNotify) }
            Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.connected?.identifier == connected.identifier,
                      self.wearable.sessionID == session, !self.wearable.isBusy,
                      self.wearableNotify === wearableNotify,
                      self.wearable.report?.finishedAt == nil else { return }
                self.wearable.fail("数据接收未能开启，请重新连接")
            }
        }
    }

    func scan() {
        guard connected == nil, connectingID == nil, !isHandingOff, !encryptedBand.isBusy else { return }
        wantsScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginScanIfReady() }
    }

    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        scanTimeout?.cancel()
        devices.removeAll()
        isScanning = true
        status = "正在搜索附近蓝牙设备…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        scanTimeout?.cancel()
        wantsScan = false
        central?.stopScan()
        isScanning = false
        if connectedName == nil && connectingID == nil && central?.state == .poweredOn {
            status = devices.isEmpty ? "未发现蓝牙设备，请靠近手机并确认设备有电" : "发现 \(devices.count) 台蓝牙设备"
        }
    }

    func connect(_ device: NearbyRing) {
        guard connectingID == nil, connected == nil, !encryptedBand.isBusy, !isHandingOff, let central, central.state == .poweredOn else { return }
        stopScan()
        connectingID = device.id
        connected = device.peripheral
        selectedName = device.name
        status = "正在连接 \(device.name)…"
        central.connect(device.peripheral)
        connectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.connectingID != nil else { return }
            self.disconnect()
            self.status = "连接超时，请确认设备可配对后重试"
        }
    }

    func disconnect() {
        wearable.cancel()
        encryptedBandChannelDetected = false
        wearableChannelDetected = false; wearableProbeAvailable = false; wearableWriter = nil; wearableNotify = nil; wearableStarted = false
        pendingReconnect = nil
        connectionTimeout?.cancel()
        inspectionTimeout?.cancel()
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil
        connectingID = nil
        connectedName = nil
        selectedName = nil
        battery = nil
        modelNumber = nil
        liveHeartRate = nil
        supportsHeartRate = false
        isInspecting = false
        batteryState = .unchecked; modelState = .unchecked; heartRateState = .unchecked
        discoveredServices = []; discoveredCharacteristics = [:]; readErrors = []; pendingServices = []; inspectedAt = nil
        veepooChannelDetected = false
        status = "已断开连接"
    }

    var encryptedBandTarget: (id: UUID, name: String)? {
        guard encryptedBandChannelDetected, let connected, let connectedName else { return nil }
        return (connected.identifier, connectedName)
    }

    /// Hand off to a dedicated encrypted session only after the scanner releases its connection.
    func startEncryptedBandSync() {
        guard !isInspecting, !isHandingOff, !encryptedBand.isBusy,
              let target = encryptedBandTarget, let peripheral = connected,
              encryptedBand.hasCredential(target.id) else { return }
        isHandingOff = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isHandingOff = false }
            self.disconnect()
            for _ in 0..<40 {
                if peripheral.state == .disconnected {
                    self.encryptedBand.sync(id: target.id, name: target.name)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            self.encryptedBand.fail("原连接尚未释放，请重新连接设备。")
        }
    }

    func releaseForVendorSync() async throws -> CBPeripheral {
        guard let peripheral = connected, peripheral.state == .connected, veepooChannelDetected,
              !isHandingOff else { throw VeepooImportError.failure("请先连接戒指并完成服务检查。") }
        isHandingOff = true
        defer { isHandingOff = false }
        disconnect()
        for _ in 0..<30 {
            try Task.checkCancellation()
            if peripheral.state == .disconnected { return peripheral }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw VeepooImportError.failure("原连接未能及时释放，请重新连接戒指再试。")
    }
}

extension RingScanner: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "蓝牙已开启"; reconnectIfReady(); beginScanIfReady()
        case .poweredOff: disconnect(); stopScan(); status = "蓝牙已关闭，请在系统设置中开启"
        case .unauthorized: stopScan(); status = "蓝牙未授权，请在设置中允许访问"
        case .unsupported: stopScan(); status = "当前设备不支持蓝牙扫描"
        case .resetting: stopScan(); status = "蓝牙正在重置，请稍后重试"
        case .unknown: status = "正在检查蓝牙状态…"
        @unknown default: status = "暂时无法使用蓝牙"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let name = DevicePresentation.bluetoothName(
            advertised: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            peripheral: peripheral.name,
            previous: devices.first(where: { $0.id == peripheral.identifier })?.name,
            id: peripheral.identifier)
        let device = NearbyRing(peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard connected?.identifier == peripheral.identifier else { central.cancelPeripheralConnection(peripheral); return }
        connectionTimeout?.cancel()
        connectingID = nil
        connectedName = selectedName ?? DevicePresentation.bluetoothName(advertised: nil, peripheral: peripheral.name, id: peripheral.identifier)
        peripheral.delegate = self
        inspectDevice()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        connectionTimeout?.cancel()
        connected = nil
        connectingID = nil
        selectedName = nil
        status = "连接失败：\(error?.localizedDescription ?? "请重试")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        disconnect()
        status = error.map { "连接已中断：\($0.localizedDescription)" } ?? "已断开连接"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        if let error {
            recordError("发现服务失败：\(error.localizedDescription)")
            let failure = BLEReadState.failed("服务读取失败，见设备诊断")
            batteryState = failure; modelState = failure; heartRateState = failure
            isInspecting = false
            status = "已连接 · 服务检查失败"
            return
        }
        discoveredServices = (peripheral.services ?? []).map { $0.uuid.uuidString }.sorted()
        pendingServices = Set(discoveredServices)
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        finishInspectionIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        defer { pendingServices.remove(service.uuid.uuidString); finishInspectionIfReady() }
        if let error {
            recordError("服务 \(service.uuid.uuidString)：\(error.localizedDescription)")
            let failure = BLEReadState.failed("特征检查失败，见设备诊断")
            switch service.uuid.uuidString {
            case "180F": batteryState = failure
            case "180A": modelState = failure
            case "180D": heartRateState = failure
            default: break
            }
            return
        }
        discoveredCharacteristics[service.uuid.uuidString] = (service.characteristics ?? []).map { characteristic in
            let properties = characteristic.properties
            var flags: [String] = []
            if properties.contains(.read) { flags.append("可读") }
            if properties.contains(.notify) { flags.append("通知") }
            if properties.contains(.indicate) { flags.append("指示") }
            if properties.contains(.write) || properties.contains(.writeWithoutResponse) { flags.append("可写") }
            return "\(characteristic.uuid.uuidString) · \(flags.joined(separator: "、"))"
        }.sorted()
        if service.uuid.uuidString == VeepooGatt.service {
            let values = service.characteristics ?? []
            veepooChannelDetected = !wearableChannelDetected && values.contains { $0.uuid.uuidString == VeepooGatt.notify && $0.properties.contains(.notify) }
                && values.contains { $0.uuid.uuidString == VeepooGatt.write && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) }
        }
        if service.uuid.uuidString == WearableGatt.service {
            wearableNotify = service.characteristics?.first { $0.uuid.uuidString == WearableGatt.notify && ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) }
            wearableWriter = service.characteristics?.first { $0.uuid.uuidString == WearableGatt.write && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) }
            wearableChannelDetected = wearableNotify != nil && wearableWriter != nil
            if wearableChannelDetected { veepooChannelDetected = false }
        }
        if service.uuid == STBandBandLink.fe95 {
            let values = service.characteristics ?? []
            let notify = values.contains { $0.uuid == STBandBandLink.rxUUID && ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) }
            let write = values.contains { $0.uuid == STBandBandLink.txUUID && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) }
            encryptedBandChannelDetected = notify && write
            if encryptedBandChannelDetected { veepooChannelDetected = false; wearableChannelDetected = false }
        }
        for characteristic in service.characteristics ?? [] {
            let canRead = BLEStandardAccess.canRead(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString)
            guard canRead else { continue }
            if characteristic.properties.contains(.read) {
                setState(.waiting, characteristic: characteristic)
                peripheral.readValue(for: characteristic)
            }
            if BLEStandardAccess.canSubscribe(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString),
               characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                if characteristic.uuid.uuidString == "2A37" { supportsHeartRate = true }
                setState(.waiting, characteristic: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        if characteristic.service?.uuid.uuidString == WearableGatt.service, characteristic.uuid.uuidString == WearableGatt.notify {
            if let error { wearable.fail("接收失败：\(error.localizedDescription)") }
            else if let data = characteristic.value { wearable.receive(data) }
            return
        }
        guard
              BLEStandardAccess.canRead(service: characteristic.service?.uuid.uuidString ?? "", characteristic: characteristic.uuid.uuidString) else { return }
        if let error {
            recordError("\(characteristic.uuid.uuidString)：\(error.localizedDescription)")
            setState(.failed("读取失败，见设备诊断"), characteristic: characteristic)
            return
        }
        guard let value = characteristic.value else { setState(.failed("设备返回空数据"), characteristic: characteristic); return }
        switch characteristic.uuid.uuidString {
        case "2A19":
            guard let first = value.first, first <= 100 else { setState(.failed("设备电量格式无法识别"), characteristic: characteristic); return }
            battery = Int(first)
        case "2A24":
            guard let model = String(data: value, encoding: .utf8), !model.isEmpty else { setState(.failed("设备型号格式无法识别"), characteristic: characteristic); return }
            modelNumber = DevicePresentation.name(model)
        case "2A37":
            guard let rate = StandardHeartRate.decode(value) else { setState(.failed("心率数据无效或格式不兼容"), characteristic: characteristic); return }
            liveHeartRate = rate
            latestVitals = [makeVital(.heart, value: Double(rate), peripheral: peripheral)]
        case "2A35", "2A5E", "2A5F":
            latestVitals = StandardVitalDecoder.decode(value, characteristic: characteristic.uuid.uuidString).map {
                makeVital($0.0, value: $0.1, peripheral: peripheral)
            }
            if latestVitals.isEmpty { recordError("设备未返回可验证的血氧或血压测量值。") }
        default: return
        }
        setState(.received, characteristic: characteristic)
    }

    private func makeVital(_ kind: VitalKind, value: Double, peripheral: CBPeripheral) -> WearableVital {
        let key = WearableVital.deviceKey(peripheral.identifier.uuidString)
        return WearableVital(device: key, deviceLabel: "\(connectedName ?? "戒指") · \(key.prefix(6))", date: .now,
                             kind: kind, value: value, origin: "蓝牙接收时间")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        if characteristic.service?.uuid.uuidString == WearableGatt.service, characteristic.uuid.uuidString == WearableGatt.notify {
            if let error { wearable.fail("数据接收失败：\(error.localizedDescription)") }
            else if characteristic.isNotifying, let wearableWriter { wearable.start(peripheral: peripheral, writer: wearableWriter) }
            else { wearable.fail("设备未开启数据接收") }
            return
        }
        guard
              BLEStandardAccess.canSubscribe(service: characteristic.service?.uuid.uuidString ?? "", characteristic: characteristic.uuid.uuidString) else { return }
        if let error {
            recordError("\(characteristic.uuid.uuidString) 通知订阅失败：\(error.localizedDescription)")
            if characteristic.uuid.uuidString == "2A37", liveHeartRate == nil { heartRateState = .failed("心率订阅失败，见设备诊断") }
        } else if characteristic.uuid.uuidString == "2A37", !characteristic.isNotifying, liveHeartRate == nil {
            heartRateState = .failed("设备没有开启心率通知")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connected?.identifier == peripheral.identifier, characteristic === wearableWriter else { return }
        wearable.didWrite(error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard connected?.identifier == peripheral.identifier else { return }
        inspectionTimeout?.cancel()
        isInspecting = false
        inspectDevice()
    }
}

enum StandardHeartRate {
    static func decode(_ data: Data) -> Int? {
        let bytes = Array(data)
        guard bytes.count >= 2 else { return nil }
        let value: Int
        if bytes[0] & 1 == 0 { value = Int(bytes[1]) }
        else {
            guard bytes.count >= 3 else { return nil }
            value = Int(bytes[1]) | Int(bytes[2]) << 8
        }
        return (20...250).contains(value) ? value : nil
    }
}

// Device-specific SDKs/protocols can map their history to validated local payloads.
protocol WearableSleepAdapter {
    var providerName: String { get }
    func fetchSleep(since: Date) async throws -> [SleepPayload]
}

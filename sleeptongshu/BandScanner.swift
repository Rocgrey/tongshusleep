import Foundation
import CoreBluetooth
import Combine

struct NearbyBand: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var id: UUID { peripheral.identifier }
}

@MainActor
final class BandScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [NearbyBand] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var connectingID: UUID?
    @Published private(set) var status = "尚未连接手环"
    @Published private(set) var battery: Int?
    @Published private(set) var modelNumber: String?
    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var wantsScan = false
    private var scanTimeout: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?

    func scan() {
        wantsScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginScanIfReady() }
    }

    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        scanTimeout?.cancel()
        devices.removeAll()
        isScanning = true
        status = "正在搜索附近设备…"
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
            status = devices.isEmpty ? "未发现设备，可将手环靠近后重试" : "发现 \(devices.count) 个设备"
        }
    }

    func connect(_ device: NearbyBand) {
        guard connectingID == nil, connected == nil, let central, central.state == .poweredOn else { return }
        stopScan()
        connectingID = device.id
        connected = device.peripheral
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
        connectionTimeout?.cancel()
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil
        connectingID = nil
        connectedName = nil
        battery = nil
        modelNumber = nil
        status = "已断开连接"
    }
}

extension BandScanner: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "蓝牙已开启"; beginScanIfReady()
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
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名设备"
        let device = NearbyBand(peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimeout?.cancel()
        connectingID = nil
        connectedName = peripheral.name ?? "蓝牙设备"
        status = "蓝牙已连接 · 睡眠同步尚未适配"
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "180F"), CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTimeout?.cancel()
        connected = nil
        connectingID = nil
        status = "连接失败：\(error?.localizedDescription ?? "请重试")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        disconnect()
        status = error.map { "连接已中断：\($0.localizedDescription)" } ?? "已断开连接"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([CBUUID(string: "2A19"), CBUUID(string: "2A24")], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        if characteristic.uuid == CBUUID(string: "2A19"), let first = value.first, first <= 100 { battery = Int(first) }
        if characteristic.uuid == CBUUID(string: "2A24") { modelNumber = String(data: value, encoding: .utf8) }
    }
}

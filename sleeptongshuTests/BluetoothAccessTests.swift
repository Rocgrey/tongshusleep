import XCTest
@testable import sleeptongshu

final class BluetoothAccessTests: XCTestCase {
    func testBluetoothNamesUseBroadcastNameWithoutRelabelingOtherDevicesAsRings() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        XCTAssertEqual(DevicePresentation.bluetoothName(advertised: "  卧室音箱  ", peripheral: "系统缓存名称", id: id), "卧室音箱")
        XCTAssertEqual(DevicePresentation.bluetoothName(advertised: "G Band L03", peripheral: nil, id: id), "G Band L03")
        XCTAssertEqual(DevicePresentation.bluetoothName(advertised: " \n", peripheral: "蓝牙耳机", id: id), "蓝牙耳机")
        XCTAssertEqual(DevicePresentation.bluetoothName(advertised: nil, peripheral: nil, previous: "L03 Ultra", id: id), "L03 Ultra")
        XCTAssertEqual(DevicePresentation.bluetoothName(advertised: nil, peripheral: " ", id: id), "未命名蓝牙设备 · 1234")
    }

    func testBatteryPreservesPercentageAndGridUnitsAndRejectsInvalidValues() {
        XCTAssertEqual(DeviceBatteryReading(level: 68, isPercentage: true)?.text, "68%")
        XCTAssertEqual(DeviceBatteryReading(level: 0, isPercentage: true)?.fraction, 0)
        XCTAssertEqual(DeviceBatteryReading(level: 100, isPercentage: true)?.fraction, 1)
        XCTAssertEqual(DeviceBatteryReading(level: 3, isPercentage: false)?.text, "3/4 格")
        XCTAssertEqual(DeviceBatteryReading(level: 3, isPercentage: false)?.fraction, 0.75)
        XCTAssertEqual(DeviceBatteryReading(level: 68, isPercentage: true, isLow: true)?.isLow, true)
        XCTAssertEqual(DeviceBatteryReading(level: 20, isPercentage: true)?.isLow, true)
        XCTAssertNil(DeviceBatteryReading(level: -1, isPercentage: true))
        XCTAssertNil(DeviceBatteryReading(level: 101, isPercentage: true))
        XCTAssertNil(DeviceBatteryReading(level: 5, isPercentage: false))
    }

    @MainActor
    func testPreparingAnotherDeviceClearsThePreviousBattery() {
        let client = VeepooRingClient()
        client.preparing(name: "第一枚戒指", battery: 80)
        XCTAssertEqual(client.battery?.text, "80%")
        client.preparing(name: "第二枚戒指", battery: nil)
        XCTAssertNil(client.battery)
        XCTAssertEqual(client.deviceName, "第二枚戒指")
        client.cancel()
    }

    func testRingDiscoveryExcludesOtherDeviceNamesAndAcceptsTheKnownRingService() {
        XCTAssertTrue(RingDevicePolicy.recognizes(name: "L03 Ultra"))
        XCTAssertTrue(RingDevicePolicy.recognizes(name: "G Band"))
        XCTAssertTrue(RingDevicePolicy.recognizes(name: "未知名称", services: [VeepooGatt.service]))
        XCTAssertFalse(RingDevicePolicy.recognizes(name: "Xiaomi Smart Band 10 Pro"))
        XCTAssertFalse(RingDevicePolicy.recognizes(name: "手环"))
        XCTAssertFalse(RingDevicePolicy.recognizes(name: "Apple Watch"))
        XCTAssertFalse(RingDevicePolicy.recognizes(name: "蓝牙耳机"))
    }

    func testReadsAreRestrictedToKnownServiceAndCharacteristicPairs() {
        XCTAssertTrue(BLEStandardAccess.canRead(service: "180F", characteristic: "2A19"))
        XCTAssertTrue(BLEStandardAccess.canRead(service: "180A", characteristic: "2A24"))
        XCTAssertTrue(BLEStandardAccess.canRead(service: "180D", characteristic: "2A37"))
        XCTAssertFalse(BLEStandardAccess.canRead(service: "FF00", characteristic: "2A37"))
        XCTAssertFalse(BLEStandardAccess.canRead(service: "180D", characteristic: "FF01"))
        XCTAssertFalse(BLEStandardAccess.canRead(service: "180D", characteristic: "2A19"))
        XCTAssertTrue(BLEStandardAccess.canSubscribe(service: "180D", characteristic: "2A37"))
        XCTAssertFalse(BLEStandardAccess.canSubscribe(service: "180F", characteristic: "2A19"))
        XCTAssertFalse(BLEStandardAccess.canSubscribe(service: "FF00", characteristic: "FF01"))
    }
}

import XCTest
@testable import sleeptongshu

final class BluetoothAccessTests: XCTestCase {
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

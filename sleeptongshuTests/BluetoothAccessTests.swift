import XCTest
@testable import sleeptongshu

final class BluetoothAccessTests: XCTestCase {
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

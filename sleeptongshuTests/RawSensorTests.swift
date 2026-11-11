import XCTest
import SwiftProtobuf
@testable import sleeptongshu

final class RawSensorTests: XCTestCase {
    private func packet(type: UInt32 = 16, seq: UInt32 = 37) throws -> RawSensorPacket {
        var notification = IW_RtNotification()
        notification.rtSensordata.type = type
        notification.rtSensordata.time.seconds = 1794390000
        notification.rtSensordata.seq = seq
        notification.rtSensordata.data = [100, UInt32(bitPattern: -1012), 202, UInt32.max]
        let wire = try notification.serializedData()
        let decoded = try IW_RtNotification(serializedBytes: wire)
        return try RawSensorPacket(decoded.rtSensordata, notification: wire, receivedAt: Date(timeIntervalSince1970: 1794390001))
    }
    func testSensorTypesAndSignedFixed32ViewRetainOriginalWireWords() throws {
        let p = try packet()
        XCTAssertEqual(p.sensorDataList, [100, -1012, 202, -1])
        XCTAssertTrue(p.sensorName.contains("ACC"))
        XCTAssertTrue(try packet(type: 512).sensorName.contains("BIOZ"))
        XCTAssertTrue(try packet(type: 2).sensorName.contains("PPG"))
        let wire = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(p.notificationBase64)))
        let restored = try IW_RtNotification(serializedBytes: wire)
        XCTAssertEqual(restored.rtSensordata.data, [100, UInt32(bitPattern: -1012), 202, UInt32.max])
        XCTAssertEqual(restored.rtSensordata.time.seconds, p.sensorSeconds)
        XCTAssertEqual(try JSONDecoder().decode(RawSensorPacket.self, from: JSONEncoder().encode(p)), p)
    }
    func testBoundedBatchesUseStableIdsAndRequireFinishedCapture() throws {
        var report = WearableProbeReport(deviceName: "BIO · synthetic", deviceKey: "synthetic")
        report.rawSensorPackets = try (0..<256).map { try packet(seq: UInt32($0)) }
        XCTAssertTrue(RawSensorBatchRequest.make(report).isEmpty)
        report.finishedAt = .now
        let batches = RawSensorBatchRequest.make(report)
        XCTAssertEqual(batches.map { $0.packets.count }, [100,100,56])
        XCTAssertEqual(batches.map(\.upload_id), RawSensorBatchRequest.make(report).map(\.upload_id))
        let json = String(decoding: try JSONEncoder().encode(batches[0]), as: UTF8.self)
        XCTAssertTrue(json.contains("device_seconds_unverified"))
        XCTAssertFalse(json.contains("user_id")); XCTAssertFalse(json.contains("deep_sleep"))
        report.startedAt = report.startedAt.addingTimeInterval(1)
        XCTAssertNotEqual(batches[0].capture_id, RawSensorBatchRequest.make(report)[0].capture_id)
    }
    func testStartAndStopUseDocumentedRealtimeSensorBitmask() throws {
        let start = try WearableProbeProtocol.sensorRequest(stop: false)
        XCTAssertEqual(start.opcode, 0x70)
        let value = try IW_RtSubscriber(serializedBytes: start.payload)
        XCTAssertEqual(value.sensor.type, 528); XCTAssertEqual(value.sensor.operation, .sensorStartSync)
        let stop = try IW_RtSubscriber(serializedBytes: WearableProbeProtocol.sensorRequest(stop: true).payload)
        XCTAssertEqual(stop.sensor.operation, .sensorStopSync)
        XCTAssertThrowsError(try RawSensorPacket(IW_RtSensorData(), notification: Data()))
    }
}

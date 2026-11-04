import XCTest
import SwiftProtobuf
@testable import sleeptongshu

final class WearableProtocolTests: XCTestCase {
    func testDocumentedReadQueriesHaveKnownWireValues() throws {
        XCTAssertEqual(try WearableProbeProtocol.infoRequest().payload, Data([0x0d, 123, 0, 0, 0, 0x10, 0]))
        XCTAssertEqual(try WearableProbeProtocol.realtimeRequest(battery: true).payload, Data([0x10, 1]))
        XCTAssertEqual(try WearableProbeProtocol.realtimeRequest(battery: false).payload, Data([0x18, 1]))
        XCTAssertEqual(try WearableProbeProtocol.historyRequest(type: 3).payload, Data([8, 0, 0x12, 2, 8, 3]))
        let request = try IW_HisSubscriber(serializedBytes: WearableProbeProtocol.historyRequest(type: 17, range: 12...19).payload)
        XCTAssertEqual(request.operation, .startSync)
        XCTAssertEqual(request.startSync.block.first?.startSeq, 12)
        XCTAssertEqual(request.startSync.block.first?.endSeq, 19)
        XCTAssertEqual(request.startSync.type.rawValue, 17)
        let stop = try IW_HisSubscriber(serializedBytes: WearableProbeProtocol.historyRequest(type: 17, stop: true).payload)
        XCTAssertEqual(stop.operation, .stopSync)
    }

    func testIndexSampleDoesNotUnderflowOrExpandMalformedRanges() {
        var small = IW_HisIndex(); small.startSeq = 0; small.endSeq = 3
        var large = IW_HisIndex(); large.startSeq = UInt32.max - 100; large.endSeq = UInt32.max
        var invalid = IW_HisIndex(); invalid.startSeq = 12; invalid.endSeq = 2
        XCTAssertEqual(WearableProbeProtocol.sampleRange([small], limit: 120), 0...3)
        XCTAssertEqual(WearableProbeProtocol.sampleRange([small, large, invalid], limit: 8), (UInt32.max - 7)...UInt32.max)
        XCTAssertNil(WearableProbeProtocol.sampleRange([invalid], limit: 8))
        XCTAssertNil(WearableProbeProtocol.sampleRange([small], limit: 0))
    }

    func testUnknownFirmwareFieldsSurviveBinaryExportAndMissingMetricsStayEmpty() throws {
        // seq=7, then a field unknown to the supplied schema (field 100, varint 9).
        let wire = Data([0x0d, 7, 0, 0, 0, 0xa0, 6, 9])
        let value = try IW_HisData(serializedBytes: wire)
        let record = try WearableProbeProtocol.record(value, type: 17)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(record.protobufBase64)), wire)
        XCTAssertNil(record.heartRate)
        XCTAssertNil(record.oxygen)
        XCTAssertNil(record.steps)
        XCTAssertThrowsError(try IW_HisNotification(serializedBytes: Data([0x22, 1, 0xff])))
    }

    func testRememberedWearablesDoNotBreakOldSavedDevices() throws {
        let old = Data("{\"id\":\"12345678-1234-1234-1234-123456789ABC\",\"name\":\"L03\",\"lastConnected\":0,\"verifiedRing\":true}".utf8)
        let device = try JSONDecoder().decode(RememberedDevice.self, from: old)
        XCTAssertTrue(device.verifiedRing == true)
        XCTAssertNil(device.verifiedWearable)
        XCTAssertNil(device.verifiedConnection)
    }
    func testKnownXmodemChecksumAndLittleEndianHeader() {
        XCTAssertEqual(WearableFrame.crc(Data("123456789".utf8)), 0x31c3)
        let bytes = WearableFrame(opcode: 0x80, payload: Data("123456789".utf8)).encoded()
        XCTAssertEqual(Array(bytes.prefix(8)), [0x44, 0x54, 9, 0, 0xc3, 0x31, 0x80, 0])
    }

    func testSplitHeadersAndConcatenatedFrames() {
        let a = WearableFrame(opcode: 0, payload: Data([0x10, 0]))
        let b = WearableFrame(opcode: 0x70, payload: Data([8, 1]))
        let wire = a.encoded() + b.encoded()
        for split in 0...wire.count {
            var decoder = WearableFrameDecoder()
            let frames = decoder.append(Data(wire.prefix(split))) + decoder.append(Data(wire.dropFirst(split)))
            XCTAssertEqual(frames, [a, b], "split \(split)")
        }
    }

    func testBadCrcNoiseAndOversizeHeaderDoNotBecomeMeasurements() {
        let frame = WearableFrame(opcode: 0x70, payload: Data([8, 1]))
        var broken = frame.encoded()
        broken[4] ^= 1
        var decoder = WearableFrameDecoder()
        let frames = decoder.append(Data([99, 0x44, 0x54, 0xff, 0xff, 0, 0, 0, 0]) + broken + frame.encoded())
        XCTAssertEqual(frames, [frame])
        XCTAssertGreaterThan(decoder.rejected, 0)
    }

    func testAnIncompleteFrameDoesNotPoisonTheNextRequestAfterTimeout() {
        var decoder = WearableFrameDecoder()
        XCTAssertTrue(decoder.append(Data([0x44, 0x54, 0, 0x20, 0, 0, 0, 0])).isEmpty)
        decoder.discardIncomplete()
        let good = WearableFrame(opcode: 0x70, payload: Data([0x10, 1]))
        XCTAssertEqual(decoder.append(good.encoded()), [good])
        XCTAssertEqual(decoder.rejected, 1)
    }

    func testFirmwareHintsAreNotCapabilitiesAndBatteryDoesNotInventPercent() {
        XCTAssertEqual(WearableGatt.reportedFirmware(for: "H02C-4190"), "99.0.100.4")
        XCTAssertEqual(WearableGatt.reportedFirmware(for: "H102C-4190"), "99.0.100.4")
        XCTAssertNil(WearableGatt.reportedFirmware(for: "耳机"))
        XCTAssertEqual(DeviceBatteryReading(gridLevel: 7, maximum: 9)?.text, "7/9 格")
        XCTAssertNil(DeviceBatteryReading(gridLevel: 10, maximum: 9))
    }
}

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
    func testAutomaticCaptureRequestsIndividualTypesAndQueuesBeforeHistoryFinishes() throws {
        XCTAssertEqual(RawCapturePolicy.types, [16, 2, 1, 512])
        for type in RawCapturePolicy.types {
            let start = try IW_RtSubscriber(serializedBytes: WearableProbeProtocol.sensorRequest(stop: false, type: type).payload)
            let stop = try IW_RtSubscriber(serializedBytes: WearableProbeProtocol.sensorRequest(stop: true, type: type).payload)
            XCTAssertEqual(start.sensor.type, type); XCTAssertEqual(stop.sensor.type, type)
            XCTAssertEqual(stop.sensor.operation, .sensorStopSync)
        }
        var report = WearableProbeReport(deviceName: "BIO synthetic", deviceKey: "synthetic")
        report.rawSensorPackets = [try packet()]
        report.rawSensorFinishedAt = .now
        XCTAssertNil(report.finishedAt)
        XCTAssertEqual(RawSensorBatchRequest.make(report).count, 1)
    }
    func testProbeUploadPreservesCamelCaseHistoryAndSharesCaptureWithRealtime() throws {
        var report = WearableProbeReport(deviceName: "BIO synthetic", deviceKey: "synthetic")
        report.observedModel = "BIO9"; report.observedFirmware = "103.0.0.11"
        report.finishedAt = .now; report.rawSensorPackets = [try packet()]
        var rri = IW_HisData()
        rri.seq = 81; rri.rri.timeStamp.dateTime.seconds = 1794390000
        rri.rri.timeStamp.timeZone = 80
        rri.rri.rawData = [800, UInt32(bitPattern: -3), 900]
        report.records = [try WearableProbeProtocol.record(rri, type: 4)]
        let upload = ProbeReportUpload(report: report)
        let data = try JSONEncoder().encode(upload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["report"]); XCTAssertNil(json["user_id"])
        XCTAssertEqual(json["capture_id"] as? String, RawSensorBatchRequest.make(report)[0].capture_id)
        XCTAssertEqual(json["report_key"] as? String, upload.report_key)
        let rows = try XCTUnwrap(json["records"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["protobufBase64"] as? String, report.records.first?.protobufBase64)
        let restored = try JSONDecoder().decode(ProbeReportUpload.self, from: data)
        XCTAssertEqual(restored.capture_id, upload.capture_id)
        XCTAssertEqual(restored.report.records.first?.protobufJSON, report.records.first?.protobufJSON)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("isi_score"))
    }
    func testCaptureOwnerIsIsolatedByServerAndStableUserID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(try RawSensorPendingStorage.claim(capture: "capture", scope: "serverA|1", base: directory))
        XCTAssertTrue(try RawSensorPendingStorage.claim(capture: "capture", scope: "serverA|1", base: directory))
        XCTAssertFalse(try RawSensorPendingStorage.claim(capture: "capture", scope: "serverA|2", base: directory))
        XCTAssertFalse(try RawSensorPendingStorage.claim(capture: "capture", scope: "serverB|1", base: directory))
    }

    func testBackgroundQueueSkipsReceiptedFilesAndKeepsAccountIsolation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "raw-queue-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        let folder = base.appendingPathComponent("raw-pending")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report = WearableProbeReport(deviceName: "BIO synthetic", deviceKey: "synthetic")
        report.finishedAt = .now; report.rawSensorPackets = [try packet()]
        let file = folder.appendingPathComponent("batch.json")
        try JSONEncoder().encode(RawSensorBatchRequest.make(report)[0]).write(to: file)
        let worker = WearableProbeWorker()
        let first = try await worker.pendingUploads(owner: "server|1", defaults: defaults, base: base)
        let item = try XCTUnwrap(first.uploads.first)
        XCTAssertEqual(first.uploads.count, 1); XCTAssertFalse(first.otherAccount)
        let body = try await worker.uploadBody(item)
        XCTAssertEqual(try JSONDecoder().decode(RawSensorBatchRequest.self, from: body).packets, report.rawSensorPackets)
        // Confirmed immutable files are skipped using metadata, without decoding
        // their contents again. A failed upload (no receipt) remains queued.
        let retry = try await worker.pendingUploads(owner: "server|1", defaults: defaults, base: base)
        XCTAssertEqual(retry.uploads.map(\.uploadID), first.uploads.map(\.uploadID))
        defaults.set(true, forKey: item.receiptKey(owner: "server|1"))
        try Data("must not be decoded again".utf8).write(to: file)
        let confirmed = try await worker.pendingUploads(owner: "server|1", defaults: defaults, base: base)
        XCTAssertTrue(confirmed.uploads.isEmpty)
        let switched = try await worker.pendingUploads(owner: "server|2", defaults: defaults, base: base)
        XCTAssertTrue(switched.uploads.isEmpty); XCTAssertTrue(switched.otherAccount)
        let otherServer = try await worker.pendingUploads(owner: "other|1", defaults: defaults, base: base)
        XCTAssertTrue(otherServer.uploads.isEmpty); XCTAssertTrue(otherServer.otherAccount)
    }

    func testLargeHistoryBackgroundQueuePreservesEveryRecordAndWireField() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "raw-history-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        let folder = base.appendingPathComponent("probe-pending")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report = WearableProbeReport(deviceName: "BIO synthetic", deviceKey: "synthetic")
        report.finishedAt = .now
        report.records = try (0..<3011).map { index in
            var value = IW_HisData(); value.seq = UInt32(index)
            value.rri.timeStamp.dateTime.seconds = 1794390000; value.rri.timeStamp.timeZone = 80
            value.rri.rawData = Array(repeating: 0x03200384, count: 120)
            return try WearableProbeProtocol.record(value, type: 4)
        }
        let upload = ProbeReportUpload(report: report)
        try JSONEncoder().encode(upload).write(to: folder.appendingPathComponent("history.json"))
        let worker = WearableProbeWorker()
        let start = Date.now
        let pending = try await worker.pendingUploads(owner: "server|1", defaults: defaults, base: base)
        let item = try XCTUnwrap(pending.uploads.first)
        XCTAssertEqual(item.count, 3011); XCTAssertTrue(item.history)
        let body = try await worker.uploadBody(item)
        let restored = try JSONDecoder().decode(ProbeReportUpload.self, from: body)
        XCTAssertEqual(restored.report.records.map(\.protobufBase64), report.records.map(\.protobufBase64))
        XCTAssertEqual(restored.report.records.map(\.sequence), Array(0..<3011).map(UInt32.init))
        XCTAssertEqual(restored.report_key, upload.report_key)
        defaults.set(true, forKey: item.receiptKey(owner: "server|1"))
        let confirmed = try await worker.pendingUploads(owner: "server|1", defaults: defaults, base: base)
        XCTAssertTrue(confirmed.uploads.isEmpty)
        print("Background history queue: \(body.count) bytes / 3011 records, verified in \(Date.now.timeIntervalSince(start))s")
    }
}

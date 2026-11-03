import XCTest
@testable import sleeptongshu

@MainActor
final class DeviceValidationTests: XCTestCase {
    func testInventoryPreservesUnknownFieldsAndPlaceholdersWithoutExportingRetiredMetricsOrCredentials() throws {
        let fields = ValidationInventory.collect([
            ["history": ["heartValue": 0, "ppgs": [60, 62, 255], "unknownField": 17, "device_password": "private",
                         "bloodGlucose": 6.5, "HDL": 1.2, "deviceAddress": "private"]],
            ["history": ["heartValue": 64, "ppgs": [61, 63]]]
        ])
        let heart = try XCTUnwrap(fields.first { $0.path == "history.heartValue" })
        XCTAssertEqual(heart.minimum, 0)
        XCTAssertEqual(heart.maximum, 64)
        XCTAssertEqual(heart.occurrences, 2)
        XCTAssertTrue(fields.contains { $0.path == "history.unknownField" })
        let ppg = try XCTUnwrap(fields.first { $0.path == "history.ppgs" })
        XCTAssertEqual(ppg.values, 5)
        XCTAssertTrue(ppg.meaning.contains("不能证明"))
        let encoded = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        for secret in ["private", "bloodGlucose", "HDL", "deviceAddress", "device_password"] {
            XCTAssertFalse(encoded.contains(secret))
        }
    }

    func testRRBlocksDeduplicatePreserveBytesAndDoNotInventMilliseconds() throws {
        let store = DeviceValidationStore(directory: nil)
        store.begin(device: UUID())
        let snapshot: [String: Any] = ["kind": "rr", "date": "2026-01-01", "time": "00:00:00", "number": 1,
                                       "raw": Data([1, 2]), "converted": Data([0x64, 0, 0x20, 3])]
        store.receive(snapshot)
        store.receive(snapshot)
        store.receive(["kind": "rr", "number": 2, "raw": Data()])
        let report = try XCTUnwrap(store.report)
        XCTAssertEqual(report.blocks.count, 1)
        XCTAssertEqual(report.blocks[0].littleEndianValues, [100, 800])
        XCTAssertEqual(report.blocks[0].raw, Data([1, 2]))
        XCTAssertTrue(report.summary.contains("不标为毫秒"))
        XCTAssertTrue(report.conclusion.contains("候选信号"))
        let malformed = ValidationSignalBlock(kind: "rr", date: "", time: "", number: 1, raw: Data(), converted: Data([1]), receivedAt: .now)
        XCTAssertTrue(malformed.littleEndianValues.isEmpty)
    }

    func testCollectionLimitsAndNonFiniteWaveValuesDoNotCreateFakeSignals() throws {
        let store = DeviceValidationStore(directory: nil)
        store.begin(device: UUID())
        store.receive(["kind": "wave", "values": [Double.nan, Double.infinity]])
        XCTAssertEqual(store.report?.waveSampleCount, 0)
        XCTAssertFalse(try XCTUnwrap(store.report?.waveStatus).contains("已收到"))
        XCTAssertTrue(try XCTUnwrap(store.report?.conclusion).contains("尚未取得"))
        store.receive(["kind": "rr", "raw": Data(repeating: 1, count: 32769)])
        XCTAssertTrue(store.report?.blocks.isEmpty ?? false)
        XCTAssertEqual(store.report?.captureLimitReached, true)
        store.receive(["kind": "wave", "values": Array(repeating: 3, count: 1000)])
        XCTAssertEqual(store.report?.wavePreview.count, 600)
        XCTAssertEqual(store.report?.waveSampleCount, 1000)
    }

    func testPartialReportSurvivesRestartAndNextDeviceDoesNotInheritSignals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceValidationStore(directory: directory)
        let firstDevice = UUID()
        store.begin(device: firstDevice, services: ["180F": ["2A19"]])
        store.receive(["kind": "rr", "raw": Data([1, 2]), "number": 1])
        XCTAssertTrue(store.save(force: true))
        let restored = DeviceValidationStore(directory: directory)
        XCTAssertEqual(restored.report?.blocks.count, 1)
        XCTAssertTrue(try XCTUnwrap(restored.report?.status).contains("中断"))
        XCTAssertNotNil(restored.report?.finishedAt)
        XCTAssertEqual(restored.report?.bluetoothServices["180F"], ["2A19"])
        restored.begin(device: UUID())
        XCTAssertTrue(restored.report?.blocks.isEmpty ?? false)
        XCTAssertNotEqual(restored.report?.deviceKey, WearableVital.deviceKey(firstDevice.uuidString))
        XCTAssertFalse(String(decoding: try Data(contentsOf: XCTUnwrap(store.exportURL)), as: UTF8.self).contains(firstDevice.uuidString))
    }

    func testFinishedReportKeepsValidatedHistoryAndRejectsLateSignalCallbacks() throws {
        let store = DeviceValidationStore(directory: nil)
        store.begin(device: UUID())
        store.receive(["kind": "state", "rr": "等待回包超时，尚不能确定是否支持"])
        let vital = WearableVital(device: "test", deviceLabel: "测试设备", date: .now, kind: .heart, value: 64, origin: "设备历史")
        store.finish(download: VeepooDecodedSleep(records: [], rejected: 1, vitals: [vital]), status: "验证结束")
        store.receive(["kind": "rr", "raw": Data([9]), "number": 1])
        XCTAssertEqual(store.report?.vitals, [vital])
        XCTAssertEqual(store.report?.rejectedSleeps, 1)
        XCTAssertEqual(store.report?.blocks.count, 0)
        XCTAssertTrue(try XCTUnwrap(store.report?.rrStatus).contains("尚不能确定"))
    }

    func testLargeHistoryReportIsExplicitlyMarkedPartialWithoutMutatingDownload() throws {
        let store = DeviceValidationStore(directory: nil)
        store.begin(device: UUID())
        let samples = (0..<3001).map { index in
            WearableVital(device: "test", deviceLabel: "测试设备", date: Date(timeIntervalSince1970: Double(index)),
                          kind: .heart, value: 64, origin: "设备历史")
        }
        let download = VeepooDecodedSleep(records: [], rejected: 0, vitals: samples)
        store.finish(download: download, status: "验证结束")
        XCTAssertEqual(download.vitals.count, 3001)
        XCTAssertEqual(store.report?.vitals.count, 3000)
        XCTAssertEqual(store.report?.captureLimitReached, true)
    }
}

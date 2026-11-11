import XCTest
@testable import sleeptongshu

@MainActor final class DeviceStepsTests: XCTestCase {
    private let first = StepDates.date("2026-11-10")!.addingTimeInterval(12 * 3600)
    private func day(_ count: Int, device: String = "test-device", date: String = "2026-11-10", offset: Double = 0) -> DeviceStepDay {
        DeviceStepDay(device: device, deviceName: "测试设备", day: date, steps: count, readAt: first.addingTimeInterval(offset), dayBasis: "测试日期")
    }
    private func report() -> WearableProbeReport {
        var value = WearableProbeReport(startedAt: first, deviceName: "测试设备", deviceKey: "test-device")
        value.observedModel = "BIO9"; value.observedFirmware = "103.0.0.11"
        value.currentSteps = 4221; value.finishedAt = first.addingTimeInterval(120)
        return value
    }

    func testRepeatedTotalsReplaceInsteadOfAddingAndOlderResponsesCannotOverwrite() {
        let store = DeviceStepsStore(url: nil)
        store.merge([day(4000)]); store.merge([day(4000)])
        XCTAssertEqual(store.rows.count, 1); XCTAssertEqual(store.latest?.steps, 4000)
        store.merge([day(4221, offset: 60)]); store.merge([day(1000, offset: -60)])
        XCTAssertEqual(store.latest?.steps, 4221)
        store.merge([day(4100, offset: 120)]) // Corrected totals may decrease.
        XCTAssertEqual(store.latest?.steps, 4100)
    }

    func testDaysDevicesRealZeroAndMissingDaysRemainDistinct() {
        let store = DeviceStepsStore(url: nil)
        store.merge([day(4000), day(0, date: "2026-11-11", offset: 86400), day(9999, device: "other")])
        let selected = store.days(for: "test-device")
        let range = StepRange(start: "2026-11-09", end: "2026-11-11")
        let stats = StepStatistics(values: Dictionary(uniqueKeysWithValues: selected.map { ($0.day, $0.steps) }), range: range)
        XCTAssertEqual(store.devices.count, 2); XCTAssertEqual(stats.total, 4000)
        XCTAssertEqual(stats.recordedDays, 2); XCTAssertEqual(stats.zeroDays, 1)
        XCTAssertEqual(stats.missingDays, 1); XCTAssertEqual(stats.average, 2000)
    }

    func testPersistenceRestoresDateInsteadOfRelabelingItAsToday() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("steps.json")
        let store = DeviceStepsStore(url: url); store.merge([day(4221)])
        let restored = DeviceStepsStore(url: url)
        XCTAssertEqual(restored.rows, store.rows); XCTAssertEqual(restored.latest?.day, "2026-11-10")
    }

    func testInvalidCountsDatesAndIdentitiesDoNotEnterStatistics() {
        let store = DeviceStepsStore(url: nil)
        store.merge([day(-1), day(200001), day(10, device: ""), day(50, date: "2026-02-30")])
        XCTAssertTrue(store.rows.isEmpty)
    }

    func testOldBIOReportRecoversItsReadDateAndDoesNotNeedHealthKit() throws {
        let value = try XCTUnwrap(DeviceStepDay.read(report()))
        XCTAssertEqual(value.steps, 4221); XCTAssertEqual(value.day, "2026-11-10")
        XCTAssertEqual(value.readAt, first)
        var unknown = report(); unknown.observedModel = "unknown"
        XCTAssertNil(DeviceStepDay.read(unknown))
    }

    func testMidnightReportsNeedExactTimestampAndExplicitZeroIsPreserved() throws {
        var value = report()
        value.startedAt = StepDates.date("2026-11-11")!.addingTimeInterval(-30)
        value.finishedAt = value.startedAt.addingTimeInterval(120)
        XCTAssertNil(DeviceStepDay.read(value))
        value.currentStepsReadAt = value.startedAt.addingTimeInterval(60)
        value.currentSteps = 0
        XCTAssertEqual(try XCTUnwrap(DeviceStepDay.read(value)).day, "2026-11-11")
        XCTAssertEqual(DeviceStepDay.read(value)?.steps, 0)
        value.currentSteps = nil
        XCTAssertNil(DeviceStepDay.read(value))
    }

    func testPartialMinutePacketsNeverBecomeDailyTotals() {
        var value = report(); value.currentSteps = nil
        value.records = [.init(type: 0, sequence: 0, receivedAt: first, protobufJSON: "{}", steps: 500)]
        XCTAssertNil(DeviceStepDay.read(value))
    }

    func testReportTimestampIsOptionalForBackwardCompatibility() throws {
        let data = try JSONEncoder().encode(report())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("currentStepsReadAt"))
        XCTAssertEqual(try JSONDecoder().decode(WearableProbeReport.self, from: data).currentSteps, 4221)
    }

    func testDeviceSleepWinsEvenAfterAnEmptyHealthReadAndOtherRecordsStayAccessible() throws {
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.source = .band
        let band = SleepRecord(payload)
        payload.id = UUID(); payload.source = .healthKit
        let health = SleepRecord(payload)
        payload.id = UUID(); payload.source = .manual
        let manual = SleepRecord(payload)
        XCTAssertEqual(SleepDashboardSource.preferred(records: [band, health, manual], hasDeviceData: false, hasReadHealth: true), .device)
        XCTAssertTrue(SleepDashboardSource.device.includes(band))
        XCTAssertFalse(SleepDashboardSource.device.includes(health))
        XCTAssertTrue(SleepDashboardSource.health.includes(health))
        XCTAssertTrue(SleepDashboardSource.all.includes(manual))
        XCTAssertEqual(SleepDashboardSource.preferred(records: [], hasDeviceData: true, hasReadHealth: true), .device)
        XCTAssertEqual(SleepDashboardSource.preferred(records: [], hasDeviceData: false, hasReadHealth: true), .health)
        XCTAssertEqual(SleepDashboardSource.preferred(records: [], hasDeviceData: false, hasReadHealth: false), .all)
    }
}

import XCTest
import SwiftData
import SwiftProtobuf
@testable import sleeptongshu

@MainActor final class BIONightTests: XCTestCase {
    private func stamp(_ text: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = StepDates.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: text)!
    }
    private func fixture() -> (WearableProbeReport, WearableDecodedHistory) {
        let a = stamp("2026-11-10 23:00"), b = stamp("2026-11-11 07:00")
        var report = WearableProbeReport(deviceName: "BIO · 测试", deviceKey: "test-bio")
        report.observedModel = "BIO9"; report.observedFirmware = "103.0.0.11"; report.finishedAt = b.addingTimeInterval(3600)
        let vitals = [WearableVital(device: "test-bio", deviceLabel: "BIO · 测试", date: a, kind: .heart, value: 60, origin: "设备历史"),
            WearableVital(device: "test-bio", deviceLabel: "BIO · 测试", date: b, kind: .heart, value: 70, origin: "设备历史"),
            WearableVital(device: "test-bio", deviceLabel: "BIO · 测试", date: b, kind: .oxygen, value: 98, origin: "设备历史")]
        return (report, WearableDecodedHistory(vitals: vitals, rows: [WearableHealthRow(sequence: 1, date: a, hasSleepInput: true), WearableHealthRow(sequence: 2, date: b, hasSleepInput: true)], skippedTimes: 0))
    }
    func testNightObservationUsesEndDayButNeverInventsSleepStagesDurationOrAverage() throws {
        let (report, history) = fixture()
        let payload = try XCTUnwrap(BIONight.payloads(report: report, history: history).first)
        let record = SleepRecord(payload); try payload.validate()
        XCTAssertEqual(record.metadata?.bioNight?.endDay, "2026-11-11")
        XCTAssertEqual(record.metadata?.bioNight?.mean(.heart), 65)
        XCTAssertEqual(record.metadata?.bioNight?.mean(.oxygen), 98)
        XCTAssertFalse(record.hasSleepDuration); XCTAssertEqual(record.asleepMinutes, 0)
        XCTAssertNil(record.sleepOnset); XCTAssertNil(record.awakenings); XCTAssertNil(record.score)
        XCTAssertNil(record.efficiency); XCTAssertNil(record.averageSpO2)
        XCTAssertNil(TrendMetric.duration.value(record)); XCTAssertTrue(record.segments.isEmpty)
        XCTAssertNil(BIONight.endDay(for: stamp("2026-11-11 14:00")))
    }
    func testRepeatedPartialHistoryMergesKeepsNotesAndDoesNotDuplicateNights() throws {
        var (report, history) = fixture()
        let container = try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let first = BIONight.payloads(report: report, history: history)
        try BIONight.save(first, in: context)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<SleepRecord>()).first); saved.note = "我的笔记"; try context.save()
        history.vitals = [WearableVital(device: "test-bio", deviceLabel: "测试", date: stamp("2026-11-11 05:00"), kind: .oxygen, value: 96, origin: "设备历史")]
        report.finishedAt = report.finishedAt!.addingTimeInterval(60)
        try BIONight.save(BIONight.payloads(report: report, history: history), in: context)
        try BIONight.save(first, in: context) // Older response cannot replace newer.
        let rows = try context.fetch(FetchDescriptor<SleepRecord>())
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].note, "我的笔记")
        XCTAssertEqual(rows[0].metadata?.bioNight?.samples.count, 4)
    }
    func testUnknownDeviceAndIncompleteReportDoNotCreateNightRecords() {
        var (report, history) = fixture(); report.observedModel = "unknown"
        XCTAssertTrue(BIONight.payloads(report: report, history: history).isEmpty)
        report.observedModel = "BIO9"; report.finishedAt = nil
        XCTAssertTrue(BIONight.payloads(report: report, history: history).isEmpty)
    }
    func testOnlyValidatedVendorSectionsProduceStagesAndSleepMatchedVitals() throws {
        let (report, history) = fixture()
        let observation = try XCTUnwrap(BIONight.payloads(report: report, history: history).first)
        let result = BIOSleepAlgorithmResult(completed: 1, start_time: "2026-11-10 23:00", end_time: "2026-11-11 07:01", sections: [
            .init(start: "2026-11-10 23:00", end: "2026-11-11 01:00", type: 3),
            .init(start: "2026-11-11 01:00", end: "2026-11-11 03:00", type: 4),
            .init(start: "2026-11-11 03:00", end: "2026-11-11 03:10", type: 6),
            .init(start: "2026-11-11 03:10", end: "2026-11-11 07:01", type: 7)])
        let record = SleepRecord(try BIOSleepResultAdapter.payload(result, observation: observation))
        XCTAssertTrue(record.hasSleepDuration); XCTAssertEqual(record.minutes(.deep), 120)
        XCTAssertEqual(record.minutes(.light), 120); XCTAssertEqual(record.minutes(.rem), 231)
        XCTAssertEqual(record.awakenings, 1); XCTAssertEqual(record.averageSpO2, 98)
        XCTAssertEqual(record.averageHeartRate, 65); XCTAssertNil(record.score)
        var bad = result; bad.sections[1].type = 999
        XCTAssertThrowsError(try BIOSleepResultAdapter.payload(bad, observation: observation))
        bad = result; bad.sections[1].start = "2026-11-11 00:30"
        XCTAssertThrowsError(try BIOSleepResultAdapter.payload(bad, observation: observation))
        var partial = result; partial.sections[1].start = "2026-11-11 01:10"
        let incomplete = SleepRecord(try BIOSleepResultAdapter.payload(partial, observation: observation))
        XCTAssertNil(incomplete.awakeMinutes); XCTAssertNil(incomplete.awakenings); XCTAssertNil(incomplete.efficiency)
    }
    func testAlgorithmPreprocessorPreservesSignedRRIAndRequiresRealDeviceID() throws {
        var report = WearableProbeReport(deviceName: "测试", deviceKey: "test")
        report.observedModel = "BIO9"; report.observedFirmware = "103.0.0.11"; report.finishedAt = stamp("2026-11-11 10:00")
        for (index, text) in ["2026-11-10 23:59", "2026-11-11 00:01"].enumerated() {
            var value = IW_HisData(); value.seq = UInt32(index)
            value.health.timeStamp.dateTime.seconds = UInt32(stamp(text).timeIntervalSince1970 + 28800)
            value.health.timeStamp.timeZone = 80; value.health.sleepData.sleepData = [1,2,3,4,5]
            value.health.sleepData.shutDown = false; value.health.sleepData.charge = false
            report.records.append(try WearableProbeProtocol.record(value, type: 0))
        }
        var rri = IW_HisData(); rri.seq = 10
        rri.rri.timeStamp.dateTime.seconds = UInt32(stamp("2026-11-11 00:01").timeIntervalSince1970 + 28800); rri.rri.timeStamp.timeZone = 80
        rri.rri.rawData = [0xfffd0320]; report.records.append(try WearableProbeProtocol.record(rri, type: 4))
        XCTAssertTrue(try BIOSleepAlgorithmRequest.make(report).isEmpty)
        report.algorithmDeviceID = "AABBCCDDEEFF"
        let request = try XCTUnwrap(BIOSleepAlgorithmRequest.make(report).last)
        XCTAssertEqual(request.recordDate, 20261111); XCTAssertEqual(request.nextDayRri, [-3,800])
        let rows = try JSONSerialization.jsonObject(with: Data(request.nextDay.utf8)) as! [[String: Any]]
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0]["T"] as? [Int], [0,1])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(request), as: UTF8.self).contains("password"))
    }
    func testRealBIOPrivateReplayOnlyIfAvailableNeverPrintedOrUploaded() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("work/bio-fixed-live-private.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Private hardware replay unavailable") }
        let report = try JSONDecoder().decode(WearableProbeReport.self, from: Data(contentsOf: url))
        let history = WearableHistoryDecoder.decode(report)
        let nights = BIONight.payloads(report: report, history: history)
        XCTAssertFalse(nights.isEmpty)
        for night in nights { try night.validate(); XCTAssertFalse(SleepRecord(night).hasSleepDuration); XCTAssertNil(SleepRecord(night).averageSpO2) }
    }
}

import XCTest
@testable import sleeptongshu

final class VeepooSleepTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func normal(_ line: String = "0120") -> [String: Any] {
        ["format": "normal", "start": "2026/10/26 22:00", "end": "2026/10/26 22:20", "line": line]
    }
    private func accurate(start: String, end: String, previous: Int = 0, next: Int = 0) -> [String: Any] {
        ["format": "accurate", "start": start, "end": end, "pointSeconds": "60", "previous": previous, "next": next,
         "points": [["index": 0, "type": 0], ["index": 1, "type": 2]]]
    }
    private func decode(_ rows: [[String: Any]], vitals: [[String: Any]] = [], device: String = "synthetic-ring") throws -> VeepooDecodedSleep {
        try VeepooSleepDecoder.decode(["deviceID": device, "sleeps": rows, "vitals": vitals], calendar: calendar)
    }

    func testNormalSleepDoesNotInventREMOrVitals() throws {
        let payload = try XCTUnwrap(decode([normal()]).records.first)
        try payload.validate()
        let record = SleepRecord(payload)
        XCTAssertEqual(record.asleepMinutes, 15)
        XCTAssertEqual(record.minutes(.light), 10)
        XCTAssertEqual(record.minutes(.deep), 5)
        XCTAssertEqual(record.minutes(.awake), 5)
        XCTAssertEqual(record.minutes(.rem), 0)
        XCTAssertNil(record.averageHeartRate)
        XCTAssertNil(record.averageSpO2)
        XCTAssertNil(record.averageRespiratoryRate)
        XCTAssertEqual(record.source, .band)
    }

    func testNewRingWithOnlyPlaceholderWindowsDoesNotCreateSleep() throws {
        let result = try decode([], vitals: [["time": "2026-10-27 00:00", "heart": 0, "oxygen": 0, "respiration": 255]])
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.rejected, 0)
    }

    func testVitalsExcludeAwakeDaytimePlaceholdersAndDuplicates() throws {
        let vitals: [[String: Any]] = [
            ["time": "2026-10-26 22:02", "heart": 60, "oxygen": 98, "respiration": 12],
            ["time": "2026-10-26 22:02", "heart": 60],
            ["time": "2026-10-26 22:03", "heart": 80, "oxygen": 96, "respiration": 14],
            ["time": "2026-10-26 22:07", "heart": 0, "oxygen": 255, "respiration": 255],
            ["time": "2026-10-26 22:12", "heart": 200, "oxygen": 80, "respiration": 40],
            ["time": "2026-10-26 12:00", "heart": 180, "oxygen": 85, "respiration": 40],
        ]
        let payload = try XCTUnwrap(decode([normal()], vitals: vitals).records.first)
        XCTAssertEqual(payload.heartSamples.count, 2)
        XCTAssertEqual(payload.averageHeartRate, 70)
        XCTAssertEqual(payload.averageSpO2, 97)
        XCTAssertEqual(payload.averageRespiratoryRate, 13)
    }

    func testAccurateSleepPreservesMissingAndUnknownStages() throws {
        let row: [String: Any] = ["format": "accurate", "start": "2026-10-27 00:00", "end": "2026-10-27 00:05", "pointSeconds": 60,
            "points": [["index": 0, "type": 0], ["index": 2, "type": 2], ["index": 3, "type": 3], ["index": 4, "type": 7]]]
        let record = try SleepRecord(XCTUnwrap(decode([row]).records.first))
        XCTAssertEqual(record.minutes(.unobserved), 2)
        XCTAssertEqual(record.minutes(.rem), 1)
        XCTAssertEqual(record.minutes(.awake), 1)
        XCTAssertNil(record.efficiency)
        XCTAssertNil(record.deepShare)
    }

    func testTruncatedCurveLeavesGapInsteadOfExtendingSleep() throws {
        let record = try SleepRecord(XCTUnwrap(decode([normal("01")]).records.first))
        XCTAssertEqual(record.asleepMinutes, 10)
        XCTAssertEqual(record.minutes(.unobserved), 10)
        XCTAssertNil(record.efficiency)
    }

    func testDuplicateSyncHasStableIDsAndDevicesStaySeparate() throws {
        let first = try XCTUnwrap(decode([normal()]).records.first)
        let again = try XCTUnwrap(decode([normal(), normal()]).records.first)
        let other = try XCTUnwrap(decode([normal()], device: "other-synthetic-ring").records.first)
        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(try decode([normal(), normal()]).records.count, 1)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertFalse(first.metadata?.externalID?.contains("synthetic-ring") ?? true)
    }

    func testCrossMidnightFragmentsRequireMatchingFlagsAndContinuity() throws {
        let first = accurate(start: "2026-10-26 23:58", end: "2026-10-27 00:00", next: 1)
        let second = accurate(start: "2026-10-27 00:00", end: "2026-10-27 00:02", previous: 1)
        let complete = try decode([second, first])
        XCTAssertEqual(complete.records.count, 1)
        XCTAssertEqual(complete.records.first?.end.timeIntervalSince(complete.records.first!.start), 240)
        XCTAssertEqual(try decode([first]).records.count, 0)
        XCTAssertEqual(try decode([second]).records.count, 0)
        try complete.records.first?.validate()
    }

    func testMalformedDateUnknownNormalStageAndDuplicateMinuteAreRejected() throws {
        var badDate = normal()
        badDate["start"] = "2026/02/30 22:00"
        var duplicate = accurate(start: "2026-10-27 00:00", end: "2026-10-27 00:02")
        duplicate["points"] = [["index": 0, "type": 0], ["index": 0, "type": 2]]
        let result = try decode([badDate, normal("01F0"), duplicate])
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.rejected, 3)
    }
}

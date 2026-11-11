import XCTest
import SwiftProtobuf
@testable import sleeptongshu

final class WearableHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1794376800)
    private func report(_ json: String) throws -> WearableProbeReport {
        let value = try IW_HisData(jsonString: json)
        var report = WearableProbeReport(deviceName: "BIO · 测试", deviceKey: "synthetic-device")
        report.observedModel = "BIO9"; report.observedFirmware = "103.0.0.11"
        report.records = [try WearableProbeProtocol.record(value, type: 0)]
        return report
    }
    private let complete = """
    {"seq":1,"health":{"timeStamp":{"dateTime":{"seconds":1794398520},"timeZone":80},
    "hrData":{"minBpm":60,"maxBpm":70,"avgBpm":65},
    "bxoyData":{"minOxy":98,"maxOxy":98,"agvOxy":98},
    "bpData":{"sbp":102,"dbp":65},
    "hrvData":{"SDNN":1340,"RMSSD":270,"PNN50":200,"MEAN":7960,"fatigue":58},
    "pedoData":{"type":1,"state":0,"calorie":0,"step":0,"distance":0}}}
    """

    func testBIOBatteryPercentIncludesLowValuesWithoutChangingLegacyGrids() {
        for value: UInt32 in [0, 1, 7, 9, 42, 100] {
            let reading = WearableHistoryDecoder.battery(value, model: "BIO9", firmware: "103.0.0.11")
            XCTAssertEqual(reading?.text, "\(value)%")
        }
        XCTAssertNil(WearableHistoryDecoder.battery(101, model: "BIO9", firmware: "103.0.0.11"))
        XCTAssertEqual(WearableHistoryDecoder.battery(7, model: "older", firmware: "1")?.text, "7/9 格")
        XCTAssertNil(WearableHistoryDecoder.battery(100, model: nil, firmware: nil))
    }

    func testDocumentedLocalClockAndScaledHRVAreUsedForSavedVitals() throws {
        let report = try report(complete)
        let decoded = WearableHistoryDecoder.decode(report, now: now)
        let row = try XCTUnwrap(decoded.rows.first)
        XCTAssertEqual(row.date.timeIntervalSince1970, 1794398520 - 28800)
        XCTAssertEqual(row.sdnn, 134); XCTAssertEqual(row.rmssd, 27)
        XCTAssertEqual(row.stress, 42); XCTAssertEqual(row.steps, 0)
        XCTAssertEqual(Set(decoded.vitals.map(\.kind)), [.heart, .oxygen, .systolic, .diastolic, .hrv, .stress])
        XCTAssertEqual(decoded.vitals.first(where: { $0.kind == .hrv })?.origin, "设备历史 · SDNN（毫秒）")
    }

    func testMissingSentinelInvalidPressureAndAbsentBloodOxygenNeverBecomeValues() throws {
        let json = """
        {"seq":2,"health":{"timeStamp":{"dateTime":{"seconds":1794398520},"timeZone":80},
        "hrvData":{"SDNN":-1000,"RMSSD":-1000,"PNN50":-1000,"MEAN":-1000,"fatigue":-1000},
        "hrData":{"minBpm":0,"maxBpm":255,"avgBpm":255},"bpData":{"sbp":60,"dbp":90}}}
        """
        let decoded = WearableHistoryDecoder.decode(try report(json), now: now)
        XCTAssertTrue(decoded.vitals.isEmpty)
        XCTAssertNil(decoded.rows.first?.sdnn); XCTAssertNil(decoded.rows.first?.stress)
        XCTAssertNil(decoded.rows.first?.oxygen); XCTAssertNil(decoded.rows.first?.steps)
    }

    func testUnknownTimezoneOrModelAndFutureClockRemainInReportWithoutImport() throws {
        var report = try report(complete.replacingOccurrences(of: "\"timeZone\":80", with: "\"timeZone\":90"))
        var decoded = WearableHistoryDecoder.decode(report, now: now)
        XCTAssertTrue(decoded.vitals.isEmpty); XCTAssertEqual(decoded.skippedTimes, 1)
        report = try self.report(complete); report.observedModel = "Unknown"
        XCTAssertTrue(WearableHistoryDecoder.decode(report, now: now).vitals.isEmpty)
        report = try self.report(complete)
        decoded = WearableHistoryDecoder.decode(report, now: now.addingTimeInterval(-86400))
        XCTAssertEqual(decoded.skippedTimes, 1)
    }

    @MainActor
    func testRepeatedHistoryAndChangingDevicesPreserveIdentity() throws {
        let one = try report(complete)
        var two = one; two.deviceKey = "another-device"
        let store = WearableVitalsStore(url: nil)
        let a = WearableHistoryDecoder.decode(one, now: now).vitals
        XCTAssertEqual(try store.merge(a), 6)
        XCTAssertEqual(try store.merge(a), 0)
        XCTAssertEqual(try store.merge(WearableHistoryDecoder.decode(two, now: now).vitals), 6)
        XCTAssertEqual(store.samples.count, 12)
    }

    func testRangesCoverOlderBlocksBoundMemoryAndHandleMaximumSequence() {
        func index(_ start: UInt32, _ end: UInt32) -> IW_HisIndex {
            var index = IW_HisIndex(); index.startSeq = start; index.endSeq = end; return index
        }
        let ranges = WearableProbeProtocol.sampleRanges([index(0, 299), index(300, 999)], limit: 800)
        let unique = Set(ranges.flatMap { Array($0) })
        XCTAssertEqual(unique, Set(UInt32(200)...UInt32(999)))
        XCTAssertTrue(ranges.allSatisfy { UInt64($0.upperBound) - UInt64($0.lowerBound) < 240 })
        let end = WearableProbeProtocol.sampleRanges([index(UInt32.max - 5, UInt32.max)], limit: 100)
        XCTAssertEqual(end, [(UInt32.max - 5)...UInt32.max])
        XCTAssertTrue(WearableProbeProtocol.sampleRanges([index(5, 1)], limit: 5).isEmpty)
        XCTAssertTrue(WearableProbeProtocol.sampleRanges([index(0, 9)], limit: 0).isEmpty)
    }

    func testOldReportWithMisnamedBatteryFieldStillDecodes() throws {
        var report = try report(complete)
        report.batteryLevel0To9 = 100
        let decoded = try JSONDecoder().decode(WearableProbeReport.self, from: JSONEncoder().encode(report))
        XCTAssertNil(decoded.batteryRaw)
        XCTAssertEqual(WearableHistoryDecoder.battery(try XCTUnwrap(decoded.batteryLevel0To9), model: decoded.observedModel, firmware: decoded.observedFirmware)?.text, "100%")
    }

    func testLocalPrivateReportWhenAvailable() throws {
        // Optional local replay: no personal report or raw samples are committed to the repo.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("work/bio-latest-1359-private.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("No private local BIO report") }
        let report = try JSONDecoder().decode(WearableProbeReport.self, from: Data(contentsOf: url))
        let decoded = WearableHistoryDecoder.decode(report, now: try XCTUnwrap(report.finishedAt))
        XCTAssertEqual(report.observedModel, "BIO9")
        XCTAssertEqual(WearableHistoryDecoder.battery(try XCTUnwrap(report.batteryLevel0To9), model: report.observedModel, firmware: report.observedFirmware)?.text, "100%")
        XCTAssertGreaterThan(decoded.vitals.count, 10)
        XCTAssertEqual(decoded.skippedTimes, 0)
        XCTAssertTrue(decoded.vitals.contains { $0.kind == .oxygen && $0.value == 98 })
        XCTAssertTrue(decoded.vitals.contains { $0.kind == .hrv && $0.value == 134 })
    }
}

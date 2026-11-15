import XCTest
@testable import sleeptongshu

@MainActor final class BIONightPresentationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func sample(_ seconds: Double, kind: VitalKind = .heart, value: Double = 60) -> WearableVital {
        WearableVital(device: "synthetic", deviceLabel: "界面性能测试示例", date: start.addingTimeInterval(seconds), kind: kind, value: value, origin: "synthetic")
    }
    private func payload() -> SleepPayload {
        SleepPayload(id: UUID(), start: start, end: start.addingTimeInterval(240), source: .band,
            segments: [.init(stage: .deep, start: start, end: start.addingTimeInterval(60)),
                       .init(stage: .awake, start: start.addingTimeInterval(60), end: start.addingTimeInterval(120)),
                       .init(stage: .unobserved, start: start.addingTimeInterval(120), end: start.addingTimeInterval(180)),
                       .init(stage: .rem, start: start.addingTimeInterval(180), end: start.addingTimeInterval(240))],
            heartSamples: [], note: "",
            metadata: SleepMetadata(bioNight: BIONight(device: "synthetic", endDay: "2026-09-22", readAt: start,
                samples: [sample(240, value: 100), sample(180, value: 80), sample(120, value: 110), sample(60, value: 100), sample(0)], sleepInputMinutes: 4)))
    }
    func testSummaryExcludesAwakeMissingAndEndBoundaryWithoutInterpolating() {
        let record = SleepRecord(payload())
        let summary = record.nightPresentation
        XCTAssertEqual(summary.available, [.heart])
        XCTAssertEqual(summary.series[.heart]?.count, 2)
        XCTAssertEqual(summary.series[.heart]?.mean, 70)
        XCTAssertEqual(summary.series[.heart]?.samples.map(\.date), [start,start.addingTimeInterval(180)])
        XCTAssertNil(summary.series[.oxygen])
        XCTAssertEqual(record.metadata?.bioNight?.samples.count, 5)
    }
    func testObservationKeepsAllMeasurementsAndNeverCreatesStages() {
        var value = payload(); value.segments = []
        let record = SleepRecord(value)
        XCTAssertEqual(record.nightPresentation.series[.heart]?.count, 5)
        XCTAssertFalse(record.hasSleepDuration)
        XCTAssertTrue(record.segments.isEmpty)
    }
    func testCacheIsPerRecordAndInvalidatesForMetadataAndStageChanges() throws {
        let record = SleepRecord(payload())
        let first = record.nightPresentation
        XCTAssertTrue(first === record.nightPresentation)
        let other = SleepRecord(payload())
        XCTAssertFalse(first === other.nightPresentation)
        var updated = payload(); updated.metadata?.bioNight?.samples.append(sample(10, kind: .oxygen, value: 98))
        record.replace(with: updated)
        XCTAssertFalse(first === record.nightPresentation)
        XCTAssertEqual(record.nightPresentation.series[.oxygen]?.mean, 98)
        let second = record.nightPresentation
        record.segmentsData = try JSONEncoder().encode([SleepSegment(stage: .deep, start: start, end: record.end)])
        XCTAssertFalse(second === record.nightPresentation)
        XCTAssertEqual(record.nightPresentation.series[.heart]?.count, 4)
        record.metadataData = nil
        XCTAssertTrue(record.nightPresentation.available.isEmpty)
    }
    func testClockCacheUpdatesWhenRecordTimezoneChanges() throws {
        let record = SleepRecord(payload())
        var metadata = try XCTUnwrap(record.metadata)
        metadata.bioNight?.timeZoneIdentifier = "UTC"
        record.metadataData = try JSONEncoder().encode(metadata)
        let utc = record.displayClock(start)
        metadata.bioNight?.timeZoneIdentifier = "Asia/Shanghai"
        record.metadataData = try JSONEncoder().encode(metadata)
        let reference = DateFormatter(); reference.timeZone = TimeZone(identifier: "Asia/Shanghai")
        reference.locale = Locale(identifier: "en_US_POSIX"); reference.dateFormat = "HH:mm"
        XCTAssertEqual(record.displayClock(start), reference.string(from: start))
        XCTAssertNotEqual(record.displayClock(start), utc)
    }
    func testDenseNightPresentationMatchesLegacyMathAndReportsLocalTiming() throws {
        var value = payload()
        value.end = start.addingTimeInterval(8 * 3600)
        let stages: [SleepStage] = [.awake,.deep,.light,.rem]
        value.segments = (0..<96).map { index in
            let a = start.addingTimeInterval(Double(index) * 300)
            let b = start.addingTimeInterval(Double(index + 1) * 300)
            return SleepSegment(stage: stages[index % 4], start: a, end: b)
        }
        let kinds: [VitalKind] = [.heart,.oxygen,.hrv,.stress]
        value.metadata?.bioNight?.samples = (0..<4000).map { index in
            sample(Double(index) * 7, kind: kinds[index % kinds.count], value: Double(60 + index % 20))
        }
        let record = SleepRecord(value)
        let raw = try XCTUnwrap(value.metadata?.bioNight?.samples)
        let before = Date.now
        var expected: [VitalKind: Double] = [:]
        for _ in 0..<5 {
            for kind in kinds {
                // Reproduce the previous view's separate count and mean reads.
                let measured = raw.filter { sample in record.segments.contains { $0.stage.isAsleep && sample.date >= $0.start && sample.date < $0.end } }
                let values = measured.filter { $0.kind == kind }.map(\.value)
                expected[kind] = values.reduce(0,+)/Double(values.count)
            }
        }
        let old = Date.now.timeIntervalSince(before)
        let after = Date.now
        for _ in 0..<5 {
            let summary = record.nightPresentation
            for kind in kinds { XCTAssertEqual(try XCTUnwrap(summary.series[kind]?.mean), try XCTUnwrap(expected[kind]), accuracy: 0.00001) }
        }
        let cached = Date.now.timeIntervalSince(after)
        print("Synthetic 4000 readings / 96 stages / 5 summaries: previous repeated filtering \(old)s; cached summary \(cached)s")
        // Timings are diagnostic, not a flaky device-speed threshold.
        XCTAssertEqual(record.metadata?.bioNight?.samples.count, 4000)
    }
}

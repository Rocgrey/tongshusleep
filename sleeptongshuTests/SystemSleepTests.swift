import XCTest
import HealthKit
import SwiftData
@testable import sleeptongshu

@MainActor private final class TestSleepReader: HealthSleepReading {
    var isAvailable = true
    var candidates: [HealthSleepCandidate] = []
    var failure: Error?
    var calls: [(HealthSleepWindow, Bool)] = []
    func read(_ window: HealthSleepWindow, requestAccess: Bool) async throws -> HealthSleepReadResult {
        calls.append((window, requestAccess))
        if let failure { throw failure }
        return HealthSleepReadResult(candidates: candidates, sources: [])
    }
}

@MainActor final class SystemSleepTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private let start = ISO8601DateFormatter().date(from: "2026-11-08T23:00:00Z")!
    private func interval(_ stage: SleepStage, _ from: Double, _ to: Double, zone: String? = nil) -> HealthSleepInterval {
        HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(from * 3600), end: start.addingTimeInterval(to * 3600), stage: stage, timeZoneIdentifier: zone)
    }
    private func payloads(_ values: [HealthSleepInterval], source: String = "A") throws -> [SleepPayload] {
        try HealthSleepImporter.automaticRecords([HealthSleepCandidate(sourceID: source, intervals: values)], observations: [], sources: [], calendar: utc)
    }
    private func container() throws -> ModelContainer {
        try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    func testEveryKnownHKStageAndUnknownValueAreMapped() {
        for (raw, stage) in [(HKCategoryValueSleepAnalysis.inBed, SleepStage.inBed), (.asleepUnspecified, .unspecified), (.asleepCore, .light), (.asleepDeep, .deep), (.asleepREM, .rem), (.awake, .awake)] {
            XCTAssertEqual(HealthOverviewStore.stage(raw.rawValue), stage)
        }
        XCTAssertNil(HealthOverviewStore.stage(999))
    }
    func testBedOnlyDoesNotProduceDurationStagesScoreEfficiencyOrUploadDuration() throws {
        let record = SleepRecord(try XCTUnwrap(payloads([interval(.inBed, 0, 8)]).first))
        XCTAssertTrue(record.onlyInBed); XCTAssertFalse(record.hasSleepDuration); XCTAssertFalse(record.hasStages)
        XCTAssertEqual(record.asleepMinutes, 0); XCTAssertNil(record.sleepOnset)
        XCTAssertNil(record.efficiency); XCTAssertNil(record.awakenings); XCTAssertNil(record.awakeMinutes); XCTAssertNil(record.score)
        let json = try JSONSerialization.jsonObject(with: SleepUploadRequest(record: record).encoded()) as! [String: Any]
        XCTAssertNil(json["total_duration_minutes"]); XCTAssertNil(json["isi_score"]); XCTAssertNil(json["sleep_score"])
    }
    func testUnspecifiedSleepIsNotCoreAndBedOverlapIsNotAdded() throws {
        let unspecified = interval(.unspecified, 0, 8)
        let record = SleepRecord(try XCTUnwrap(payloads([unspecified, unspecified, interval(.inBed, 0, 8)]).first))
        XCTAssertEqual(record.asleepMinutes, 480); XCTAssertEqual(record.minutes(.light), 0)
        XCTAssertEqual(record.minutes(.unspecified), 480); XCTAssertFalse(record.hasStages)
        XCTAssertNil(record.deepShare); XCTAssertNil(record.score)
        XCTAssertNil(record.awakenings); XCTAssertNil(record.awakeMinutes)
        XCTAssertEqual(record.metadata?.healthSleep?.samples.count, 2)
    }
    func testFullStageCoverageHasStrictAwakeAndBedEfficiencyButNoScore() throws {
        let phases = [interval(.inBed, 0, 8), interval(.awake, 0, 0.5), interval(.light, 0.5, 2),
                      interval(.deep, 2, 4), interval(.awake, 4, 4.5), interval(.rem, 4.5, 7.5), interval(.awake, 7.5, 8)]
        let record = SleepRecord(try XCTUnwrap(payloads(phases).first))
        XCTAssertEqual(record.asleepMinutes, 390); XCTAssertEqual(record.awakenings, 1)
        XCTAssertEqual(record.awakeMinutes, 90); XCTAssertEqual(record.efficiency, 81); XCTAssertNil(record.score)
        let withoutBed = SleepRecord(try XCTUnwrap(payloads(phases.filter { $0.stage != .inBed }).first))
        XCTAssertNil(withoutBed.efficiency)
        XCTAssertEqual(withoutBed.awakenings, 1)
    }
    func testMissingAndConflictingIntervalsNeverBecomeAwakeOrInventedSleep() throws {
        let phases = [interval(.inBed, 0, 4), interval(.deep, 0, 2), interval(.rem, 1, 2), interval(.light, 2.25, 4)]
        let record = SleepRecord(try XCTUnwrap(payloads(phases).first))
        XCTAssertEqual(record.asleepMinutes, 165); XCTAssertEqual(record.minutes(.unobserved), 60)
        XCTAssertEqual(record.minutes(.inBed), 15); XCTAssertNil(record.awakenings); XCTAssertNil(record.awakeMinutes)
        XCTAssertNil(record.efficiency); XCTAssertNil(record.deepShare)
    }
    func testNightAndTwoIdenticalNapsSurviveEndDateAggregationAndBroadBedExport() throws {
        let values = [interval(.inBed, 0, 16), interval(.light, 0, 7), interval(.light, 13, 14), interval(.light, 15, 16)]
        let records = try payloads(values)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map { SleepRecord($0).asleepMinutes }, [420, 60, 60])
        XCTAssertTrue(records.allSatisfy { SleepRecord($0).efficiency == nil })
        XCTAssertEqual(Set(records.map { $0.metadata!.healthSleep!.endDay }), ["2026-11-09"])
        let observations = HealthOverviewAnalysis.sleepObservations(values, sourceID: "A", calendar: utc)
        XCTAssertEqual(HealthOverviewAnalysis.daily(observations, metric: .sleep, calendar: utc).first?.value, 9)
        let db = try container()
        try HealthSleepImporter.save(records, in: db.mainContext)
        let local = try db.mainContext.fetch(FetchDescriptor<SleepRecord>())
        for record in local { record.note = record.start.description }
        try db.mainContext.save()
        try HealthSleepImporter.save(Array(records.reversed()), in: db.mainContext)
        for record in local { XCTAssertEqual(record.note, record.start.description) }
    }
    func testOverlappingSourcesChooseDetailedRecordWithoutStitchingAndKeepSeparateNap() throws {
        let a = HealthSleepCandidate(sourceID: "A", intervals: [interval(.deep, 0, 4), interval(.light, 4, 8), interval(.light, 14, 15)])
        let b = HealthSleepCandidate(sourceID: "B", intervals: [interval(.unspecified, 0, 15)])
        let records = try HealthSleepImporter.automaticRecords([b, a], observations: [], sources: [], calendar: utc)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.metadata?.healthSleep?.origin.sourceID == "A" })
        XCTAssertEqual(records.first?.metadata?.healthSleep?.otherSourceIDs, ["B"])
    }
    func testLongBedContextDoesNotHideANapFromAnotherSource() throws {
        let a = HealthSleepCandidate(sourceID: "A", intervals: [interval(.inBed, 0, 16), interval(.light, 0, 7)])
        let b = HealthSleepCandidate(sourceID: "B", intervals: [interval(.deep, 14, 15)])
        let records = try HealthSleepImporter.automaticRecords([a, b], observations: [], sources: [], calendar: utc)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map { SleepRecord($0).asleepMinutes }.reduce(0, +), 480)
    }
    func testMissingStageIsNotDisplayedOrUploadedAsZeroAndSubminuteStagesSumOnce() throws {
        let record = SleepRecord(try XCTUnwrap(payloads([interval(.light, 0, 1.0 / 120), interval(.deep, 1.0 / 120, 2.0 / 120),
            interval(.light, 2.0 / 120, 3.0 / 120), interval(.deep, 3.0 / 120, 4.0 / 120)]).first))
        XCTAssertEqual(record.minutes(.light), 1); XCTAssertEqual(record.minutes(.deep), 1)
        XCTAssertNil(record.share(.rem))
        XCTAssertTrue(SleepMetricGuide.stage(.rem, record: record).body.contains("不推算时长或占比"))
        let json = try JSONSerialization.jsonObject(with: SleepUploadRequest(record: record).encoded()) as! [String: Any]
        XCTAssertNil(json["rem_minutes"])
    }
    func testAttributionUsesLastSleepEndInsteadOfTrailingBedContextAfterMidnight() throws {
        let record = SleepRecord(try XCTUnwrap(payloads([interval(.unspecified, 0, 0.5), interval(.inBed, -1, 2)]).first))
        XCTAssertEqual(record.metadata?.healthSleep?.endDay, "2026-11-08")
        XCTAssertEqual(record.sleepEnd, start.addingTimeInterval(1800))
        XCTAssertEqual(try SleepUploadRequest(record: record).record_date, "2026-11-08")
        XCTAssertTrue(try SleepUploadRequest(record: record).sleep_end_time.hasSuffix("23:30:00"))
    }
    func testDSTAndOriginalTimezonePreserveElapsedDurationAndEndDate() throws {
        let formatter = ISO8601DateFormatter()
        let from = formatter.date(from: "2026-11-01T00:00:00-07:00")!, to = formatter.date(from: "2026-11-01T04:00:00-08:00")!
        let value = HealthSleepInterval(id: UUID(), start: from, end: to, stage: .unspecified, timeZoneIdentifier: "America/Los_Angeles")
        let record = SleepRecord(try XCTUnwrap(payloads([value]).first))
        XCTAssertEqual(record.asleepMinutes, 300)
        XCTAssertEqual(record.displayClock(from), "00:00"); XCTAssertEqual(record.displayClock(to), "04:00")
        XCTAssertEqual(record.metadata?.healthSleep?.endDay, "2026-11-01")
        let spring = HealthSleepInterval(id: UUID(), start: formatter.date(from: "2026-03-08T00:00:00-08:00")!, end: formatter.date(from: "2026-03-08T04:00:00-07:00")!, stage: .unspecified, timeZoneIdentifier: "America/Los_Angeles")
        XCTAssertEqual(SleepRecord(try XCTUnwrap(payloads([spring]).first)).asleepMinutes, 180)
        let travel = interval(.unspecified, -1, 0, zone: "Pacific/Honolulu")
        XCTAssertEqual(try payloads([travel]).first?.metadata?.healthSleep?.endDay, "2026-11-08")
    }
    func testRangeReconciliationPreservesNotesOtherSourcesAndOutOfRangeRecords() throws {
        let db = try container(), context = db.mainContext
        let window = HealthSleepWindow(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(48 * 3600))
        let samples = [interval(.light, 0, 8)]
        var first = try XCTUnwrap(payloads(samples).first); first.note = "用户独立备注"
        try HealthSleepImporter.save([first], in: context, window: window)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<SleepRecord>()).first)
        var manual = first; manual.id = UUID(); manual.source = .manual; manual.metadata = nil
        context.insert(SleepRecord(manual))
        let outside = try XCTUnwrap(payloads([interval(.light, -240, -239)]).first)
        context.insert(SleepRecord(outside)); try context.save()
        try HealthSleepImporter.save(try payloads(samples), in: context, window: window)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SleepRecord>()).count, 3)
        try HealthSleepImporter.save([], in: context, window: window)
        XCTAssertFalse(original.isVisible); XCTAssertEqual(original.note, "用户独立备注")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SleepRecord>()).filter(\.isVisible).count, 2)
        try HealthSleepImporter.save(try payloads([interval(.light, 0, 9)]), in: context, window: window)
        XCTAssertTrue(original.isVisible); XCTAssertEqual(original.asleepMinutes, 540); XCTAssertEqual(original.note, "用户独立备注")
        try HealthSleepImporter.save(try payloads([interval(.light, 0, 9)]), in: context, window: window)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SleepRecord>()).count, 3)
        XCTAssertTrue(original.isVisible)
    }
    func testSharedStoreReads90DaysByExplicitClickAndRefreshesBothModelAndSnapshot() async throws {
        let db = try container(), reader = TestSleepReader()
        reader.candidates = [HealthSleepCandidate(sourceID: "A", intervals: [interval(.unspecified, 0, 8)])]
        let store = HealthOverviewStore(url: nil, authorizationDefaults: nil, sleepReader: reader)
        let now = start.addingTimeInterval(24 * 3600)
        await store.refreshSleepIfNeeded(in: db.mainContext, now: now)
        XCTAssertTrue(reader.calls.isEmpty)
        await store.readSystemSleep(in: db.mainContext, requestAccess: true, now: now)
        XCTAssertTrue(reader.calls[0].1)
        XCTAssertEqual(reader.calls[0].0.start, Calendar.current.date(byAdding: .day, value: -90, to: Calendar.current.startOfDay(for: now)))
        XCTAssertEqual(store.days(for: .sleep).first?.value, 8)
        XCTAssertEqual(try db.mainContext.fetch(FetchDescriptor<SleepRecord>()).filter(\.isVisible).count, 1)
        await store.refreshSleepIfNeeded(in: db.mainContext, now: now.addingTimeInterval(60))
        XCTAssertEqual(reader.calls.count, 1)
        await store.refreshSleepIfNeeded(in: db.mainContext, now: now.addingTimeInterval(901))
        XCTAssertEqual(reader.calls.count, 2); XCTAssertFalse(reader.calls[1].1)
        reader.failure = URLError(.notConnectedToInternet)
        await store.readSystemSleep(in: db.mainContext, now: now)
        XCTAssertEqual(store.snapshot?.sleepRecords?.count, 1)
        XCTAssertTrue(try XCTUnwrap(db.mainContext.fetch(FetchDescriptor<SleepRecord>()).first).isVisible)
        reader.failure = nil; reader.candidates = []
        await store.readSystemSleep(in: db.mainContext, requestAccess: true, now: now)
        XCTAssertEqual(store.sleepMessage, HealthOverviewStore.noSleepMessage)
        XCTAssertFalse(store.sleepMessage?.contains("拒绝") == true)
        XCTAssertTrue(store.days(for: .sleep).isEmpty)
        XCTAssertFalse(try XCTUnwrap(db.mainContext.fetch(FetchDescriptor<SleepRecord>()).first).isVisible)
    }
    func testUnavailableReaderDoesNotRequestPermissionOrDestroyLocalData() async throws {
        let reader = TestSleepReader(); reader.isAvailable = false
        let db = try container(), store = HealthOverviewStore(url: nil, authorizationDefaults: nil, sleepReader: reader)
        await store.readSystemSleep(in: db.mainContext, requestAccess: true)
        XCTAssertTrue(reader.calls.isEmpty); XCTAssertTrue(store.sleepMessageIsError)
    }

    func testFailedCacheWriteDoesNotCommitDeletionsOrChangedSleep() async throws {
        let db = try container(), reader = TestSleepReader()
        let original = try XCTUnwrap(payloads([interval(.light, 0, 8)]).first)
        try HealthSleepImporter.save([original], in: db.mainContext)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HealthOverviewStore(url: folder.appendingPathComponent("missing/health.json"), authorizationDefaults: nil, sleepReader: reader)
        await store.readSystemSleep(in: db.mainContext, requestAccess: true, now: start.addingTimeInterval(24 * 3600))
        XCTAssertTrue(store.sleepMessageIsError); XCTAssertNil(store.snapshot)
        let records = try db.mainContext.fetch(FetchDescriptor<SleepRecord>())
        XCTAssertEqual(records.count, 1); XCTAssertTrue(records[0].isVisible); XCTAssertEqual(records[0].asleepMinutes, 480)
    }

    func testDailyTrendSumsNapsAndDoesNotGenerateMetricsForBedOnlyOrUnspecified() throws {
        let sleeps = try payloads([interval(.light, 0, 7), interval(.unspecified, 13, 14), interval(.inBed, 17, 18)]).map(SleepRecord.init)
        let days = SleepTrendDay.summarize(sleeps)
        XCTAssertEqual(days.count, 1); XCTAssertEqual(days.first?.asleepMinutes, 480)
        XCTAssertNil(days.first?.efficiency); XCTAssertNil(days.first?.deepShare)
        XCTAssertTrue(SleepTrendDay.summarize(sleeps.filter(\.onlyInBed)).isEmpty)
    }

    func testWindowKeepsWholeCrossingEpisodeAndDoesNotReconcileOutsideEndDates() throws {
        let crossing = try payloads([interval(.light, 0, 8)])
        let db = try container()
        try HealthSleepImporter.save(crossing, in: db.mainContext)
        let window = HealthSleepWindow(start: start.addingTimeInterval(4 * 3600), end: start.addingTimeInterval(12 * 3600))
        let result = try HealthSleepImporter.automaticRecords([HealthSleepCandidate(sourceID: "A", intervals: [interval(.light, 0, 8)])], observations: [], sources: [], calendar: utc, window: window)
        XCTAssertEqual(result.first?.start, start)
        XCTAssertEqual(result.first?.end, start.addingTimeInterval(8 * 3600))
        let outside = HealthSleepWindow(start: start.addingTimeInterval(9 * 3600), end: start.addingTimeInterval(12 * 3600))
        try HealthSleepImporter.save([], in: db.mainContext, window: outside)
        XCTAssertTrue(try XCTUnwrap(db.mainContext.fetch(FetchDescriptor<SleepRecord>()).first).isVisible)
    }
}

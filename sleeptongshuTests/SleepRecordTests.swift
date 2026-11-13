import XCTest
import SwiftData
@testable import sleeptongshu

@MainActor
final class SleepRecordTests: XCTestCase {
    func testDemoTimelineCoversWholeNightAndTotalsMatch() throws {
        let samples = SampleSleepRecords.makeMonth(now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(samples.count, 30)
        for record in samples {
            try record.payload.validate()
            XCTAssertEqual(record.segments.first?.start, record.start)
            XCTAssertEqual(record.segments.last?.end, record.end)
            XCTAssertEqual(record.asleepMinutes + record.minutes(.awake), record.inBedMinutes)
            XCTAssertEqual(record.awakenings, 2)
            XCTAssertEqual(record.minutes(.deep), 102)
            XCTAssertGreaterThan(record.efficiency ?? 0, 90)
        }
    }

    func testManualRecordDoesNotInventStagesOrVitals() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let payload = SleepPayload(id: UUID(), start: start, end: start.addingTimeInterval(8 * 3600), source: .manual,
                                   segments: [], heartSamples: [], averageHeartRate: nil, averageSpO2: nil,
                                   averageRespiratoryRate: nil, note: "test")
        try payload.validate()
        let record = SleepRecord(payload)
        XCTAssertEqual(record.asleepMinutes, 480)
        XCTAssertNil(record.score)
        XCTAssertNil(record.efficiency)
        XCTAssertNil(record.deepShare)
        XCTAssertNil(record.awakenings)
        XCTAssertNil(record.averageHeartRate)
    }

    func testStageSharesExcludeAwakeAndUnknownIntervalsDoNotBecomeZeroShares() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let pattern: [(SleepStage, Int)] = [(.awake, 60), (.deep, 84), (.light, 231), (.rem, 105)]
        var cursor = start
        let segments = pattern.map { stage, minutes in
            let end = cursor.addingTimeInterval(Double(minutes) * 60)
            defer { cursor = end }
            return SleepSegment(stage: stage, start: cursor, end: end)
        }
        var payload = SleepPayload(id: UUID(), start: start, end: cursor, source: .band, segments: segments,
                                   heartSamples: [], averageHeartRate: nil, averageSpO2: nil, averageRespiratoryRate: nil, note: "")
        try payload.validate()
        let record = SleepRecord(payload)
        XCTAssertEqual(record.asleepMinutes, 420)
        XCTAssertEqual(record.efficiency, 87)
        XCTAssertEqual(record.share(.deep), 20)
        XCTAssertEqual(record.share(.light), 55)
        XCTAssertEqual(record.share(.rem), 25)
        XCTAssertNil(record.share(.awake))
        XCTAssertEqual(record.score, 87)
        payload.segments[2].stage = .unobserved
        let incomplete = SleepRecord(payload)
        XCTAssertNil(incomplete.share(.deep))
        XCTAssertNil(incomplete.share(.light))
        XCTAssertNil(incomplete.share(.rem))
        XCTAssertNil(incomplete.efficiency)
        XCTAssertNil(incomplete.score)
        payload.segments[2].stage = .unspecified
        XCTAssertNil(SleepRecord(payload).share(.rem))
    }

    func testStageHelpUsesTheSelectedRecordSource() throws {
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        XCTAssertTrue(SleepMetricGuide.stages(SleepRecord(payload)).body.contains("当前选中的是预览记录"))
        payload.source = .band
        let ringHelp = SleepMetricGuide.stages(SleepRecord(payload))
        XCTAssertTrue(ringHelp.body.contains("本晚来自设备"))
        XCTAssertFalse(ringHelp.body.contains("预览记录"))
        XCTAssertFalse(ringHelp.references.isEmpty)
        payload.source = .healthKit
        XCTAssertTrue(SleepMetricGuide.stages(SleepRecord(payload)).body.contains("本晚来自系统健康"))
    }

    func testBackupRoundTripPreservesSegmentsAndSources() throws {
        let samples = SampleSleepRecords.makeMonth(now: Date(timeIntervalSince1970: 1_790_000_000))
        let backup = SleepBackup(records: samples.map(\.payload))
        let decoded = try SleepBackup.decode(backup.encode())
        XCTAssertEqual(decoded.records.count, 30)
        XCTAssertEqual(decoded.records.first?.id, samples.first?.id)
        XCTAssertEqual(decoded.records.first?.segments, samples.first?.segments)
        XCTAssertEqual(decoded.records.first?.heartSamples, samples.first?.heartSamples)
        XCTAssertEqual(decoded.records.first?.source, .sample)
    }

    func testImportRejectsOverlapsGapsInvalidVitalsAndFutureFormat() throws {
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.segments[1].start = payload.segments[0].start
        XCTAssertThrowsError(try payload.validate())
        payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.segments[1].start.addTimeInterval(60)
        XCTAssertThrowsError(try payload.validate())
        payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.averageSpO2 = 101
        XCTAssertThrowsError(try payload.validate())
        let backup = SleepBackup(version: 999, records: [])
        XCTAssertThrowsError(try SleepBackup.decode(backup.encode()))
    }

    func testSwiftDataSurvivesReopeningAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        do {
            let container = try ModelContainer(for: SleepRecord.self, configurations: configuration)
            let context = ModelContext(container)
            context.insert(SleepRecord(payload))
            try context.save()
        }
        do {
            let container = try ModelContainer(for: SleepRecord.self, configurations: configuration)
            let context = ModelContext(container)
            let rows = try context.fetch(FetchDescriptor<SleepRecord>())
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.id, payload.id)
            XCTAssertEqual(rows.first?.segments, payload.segments)
            context.delete(try XCTUnwrap(rows.first))
            try context.save()
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepRecord>()), 0)
        }
    }

    func testDecodedFieldsRefreshAfterReplacementDirectEditsAndRemoval() throws {
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.metadata = SleepMetadata(externalSource: "first", aisScore: 6)
        let record = SleepRecord(payload)
        XCTAssertEqual(record.metadata?.externalSource, "first")
        XCTAssertEqual(record.segments, payload.segments)
        XCTAssertEqual(record.heartSamples, payload.heartSamples)
        payload.metadata = SleepMetadata(externalSource: "updated")
        payload.segments = [SleepSegment(stage: .deep, start: payload.start, end: payload.end)]
        payload.heartSamples = []
        record.replace(with: payload)
        XCTAssertEqual(record.metadata?.externalSource, "updated")
        XCTAssertEqual(record.metadata?.aisScore, 6)
        XCTAssertEqual(record.segments, payload.segments)
        XCTAssertTrue(record.heartSamples.isEmpty)
        record.metadataData = nil
        XCTAssertNil(record.metadata)
        record.segmentsData = Data("broken".utf8)
        XCTAssertTrue(record.segments.isEmpty)
        record.metadataData = Data("broken".utf8)
        XCTAssertNil(record.metadata)
        record.metadataData = try JSONEncoder().encode(SleepMetadata(externalSource: "restored"))
        XCTAssertEqual(record.metadata?.externalSource, "restored")
        record.segmentsData = try JSONEncoder().encode(payload.segments)
        XCTAssertEqual(record.segments, payload.segments)
    }

    func testLargeNightMetadataRepeatedReadsPreserveValues() throws {
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        let values = (0..<4000).map { index in
            WearableVital(device: "test-bio", deviceLabel: "BIO synthetic", date: payload.start.addingTimeInterval(Double(index)),
                          kind: .heart, value: 60 + Double(index % 20), origin: "synthetic")
        }
        payload.metadata = SleepMetadata(bioNight: BIONight(device: "test-bio", endDay: "2026-11-12", readAt: .now,
                                                           samples: values, sleepInputMinutes: 480))
        let record = SleepRecord(payload)
        let data = try XCTUnwrap(record.metadataData)
        let baselineStart = Date.now
        for _ in 0..<40 {
            XCTAssertEqual(try JSONDecoder().decode(SleepMetadata.self, from: data).bioNight?.samples.count, 4000)
        }
        let baseline = Date.now.timeIntervalSince(baselineStart)
        let cachedStart = Date.now
        for _ in 0..<40 {
            XCTAssertEqual(record.metadata?.bioNight?.samples.count, 4000)
            XCTAssertEqual(record.metadata?.bioNight?.samples.last?.value, values.last?.value)
        }
        let cached = Date.now.timeIntervalSince(cachedStart)
        print("4000-sample night / 40 reads: repeated decoding \(baseline)s; cached model \(cached)s")
    }
}

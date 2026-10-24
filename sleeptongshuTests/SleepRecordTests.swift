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
}

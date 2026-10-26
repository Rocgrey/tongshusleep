import XCTest
import SwiftData
@testable import sleeptongshu

@MainActor
final class SleepV2Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testOldBackupWithoutMetadataStillLoads() throws {
        let record = try XCTUnwrap(SampleSleepRecords.makeMonth().first)
        let backup = SleepBackup(version: 1, records: [record.payload])
        let data = try backup.encode()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("metadata"))
        let restored = try XCTUnwrap(SleepBackup.decode(data).records.first)
        XCTAssertNil(restored.metadata)
        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.segments, record.segments)
    }

    func testQuietWindowRequiresContinuousMotionAndAudioCoverage() {
        var epochs = (0..<30).map { PhoneEpoch(date: start.addingTimeInterval(Double($0) * 60), audioSeconds: 60, soundDB: -50, movement: 0.001) }
        XCTAssertEqual(PhoneNight.analyze(epochs, classifierAvailable: true, interrupted: false).estimatedMinutes, 30)
        XCTAssertEqual(PhoneNight.analyze(epochs, classifierAvailable: true, interrupted: false).estimatedOnset, start)
        epochs = epochs.prefix(14).map { $0 }
        XCTAssertNil(PhoneNight.analyze(epochs, classifierAvailable: true, interrupted: false).estimatedMinutes)
        epochs.append(PhoneEpoch(date: start.addingTimeInterval(16 * 60), audioSeconds: 60, soundDB: -50, movement: 0.001))
        XCTAssertNil(PhoneNight.analyze(epochs, classifierAvailable: true, interrupted: false).estimatedOnset)
        let noMotion = (0..<30).map { PhoneEpoch(date: start.addingTimeInterval(Double($0) * 60), audioSeconds: 60, soundDB: -50) }
        XCTAssertNil(PhoneNight.analyze(noMotion, classifierAvailable: true, interrupted: false).estimatedOnset)
        let noAudio = (0..<30).map { PhoneEpoch(date: start.addingTimeInterval(Double($0) * 60), audioSeconds: 10, soundDB: -50, movement: 0.001) }
        XCTAssertNil(PhoneNight.analyze(noAudio, classifierAvailable: true, interrupted: false).estimatedOnset)
    }

    func testPhoneBackupAndPersistenceDoNotInventStagesOrPhysiology() throws {
        let report = PhoneNight.preview(start: start)
        let checkpoint = PhoneCheckpoint(start: start, end: start.addingTimeInterval(8 * 3600), epochs: report.epochs, classifierAvailable: true)
        let payload = checkpoint.payload
        try payload.validate()
        let data = try SleepBackup(records: [payload]).encode()
        let decoded = try XCTUnwrap(SleepBackup.decode(data).records.first)
        let container = try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let record = SleepRecord(decoded)
        container.mainContext.insert(record)
        try container.mainContext.save()
        XCTAssertEqual(record.metadata?.phone?.epochs, report.epochs)
        XCTAssertEqual(record.metadata?.phone?.estimatedOnset, report.estimatedOnset)
        XCTAssertFalse(record.hasStages)
        XCTAssertNil(record.averageHeartRate)
        XCTAssertNil(record.averageSpO2)
        XCTAssertNil(record.score)
        XCTAssertNil(record.awakenings)
        XCTAssertNil(record.deepShare)
        var short = checkpoint
        short.epochs = Array(report.epochs.prefix(3))
        short.end = start.addingTimeInterval(3 * 60)
        let insufficient = SleepRecord(short.payload)
        XCTAssertFalse(insufficient.hasSleepDuration)
        XCTAssertNil(TrendMetric.duration.value(insufficient))
    }

    func testPhoneImportRejectsMalformedOrUnboundedEpochs() throws {
        var payload = PhoneCheckpoint(start: start, end: start.addingTimeInterval(3600), epochs: [PhoneEpoch(date: start, audioSeconds: 60)], classifierAvailable: true).payload
        payload.metadata?.phone?.epochs[0].audioSeconds = -1
        XCTAssertThrowsError(try payload.validate())
        payload.metadata?.phone?.epochs[0].audioSeconds = 60
        let duplicate = payload.metadata!.phone!.epochs[0]
        payload.metadata?.phone?.epochs.append(duplicate)
        XCTAssertThrowsError(try payload.validate())
    }

    func testHealthGapsAndConflictingStagesRemainUnknown() throws {
        let intervals = [
            HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(3600), stage: .deep),
            HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(1800), end: start.addingTimeInterval(3600), stage: .rem),
            HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(5400), end: start.addingTimeInterval(7200), stage: .unspecified)
        ]
        let segments = HealthSleepNormalizer.segments(intervals)
        XCTAssertEqual(segments.map(\.stage), [.deep, .unobserved, .unspecified])
        var payload = try XCTUnwrap(SampleSleepRecords.makeMonth().first?.payload)
        payload.source = .healthKit; payload.start = start; payload.end = start.addingTimeInterval(7200)
        payload.segments = segments; payload.heartSamples = []
        try payload.validate()
        let record = SleepRecord(payload)
        XCTAssertEqual(record.asleepMinutes, 60)
        XCTAssertNil(record.efficiency)
        XCTAssertNil(record.score)
        XCTAssertNil(record.deepShare)
        XCTAssertNil(record.awakenings)
        XCTAssertEqual(HealthSleepNormalizer.stableID("source|night"), HealthSleepNormalizer.stableID("source|night"))
        XCTAssertNotEqual(HealthSleepNormalizer.stableID("source|night"), HealthSleepNormalizer.stableID("other|night"))
    }

    func testStandardHeartRateParsesBothFormatsAndRejectsTruncation() {
        XCTAssertEqual(StandardHeartRate.decode(Data([0, 62])), 62)
        XCTAssertEqual(StandardHeartRate.decode(Data([1, 200, 0])), 200)
        XCTAssertNil(StandardHeartRate.decode(Data([1, 200])))
        XCTAssertNil(StandardHeartRate.decode(Data([0, 0])))
        XCTAssertNil(StandardHeartRate.decode(Data()))
    }
}

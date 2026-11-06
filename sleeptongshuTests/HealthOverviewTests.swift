import XCTest
import HealthKit
import SwiftData
@testable import sleeptongshu

final class HealthOverviewTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_800_057_600)
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }
    private func observation(_ id: String, value: Double, metric: HealthMetric = .hrv, source: String = "A", offset: Int = -1) -> HealthObservation {
        let date = day(offset).addingTimeInterval(3600)
        return HealthObservation(id: id, metric: metric, sourceID: source, start: date, end: date.addingTimeInterval(60), value: value)
    }

    func testDailyMediansIncludeAllSourcesAndDoNotTreatMissingDaysAsZero() {
        let a = observation("1", value: 20)
        let points = [a, a, observation("2", value: 40), observation("3", value: 90, offset: -3), observation("bad", value: .nan)]
        let days = HealthOverviewAnalysis.daily(points, metric: .hrv, calendar: calendar)
        XCTAssertEqual(days.map(\.value), [90, 30])
        XCTAssertEqual(days.last?.count, 2)
        let combined = HealthOverviewAnalysis.daily(points + [observation("other", value: 75, source: "B"), observation("copy", value: 20, source: "B")], metric: .hrv, calendar: calendar)
        XCTAssertEqual(combined.map(\.value), [90, 40])
        XCTAssertEqual(combined.last?.count, 3)
    }

    func testHealthRefreshDetectsNewOrChangedRecordsButNotAnUnchangedSnapshot() {
        let oldObservation = observation("stable", value: 48)
        let old = HealthOverviewSnapshot(readAt: now, sources: [], observations: [oldObservation])
        let same = HealthOverviewSnapshot(readAt: now.addingTimeInterval(60), sources: [], observations: [oldObservation])
        let added = HealthOverviewSnapshot(readAt: now, sources: [], observations: [oldObservation, observation("new", value: 52)])
        let changed = HealthOverviewSnapshot(readAt: now, sources: [], observations: [observation("stable", value: 50)])
        let empty = HealthOverviewSnapshot(readAt: now, sources: [], observations: [])

        XCTAssertFalse(HealthOverviewAnalysis.hasNewData(previous: old, next: same))
        XCTAssertTrue(HealthOverviewAnalysis.hasNewData(previous: old, next: added))
        XCTAssertTrue(HealthOverviewAnalysis.hasNewData(previous: old, next: changed))
        XCTAssertFalse(HealthOverviewAnalysis.hasNewData(previous: nil, next: empty))
        XCTAssertTrue(HealthOverviewAnalysis.hasNewData(previous: nil, next: added))
    }

    func testCumulativeTotalsRejectOverlappingAndCrossDayIntervals() {
        let first = observation("1", value: 100, metric: .steps)
        var second = observation("2", value: 80, metric: .steps)
        second.start = first.end; second.end = first.end.addingTimeInterval(60)
        XCTAssertEqual(HealthOverviewAnalysis.daily([first, first, second], metric: .steps, calendar: calendar).first?.value, 180)
        second.start = first.start.addingTimeInterval(1)
        XCTAssertTrue(HealthOverviewAnalysis.daily([first, second], metric: .steps, calendar: calendar).isEmpty)
        var cross = observation("cross", value: 100, metric: .steps, offset: -2)
        cross.start = day(-2).addingTimeInterval(86_390)
        cross.end = day(-1).addingTimeInterval(10)
        XCTAssertTrue(HealthOverviewAnalysis.daily([first, cross], metric: .steps, calendar: calendar).isEmpty)
    }

    func testSleepStagesAreUnionedWithoutCountingBedOrAwakeAsSleep() {
        let start = day(-1).addingTimeInterval(22 * 3600)
        let deep = HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(3600), stage: .deep)
        let awake = HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400), stage: .awake)
        let rem = HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(5400), end: start.addingTimeInterval(9000), stage: .rem)
        let values = HealthOverviewAnalysis.sleepObservations([deep, deep, awake, rem], sourceID: "ring", calendar: calendar)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.value, 2)
        XCTAssertEqual(values.first?.start, day(0))
        XCTAssertNil(HealthOverviewStore.stage(HKCategoryValueSleepAnalysis.inBed.rawValue))
    }

    func testTrendRequiresCoverageInBothDisjointWindowsAndExcludesToday() {
        let days = (1...28).map { HealthDay(date: day(-$0), value: $0 <= 14 ? 45 : 30, count: 1) }
        let change = HealthOverviewAnalysis.change(days + [HealthDay(date: day(0), value: 400, count: 1)], now: now, calendar: calendar)
        XCTAssertEqual(change?.recent, 45)
        XCTAssertEqual(change?.previous, 30)
        XCTAssertNil(HealthOverviewAnalysis.change(Array(days.prefix(14)), now: now, calendar: calendar))
        XCTAssertNil(HealthOverviewAnalysis.change(Array(days.prefix(6)) + Array(days.suffix(14)), now: now, calendar: calendar))
    }

    func testFitnessAgeUsesMeasuredFriendTableWithNoOutOfRangeExtrapolation() throws {
        XCTAssertEqual(FitnessAge.reference(.male), [48.0, 42.4, 37.8, 32.6, 28.2, 24.4])
        let male = try XCTUnwrap(FitnessAge.estimate(vo2: (42.4 + 37.8) / 2, age: 45, sex: .male))
        XCTAssertEqual(male.years, 39.5, accuracy: 0.0001)
        XCTAssertEqual(male.display, "约40")
        XCTAssertEqual(FitnessAge.estimate(vo2: 60, age: 42, sex: .female)?.boundary, .younger)
        XCTAssertEqual(FitnessAge.estimate(vo2: 12, age: 42, sex: .male)?.boundary, .older)
        XCTAssertNil(FitnessAge.estimate(vo2: 35, age: nil, sex: .male))
        XCTAssertNil(FitnessAge.estimate(vo2: 35, age: 19, sex: .female))
        XCTAssertNil(FitnessAge.estimate(vo2: 35, age: 80, sex: .male))
        XCTAssertNil(FitnessAge.estimate(vo2: .nan, age: 40, sex: .male))
        XCTAssertNil(FitnessAge.estimate(vo2: 35, age: 40, sex: .unspecified))
    }

    func testAgeRequirementsExplainMissingDataWithoutTreatingDuplicatesOrTodayAsCoverage() {
        let sameDay = HealthDay(date: day(-1), value: 35, count: 1)
        let days = [sameDay, sameDay, HealthDay(date: day(0), value: 40, count: 1), HealthDay(date: day(-40), value: 40, count: 1)]
        let missing = FitnessAge.requirements(days, now: now, age: nil, sex: .unspecified, calendar: calendar)
        XCTAssertTrue(missing.allSatisfy { !$0.satisfied })
        XCTAssertTrue(missing[2].detail.contains("1 天"))
        XCTAssertTrue(missing[2].detail.contains("还需 2 天"))
        let enough = [1, 2, 3].map { HealthDay(date: day(-$0), value: 35, count: 1) }
        let ready = FitnessAge.requirements(enough, now: now, age: 40, sex: .female, calendar: calendar)
        XCTAssertTrue(ready.allSatisfy(\.satisfied))
        XCTAssertFalse(FitnessAge.requirements(enough, now: now, age: 80, sex: .female, calendar: calendar)[0].satisfied)
    }

    func testExploratoryAgeUsesOnlySameDayCompleteDataAndIsBounded() throws {
        let sleep = HealthDay(date: day(-1), value: 7.5, count: 1)
        let steps = HealthDay(date: day(-1), value: 8_000, count: 1)
        let today = HealthDay(date: day(0), value: 100_000, count: 1)
        let estimate = try XCTUnwrap(FitnessAge.exploratory([.sleep: [sleep], .steps: [steps, today]], actualAge: 40, now: now, calendar: calendar))
        XCTAssertEqual(estimate.age, 37)
        XCTAssertEqual(estimate.actualAge, 40)
        XCTAssertEqual(estimate.signals.count, 2)
        XCTAssertEqual(estimate.date, day(-1))
        XCTAssertNil(FitnessAge.exploratory([.sleep: [sleep], .steps: [HealthDay(date: day(-2), value: 8_000, count: 1)]], actualAge: 40, now: now, calendar: calendar))
        XCTAssertNil(FitnessAge.exploratory([.sleep: [sleep], .steps: [steps]], actualAge: nil, now: now, calendar: calendar))
        let poor = FitnessAge.exploratory([.sleep: [HealthDay(date: day(-1), value: 1, count: 1)],
                                           .steps: [HealthDay(date: day(-1), value: 0, count: 1)]], actualAge: 40, now: now, calendar: calendar)
        XCTAssertEqual(poor?.age, 43)
    }

    func testAgeAndChangeRequireRecentDistinctDatesAndDoNotAnnualize() throws {
        let days = [1, 10, 20, 31, 45, 59].map { HealthDay(date: day(-$0), value: $0 < 30 ? 40 : 32, count: 1) }
        XCTAssertEqual(FitnessAge.current(days, now: now, age: 45, sex: .male, calendar: calendar)?.vo2, 40)
        XCTAssertEqual(try XCTUnwrap(FitnessAge.change(days, now: now, calendar: calendar)), 25, accuracy: 0.001)
        XCTAssertNil(FitnessAge.current(Array(days.prefix(2)), now: now, age: 45, sex: .male, calendar: calendar))
        XCTAssertNil(FitnessAge.current(days, now: day(100), age: 45, sex: .male, calendar: calendar))
    }

    func testHealthIdentitySeparatesSameModelDevicesAndMissingIdentifiers() {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        func sample(_ identifier: String?) -> HKQuantitySample {
            let device = HKDevice(name: "手表", manufacturer: "设备厂商", model: "相同型号", hardwareVersion: "1", firmwareVersion: "1", softwareVersion: nil, localIdentifier: identifier, udiDeviceIdentifier: nil)
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 65),
                                    start: now, end: now, device: device, metadata: nil)
        }
        XCTAssertNotEqual(HealthSourceIdentity.key(sample("A")), HealthSourceIdentity.key(sample("B")))
        XCTAssertNotEqual(HealthSourceIdentity.key(sample("A")), HealthSourceIdentity.key(sample(nil)))
        XCTAssertTrue(HealthSourceIdentity.matches(sample("A"), sample("A")))
        XCTAssertFalse(HealthSourceIdentity.describe(sample(nil)).hardwareIdentified)
    }

    func testHealthUnitsMatchHKStorageAndPercentIsNotAlreadyTimesOneHundred() {
        XCTAssertEqual(HKQuantity(unit: .second(), doubleValue: 0.045).doubleValue(for: HealthMetric.hrv.healthUnit), 45, accuracy: 0.001)
        XCTAssertEqual(HKQuantity(unit: HKUnit(from: "ml/kg*min"), doubleValue: 38).doubleValue(for: HealthMetric.vo2.healthUnit), 38, accuracy: 0.001)
        XCTAssertEqual(HKQuantity(unit: .percent(), doubleValue: 0.98).doubleValue(for: HealthMetric.oxygen.healthUnit) * 100, 98, accuracy: 0.001)
        XCTAssertEqual(HealthMetric.bodyFat.healthValue(HKQuantity(unit: .percent(), doubleValue: 0.23)), 23, accuracy: 0.001)
        XCTAssertEqual(HealthMetric.distance.healthValue(HKQuantity(unit: .meter(), doubleValue: 5_000)), 5, accuracy: 0.001)
        XCTAssertEqual(HealthMetric.height.healthValue(HKQuantity(unit: .meter(), doubleValue: 1.72)), 172, accuracy: 0.001)
        XCTAssertEqual(HealthMetric.weight.healthValue(HKQuantity(unit: .gram(), doubleValue: 68_000)), 68, accuracy: 0.001)
        XCTAssertEqual(HealthMetric.activeEnergy.healthValue(HKQuantity(unit: .jouleUnit(with: .kilo), doubleValue: 418.4)), 100, accuracy: 0.01)
        XCTAssertEqual(HealthMetric.restingEnergy.quantityIdentifier, .basalEnergyBurned)
        XCTAssertEqual(HealthMetric.bmi.quantityIdentifier, .bodyMassIndex)
        XCTAssertNil(HealthMetric.workout.quantityIdentifier)
    }

    func testWorkoutReadKeepsTypeDurationAndAvailableDistanceWithoutInventingEnergy() throws {
        let workout = HKWorkout(activityType: .running, start: now, end: now.addingTimeInterval(1800), duration: 1500,
                                totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: 4_000), metadata: nil)
        let record = try XCTUnwrap(HealthOverviewStore.workoutRecord(workout))
        XCTAssertEqual(record.title, "跑步")
        XCTAssertEqual(record.minutes, 25)
        XCTAssertEqual(record.distanceKilometers, 4)
        XCTAssertNil(record.energyKilocalories)
    }

    func testCumulativeRefreshDoesNotCountClockAdvanceAsNewData() {
        var reading = observation("today-total", value: 150, metric: .activeEnergy, offset: 0)
        let old = HealthOverviewSnapshot(readAt: now, sources: [], observations: [reading])
        reading.end = reading.end.addingTimeInterval(60)
        var next = HealthOverviewSnapshot(readAt: now.addingTimeInterval(60), sources: [], observations: [reading])
        XCTAssertFalse(HealthOverviewAnalysis.hasNewData(previous: old, next: next))
        next.observations[0].value = 160
        XCTAssertTrue(HealthOverviewAnalysis.hasNewData(previous: old, next: next))
    }

    @MainActor
    func testOldSourceSelectionsDoNotHideAvailableHealthDataAfterUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("health.json")
        let sources = [HealthDataSource(id: "A", appName: "来源", deviceName: "手表", hardwareIdentified: true),
                       HealthDataSource(id: "B", appName: "来源", deviceName: "戒指", hardwareIdentified: true)]
        let snapshot = HealthOverviewSnapshot(readAt: now, sources: sources,
                                              observations: [observation("a", value: 40), observation("b", value: 65, source: "B")])
        try JSONEncoder().encode(HealthOverviewArchive(snapshot: snapshot, selections: ["hrv": "A"])).write(to: url)
        let store = HealthOverviewStore(url: url)
        XCTAssertEqual(store.days(for: .hrv).first?.value, 52.5)
        XCTAssertTrue(try JSONDecoder().decode(HealthOverviewArchive.self, from: store.export()).selections.isEmpty)
        try JSONEncoder().encode(HealthOverviewArchive(snapshot: snapshot, selections: ["hrv": "old-device"])).write(to: url)
        XCTAssertEqual(HealthOverviewStore(url: url).days(for: .hrv).first?.value, 52.5)
        try store.clearSnapshot()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAutomaticSleepKeepsOneSourcePerNightAndMatchesItsVitals() throws {
        let start = day(-1).addingTimeInterval(22 * 3600)
        let a = HealthSleepCandidate(sourceID: "A", intervals: [
            HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(3600), stage: .deep),
            HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400), stage: .awake),
            HealthSleepInterval(id: UUID(), start: start.addingTimeInterval(5400), end: start.addingTimeInterval(9000), stage: .rem)
        ])
        let b = HealthSleepCandidate(sourceID: "B", intervals: [
            HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(10800), stage: .unspecified)
        ])
        let vitals = [HealthObservation(id: "a-heart", metric: .heart, sourceID: "A", start: start, end: start, value: 60),
                      HealthObservation(id: "b-heart", metric: .heart, sourceID: "B", start: start, end: start, value: 120)]
        let records = try HealthSleepImporter.automaticRecords([b, a], observations: vitals, sources: [], calendar: calendar)
        let payload = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(SleepRecord(payload).asleepMinutes, 120)
        XCTAssertEqual(payload.averageHeartRate, 60)
        XCTAssertNil(payload.averageSpO2)
        XCTAssertEqual(payload.id, try HealthSleepImporter.automaticRecords([a, b], observations: [], sources: [], calendar: calendar).first?.id)
        let awake = HealthSleepCandidate(sourceID: "C", intervals: [HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(600), stage: .awake)])
        XCTAssertTrue(try HealthSleepImporter.automaticRecords([awake], observations: [], sources: [], calendar: calendar).isEmpty)
    }

    @MainActor
    func testAutomaticSleepRefreshUpdatesOldRecordAndPreservesOtherRecords() throws {
        let container = try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let start = day(-1).addingTimeInterval(22 * 3600)
        let oldID = UUID()
        let old = SleepPayload(id: oldID, start: start, end: start.addingTimeInterval(7200), source: .healthKit,
                               segments: [], heartSamples: [], note: "旧版导入", metadata: SleepMetadata(externalSource: "旧设备", externalID: "health-v2|old"))
        var manual = old
        manual.id = UUID(); manual.source = .manual; manual.metadata = nil
        context.insert(SleepRecord(old)); context.insert(SleepRecord(manual)); try context.save()
        let candidate = HealthSleepCandidate(sourceID: "new-device", intervals: [HealthSleepInterval(id: UUID(), start: start, end: start.addingTimeInterval(10800), stage: .light)])
        let payloads = try HealthSleepImporter.automaticRecords([candidate], observations: [], sources: [], calendar: calendar)
        try HealthSleepImporter.save(payloads, in: context, calendar: calendar)
        try HealthSleepImporter.save(payloads, in: context, calendar: calendar)
        let records = try context.fetch(FetchDescriptor<SleepRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.source == .healthKit }?.id, oldID)
        XCTAssertEqual(records.first { $0.source == .healthKit }?.asleepMinutes, 180)
        XCTAssertEqual(records.first { $0.source == .manual }?.asleepMinutes, 120)
    }
}

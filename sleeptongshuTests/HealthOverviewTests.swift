import XCTest
import HealthKit
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

    func testDailyMediansDeduplicateAndDoNotMixDevicesOrTreatMissingDaysAsZero() {
        let a = observation("1", value: 20)
        let points = [a, a, observation("2", value: 40), observation("3", value: 90, offset: -3), observation("bad", value: .nan)]
        let days = HealthOverviewAnalysis.daily(points, metric: .hrv, calendar: calendar)
        XCTAssertEqual(days.map(\.value), [90, 30])
        XCTAssertEqual(days.last?.count, 2)
        XCTAssertEqual(HealthOverviewAnalysis.daily(points + [observation("other", value: 75, source: "B")], metric: .hrv, calendar: calendar), [])
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
    }

    @MainActor
    func testSelectedSourcePersistsAndUnavailableSourceDoesNotSilentlySwitch() throws {
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
        XCTAssertEqual(store.days(for: .hrv).first?.value, 40)
        store.select("B", for: .hrv)
        XCTAssertEqual(store.days(for: .hrv).first?.value, 65)
        XCTAssertEqual(HealthOverviewStore(url: url).selections["hrv"], "B")
        store.select("nonexistent", for: .hrv)
        XCTAssertEqual(store.selections["hrv"], "B")
        try JSONEncoder().encode(HealthOverviewArchive(snapshot: snapshot, selections: ["hrv": "old-device"])).write(to: url)
        XCTAssertTrue(HealthOverviewStore(url: url).days(for: .hrv).isEmpty)
        try store.clearSnapshot()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

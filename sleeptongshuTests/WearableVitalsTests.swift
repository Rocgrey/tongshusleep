import XCTest
@testable import sleeptongshu

final class WearableVitalsTests: XCTestCase {
    @MainActor
    func testRetiredMetricsAreHiddenFromOldFilesAndNotSyncedOrExported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = [VitalKind.heart, .glucose, .cholesterol, .triglycerides, .hdl, .ldl, .uricAcid].map {
            WearableVital(device: "old-ring", deviceLabel: "戒指", date: Date(timeIntervalSince1970: 1000), kind: $0, value: $0 == .heart ? 65 : 5, origin: "旧记录")
        }
        try JSONEncoder().encode(samples).write(to: url)
        let store = WearableVitalsStore(url: url)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.samples.count, 7)
        XCTAssertEqual(store.visibleSamples.map(\.kind), [.heart])
        XCTAssertEqual(try JSONDecoder().decode([WearableVital].self, from: store.export()).map(\.kind), [.heart])
        let decoded = try WearableVitalDecoder.decode(["deviceID": "unit-ring", "vitals": [
            ["time": "2025-10-28 08:00", "heart": 65, "glucose": 5, "cholesterol": 5,
             "triglycerides": 2, "hdl": 1, "ldl": 3, "uricAcid": 300]
        ]])
        XCTAssertEqual(decoded.map(\.kind), [.heart])
        let fresh = WearableVitalsStore(url: nil)
        XCTAssertEqual(try fresh.merge(samples), 1)
    }

    func testDailyGraphsPreserveMissingDaysAndDistributionCountsEverySampleOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_700_006_400)
        let values: [(TimeInterval, Double)] = [(0, 60), (60, 70), (120, 80), (2 * 86400, 90)]
        let samples = values.map {
            WearableVital(device: "test", deviceLabel: "设备", date: start.addingTimeInterval($0.0), kind: .heart, value: $0.1, origin: "测试")
        }
        let days = VitalInsights.daily(samples, calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.mean, 70)
        XCTAssertEqual(days.first?.minimum, 60)
        XCTAssertEqual(days.first?.maximum, 80)
        XCTAssertEqual(days.first?.count, 3)
        XCTAssertEqual(days.last?.count, 1)
        XCTAssertEqual(VitalInsights.buckets(samples).map(\.count), [1, 1, 1, 1])
        XCTAssertEqual(VitalInsights.buckets([samples[0], samples[0]]).map(\.count), [2])
        XCTAssertTrue(VitalInsights.buckets([]).isEmpty)
        XCTAssertNil(VitalKind.hrv.chartReference)
        XCTAssertNil(VitalKind.stress.chartReference)
        XCTAssertNil(VitalKind.heart.chartReference)
        XCTAssertEqual(VitalKind.oxygen.chartReference, 95...100)
    }

    func testVitalsDoNotRequireSleepAndRejectPlaceholders() throws {
        let result: [String: Any] = ["deviceID": "unit-ring", "sleeps": [], "vitals": [
            ["time": "2025-10-28 08:00", "heart": 65, "oxygen": 98, "respiration": 14, "hrv": 42],
            ["time": "2025-10-28 08:05", "heart": 0, "oxygen": 255, "respiration": 255, "hrv": 0],
            ["time": "2025-02-30 08:00", "heart": 60],
            ["time": "2099-01-01 08:00", "heart": 60]
        ]]
        let parsed = try VeepooSleepDecoder.decode(result)
        XCTAssertTrue(parsed.records.isEmpty)
        XCTAssertEqual(parsed.vitals.count, 4)
        XCTAssertEqual(Set(parsed.vitals.map(\.kind)), [.heart, .oxygen, .respiration, .hrv])
    }

    func testConflictingValuesAndInvalidPressureRemainMissing() throws {
        let parsed = try WearableVitalDecoder.decode(["deviceID": "unit-ring", "vitals": [
            ["time": "2025-10-28 08:00", "heart": 65, "systolic": 70, "diastolic": 120],
            ["time": "2025-10-28 08:00", "heart": 68],
            ["time": "2025-10-28 08:05", "heart": true],
            ["time": "2025-10-28 08:10", "systolic": 120, "diastolic": 75]
        ]])
        XCTAssertEqual(Set(parsed.map(\.kind)), [.systolic, .diastolic])
        XCTAssertEqual(parsed.count, 2)
    }

    @MainActor
    func testLocalVitalsSurviveReloadAndDeduplicate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vitals.json")
        let store = WearableVitalsStore(url: url)
        let sample = WearableVital(device: "one", deviceLabel: "戒指", date: Date(timeIntervalSince1970: 1000), kind: .oxygen, value: 98, origin: "设备历史")
        XCTAssertEqual(try store.merge([sample, sample]), 1)
        XCTAssertEqual(try store.merge([sample]), 0)
        let reloaded = WearableVitalsStore(url: url)
        XCTAssertEqual(reloaded.samples, [sample])
        try reloaded.clear()
        XCTAssertTrue(WearableVitalsStore(url: url).samples.isEmpty)
    }

    func testRememberedDevicePersistsAndForgetDoesNotRestoreIt() throws {
        let suite = "wearable-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = RememberedDeviceStorage(defaults: defaults)
        let device = RememberedDevice(id: UUID(), name: "戒指", lastConnected: .now)
        storage.save([device])
        XCTAssertEqual(storage.load(), [device])
        storage.save([])
        XCTAssertTrue(storage.load().isEmpty)
    }

    func testStandardOxygenAndPressureIncludingInvalidFrames() {
        XCTAssertEqual(StandardVitalDecoder.decode(Data([0, 98, 0, 65, 0]), characteristic: "2A5E").first?.1, 98)
        XCTAssertEqual(StandardVitalDecoder.decode(Data([0, 120, 0, 75, 0, 90, 0]), characteristic: "2A35").count, 2)
        XCTAssertTrue(StandardVitalDecoder.decode(Data([0, 0xff, 0x07, 65, 0]), characteristic: "2A5E").isEmpty)
        XCTAssertTrue(StandardVitalDecoder.decode(Data([1, 98, 0, 65, 0]), characteristic: "2A5E").isEmpty)
        XCTAssertTrue(StandardVitalDecoder.decode(Data([2, 98, 0, 65, 0, 0x20, 0]), characteristic: "2A5E").isEmpty)
        XCTAssertTrue(StandardVitalDecoder.decode(Data([0, 75, 0, 120, 0, 90, 0]), characteristic: "2A35").isEmpty)
        XCTAssertNil(StandardVitalDecoder.sfloat([1], offset: 0))
    }

    func testPublicDeviceNamesAreGeneric() {
        for name in ["Xiaomi Smart Band 10 Pro", "小米手环", "G Band", "Gb and", "Apple Watch", "苹果手表", "Veepoo Ring"] {
            let label = DevicePresentation.name(name).lowercased()
            for brand in ["xiaomi", "小米", "g band", "apple", "苹果", "veepoo"] { XCTAssertFalse(label.contains(brand)) }
        }
    }
}

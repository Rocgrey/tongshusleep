import XCTest
@testable import sleeptongshu

@MainActor final class SyncPreparationTests: XCTestCase {
    func testUnchangedDenseRecordsReusePreparedBatchAndChangedNotesInvalidate() async throws {
        let records = BIONightPerformanceFixture.make().map(SleepRecord.init)
        let input = SyncPreparationInput(sleep: records.map(SleepSyncSnapshot.init), steps: [], healthSteps: [], vitals: [])
        let worker = SyncPreparationWorker()
        let started = Date.now
        let first = await worker.prepare(input)
        let initialTime = Date.now.timeIntervalSince(started)
        for _ in 0..<20 { _ = await worker.prepare(input) }
        let builds = await worker.buildCount
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(first.requests.count, records.count)
        XCTAssertTrue(first.requests.allSatisfy { first.fingerprints[$0.record_key] == $0.fingerprint })
        var changed = input; changed.sleep[0].note = "Updated synthetic note"
        let second = await worker.prepare(changed)
        let changedBuilds = await worker.buildCount
        XCTAssertEqual(changedBuilds, 2)
        XCTAssertNotEqual(second.fingerprints, first.fingerprints)
        print("Synthetic sync preparation cold seconds:", initialTime, "unchanged redraws rebuilt: 0")
    }
    func testStepCorrectionsTrueZeroAndDeletedRecordsInvalidateWithoutAddingTotals() async throws {
        let worker = SyncPreparationWorker()
        let day = DeviceStepDay(device: "test", deviceName: "Synthetic", day: "2026-11-20", steps: 100, readAt: .now, dayBasis: "北京时间（UTC+8）")
        var input = SyncPreparationInput(sleep: [], steps: [day], healthSteps: [], vitals: [])
        let first = await worker.prepare(input)
        input.steps[0].steps = 0
        let zero = await worker.prepare(input)
        XCTAssertEqual(zero.requests.first?.steps?.steps, 0)
        XCTAssertNotEqual(first.fingerprints, zero.fingerprints)
        input.steps = []
        let empty = await worker.prepare(input)
        XCTAssertTrue(empty.requests.isEmpty)
        await worker.clear()
        let repeated = await worker.prepare(input)
        XCTAssertTrue(repeated.fingerprints.isEmpty)
    }
}

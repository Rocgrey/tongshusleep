import XCTest
@testable import sleeptongshu

@MainActor private final class MemoryStepsCache: StepCacheStorage {
    var values: [String: StepCache] = [:]
    func load(scope: String) throws -> StepCache? { values[scope] }
    func save(_ value: StepCache, scope: String) throws { values[scope] = value }
}

@MainActor private final class TestStepsAPI: StepsServing {
    var uploads: [StepUploadRequest] = []
    var tokens: [String] = []
    var records: [String: Int] = [:]
    var failure: APIError?
    var userID = 1
    var suspend = false
    var continuation: CheckedContinuation<CloudStepResponse, Error>?
    func upload(_ request: StepUploadRequest, token: String) async throws -> StepUpsertResult {
        if let failure { throw failure }
        uploads.append(request); tokens.append(token)
        records[request.record_date] = request.steps
        return StepUpsertResult(record_id: 1, applied: true, reason: nil, record: StepStoredRecord(id: 1, user_id: userID, record_date: request.record_date, steps: request.steps, source: request.source, data_time: request.data_time))
    }
    func fetch(_ range: StepRange, token: String) async throws -> CloudStepResponse {
        tokens.append(token)
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return response(range)
    }
    func response(_ range: StepRange) -> CloudStepResponse {
        let filtered = records.filter { range.contains($0.key) }
        let stats = StepStatistics(values: filtered, range: range)
        return CloudStepResponse(days: filtered.map { CloudStepDay(record_date: $0.key, steps: $0.value, source: "healthkit", source_id: nil, data_time: nil, updated_at: .now) },
            summary: CloudStepSummary(start_date: range.start, end_date: range.end, days_in_range: range.dates.count, days_with_record: stats.recordedDays, days_real_zero: stats.zeroDays, days_missing: stats.missingDays, range_incomplete: stats.missingDays > 0, total_steps: stats.total, avg_steps: stats.average))
    }
}

@MainActor final class AccountStepsTests: XCTestCase {
    private let range = StepRange(start: "2026-11-07", end: "2026-11-09")
    private func session(_ id: Int) -> AccountSession {
        AccountSession(user: AccountUser(id: id, username: "tester\(id)", email: nil, phone: "13800001234", createdAt: .now), accessToken: "token-\(id)", expiresAt: .distantFuture)
    }
    private func snapshot() -> HealthOverviewSnapshot {
        let values: [(String, Double)] = [("2026-11-07", 0), ("2026-11-09", 1200)]
        return HealthOverviewSnapshot(readAt: StepDates.date("2026-11-10")!, sources: [], observations: values.map { day, count in
            let date = StepDates.date(day)!
            return HealthObservation(id: day, metric: .steps, sourceID: "system-health-statistics", start: date, end: date.addingTimeInterval(3600), value: count)
        }, age: nil, stepsTimeZone: "Asia/Shanghai")
    }
    func testMissingDaysAreNotZeroAndTrueZeroParticipatesInAverage() {
        let stats = StepStatistics(values: ["2026-11-07": 0, "2026-11-09": 1200], range: range)
        XCTAssertEqual(stats.total, 1200); XCTAssertEqual(stats.average, 600)
        XCTAssertEqual(stats.zeroDays, 1); XCTAssertEqual(stats.missingDays, 1)
        XCTAssertNil(StepStatistics(values: [:], range: range).average)
        XCTAssertEqual(StepDates.format(Date(timeIntervalSince1970: 0)), "1970-01-01")
        let before = StepDates.date("2026-11-09")!.addingTimeInterval(-1)
        XCTAssertEqual(StepDates.format(before), "2026-11-08")
        XCTAssertNil(StepDates.date("2026-02-30"))
    }
    func testOnlyFreshTimezoneTaggedHealthKitTotalsAreUploadable() throws {
        var value = snapshot()
        XCTAssertEqual(LocalStepDay.read(value).map(\.steps), [0, 1200])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalStepDay.read(value)[0].request)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["record_date", "steps", "source", "source_id", "data_time", "timezone"])
        XCTAssertNil(json["user_id"])
        value.stepsTimeZone = nil
        XCTAssertTrue(LocalStepDay.read(value).isEmpty)
        value.stepsTimeZone = "Asia/Shanghai"; value.observations.append(value.observations[0])
        XCTAssertEqual(LocalStepDay.read(value).map(\.steps), [1200])
        value.truncatedMetrics = [.steps]
        XCTAssertTrue(LocalStepDay.read(value).isEmpty)
        let old = try JSONDecoder().decode(HealthOverviewSnapshot.self, from: JSONEncoder().encode(snapshotWithoutZone()))
        XCTAssertEqual(old.observations.count, 2)
        XCTAssertNil(old.stepsTimeZone)
    }
    func testRetainedStepsKeepOriginalReadTimeWhenOtherMetricsRefresh() {
        var value = snapshot()
        let original = value.readAt
        value.stepsReadAt = original
        value.readAt = original.addingTimeInterval(3600)
        XCTAssertEqual(LocalStepDay.read(value).first?.measuredAt, original)
        XCTAssertEqual(LocalStepDay.read(value).first?.request.data_time, StepDates.format(original, time: true))
    }
    private func snapshotWithoutZone() -> HealthOverviewSnapshot { var value = snapshot(); value.stepsTimeZone = nil; return value }

    func testRepeatedSyncReplacesCumulativeValueAndFetchesRealCloudResponse() async {
        let api = TestStepsAPI(), cache = MemoryStepsCache(), store = AccountStepsStore(cache: MemoryStepsCache())
        store.bind(session: session(1), serviceID: "service-a", api: api)
        await store.sync(range, snapshot: snapshot())
        await store.sync(range, snapshot: snapshot())
        XCTAssertEqual(api.uploads.count, 4)
        XCTAssertEqual(api.uploads[0], api.uploads[2])
        XCTAssertEqual(store.cloud?.summary.total_steps, 1200)
        XCTAssertEqual(store.cloud?.summary.days_with_record, 2)
        XCTAssertEqual(Set(api.tokens), ["token-1"])
        let saved = AccountStepsStore(cache: cache)
        saved.bind(session: session(1), serviceID: "service-a", api: api)
        await saved.refresh(range)
        XCTAssertEqual(cache.values.count, 1)
    }
    func testAccountAndServerCachesAreIsolatedAndOfflineNeverFabricatesCloudData() async {
        let api = TestStepsAPI(), cache = MemoryStepsCache(), store = AccountStepsStore(cache: MemoryStepsCache())
        api.records = ["2026-11-09": 400]
        let first = AccountStepsStore(cache: cache)
        first.bind(session: session(1), serviceID: "service-a", api: api)
        await first.refresh(range)
        api.failure = .network
        let second = AccountStepsStore(cache: cache)
        second.bind(session: session(1), serviceID: "service-a", api: api)
        await second.refresh(range)
        XCTAssertEqual(second.cloud?.summary.total_steps, 400)
        XCTAssertTrue(second.isCached)
        second.bind(session: session(2), serviceID: "service-a", api: api)
        XCTAssertNil(second.cloud)
        await second.refresh(range)
        XCTAssertNil(second.cloud)
        second.bind(session: session(1), serviceID: "service-b", api: api)
        await second.refresh(range)
        XCTAssertNil(second.cloud)
        store.bind(session: nil, serviceID: "service-a", api: api)
        await store.refresh(range)
        XCTAssertNil(store.cloud)
    }
    func testLateRequestCannotOverwriteNewAccountOrSaveInItsCache() async {
        let api = TestStepsAPI(), cache = MemoryStepsCache()
        let store = AccountStepsStore(cache: cache)
        store.bind(session: session(1), serviceID: "service-a", api: api)
        api.suspend = true; api.records = ["2026-11-09": 999]
        let task = Task { await store.refresh(range) }
        for _ in 0..<100 { if api.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(api.continuation)
        store.bind(session: session(2), serviceID: "service-a", api: api)
        XCTAssertNil(store.cloud); XCTAssertFalse(store.isLoading)
        api.continuation?.resume(returning: api.response(range)); api.continuation = nil
        await task.value
        XCTAssertNil(store.cloud); XCTAssertTrue(cache.values.isEmpty)
    }
    func testNewCumulativeTotalAndNoDataDoNotUploadMissingDates() async {
        let api = TestStepsAPI(), store = AccountStepsStore(cache: MemoryStepsCache())
        store.bind(session: session(1), serviceID: "service-a", api: api)
        await store.sync(range, snapshot: nil)
        XCTAssertTrue(api.uploads.isEmpty); XCTAssertNil(store.cloud)
        await store.sync(range, snapshot: snapshot())
        var changed = snapshot(); changed.observations[1].value = 1700
        await store.sync(range, snapshot: changed)
        XCTAssertEqual(store.cloud?.summary.total_steps, 1700)
        XCTAssertNil(api.records["2026-11-08"])
        api.failure = .unauthorized("已失效")
        await store.refresh(range)
        XCTAssertTrue(store.message?.contains("已失效") == true)
        store.bind(session: nil, serviceID: "service-a", api: api)
        XCTAssertNil(store.cloud); XCTAssertNil(store.fetchedAt)
    }
}

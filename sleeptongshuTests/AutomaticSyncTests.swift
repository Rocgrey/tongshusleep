import XCTest
@testable import sleeptongshu

@MainActor private final class MockAutomaticSync: AutomaticSyncServing {
    var ready = true
    var failure: APIError?
    var userID = 1
    var requests: [DeviceSyncRequest] = []
    var tokens: [String] = []
    var continuation: CheckedContinuation<DeviceSyncReceipt, Error>?
    var suspend = false
    func available(token: String) async throws -> Bool { if let failure { throw failure }; return ready }
    func upload(_ request: DeviceSyncRequest, token: String) async throws -> DeviceSyncReceipt {
        requests.append(request); tokens.append(token)
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return DeviceSyncReceipt(id: 10, user_id: userID, applied: true)
    }
}
@MainActor final class AutomaticSyncTests: XCTestCase {
    private func session(_ id: Int, token: String? = nil) -> AccountSession {
        AccountSession(user: AccountUser(id: id, username: "test", email: nil, phone: "13800001234", createdAt: .now), accessToken: token ?? "token-\(id)", expiresAt: .distantFuture)
    }
    private func request(_ steps: Int = 4221) -> DeviceSyncRequest {
        DeviceSyncRequest.step(DeviceStepDay(device: "synthetic-device", deviceName: "测试", day: "2026-11-11", steps: steps, readAt: StepDates.date("2026-11-11")!.addingTimeInterval(3600), dayBasis: "北京时间（UTC+8）"))
    }
    func testRepeatedSyncAndChangedDailyTotalUseStableKeyAndNewRevision() async throws {
        let store = AutomaticSyncStore(directory: nil), api = MockAutomaticSync()
        await store.sync([request()], session: session(1), service: "test", api: api)
        await store.sync([request()], session: session(1), service: "test", api: api)
        XCTAssertEqual(api.requests.count, 1)
        await store.sync([request(5000)], session: session(1), service: "test", api: api)
        XCTAssertEqual(api.requests.count, 2)
        XCTAssertEqual(api.requests[0].record_key, api.requests[1].record_key)
        XCTAssertGreaterThan(api.requests[1].revision_at, api.requests[0].revision_at)
        let json = try JSONSerialization.jsonObject(with: api.requests[1].encoded()) as! [String: Any]
        XCTAssertNil(json["user_id"]); XCTAssertFalse(String(decoding: try api.requests[1].encoded(), as: UTF8.self).contains("isi_score"))
    }
    func testMissingServerCapabilityDoesNotSendOrPretendSuccess() async {
        let store = AutomaticSyncStore(directory: nil), api = MockAutomaticSync(); api.ready = false
        await store.sync([request()], session: session(1), service: "test", api: api)
        XCTAssertTrue(api.requests.isEmpty); XCTAssertNil(store.lastSyncedAt)
        XCTAssertTrue(store.message.contains("本机记录已保留"))
    }
    func testTimeoutReusesPersistedRevisionAfterRelaunchAndTokenRenewal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockAutomaticSync(); api.suspend = true
        let store = AutomaticSyncStore(directory: directory)
        let first = Task { await store.sync([request()], session: session(1), service: "test", api: api) }
        while api.continuation == nil { await Task.yield() }
        api.continuation?.resume(throwing: APIError.timeout); api.continuation = nil
        await first.value
        let revision = try XCTUnwrap(api.requests.first?.revision_at)
        api.suspend = false
        let restored = AutomaticSyncStore(directory: directory)
        await restored.sync([request()], session: session(1, token: "renewed-token"), service: "test", api: api)
        XCTAssertEqual(api.requests.last?.revision_at, revision)
        let again = AutomaticSyncStore(directory: directory)
        await again.sync([request()], session: session(1, token: "another-token"), service: "test", api: api)
        XCTAssertEqual(api.requests.count, 2)
    }
    func testLogoutAndLateResponseNeverRestorePreviousAccountState() async {
        let store = AutomaticSyncStore(directory: nil), api = MockAutomaticSync(); api.suspend = true
        let task = Task { await store.sync([request()], session: session(1), service: "test", api: api) }
        while api.continuation == nil { await Task.yield() }
        store.reset()
        api.continuation?.resume(returning: DeviceSyncReceipt(id: 1, user_id: 1, applied: true)); api.continuation = nil
        await task.value
        XCTAssertNil(store.lastSyncedAt); XCTAssertFalse(store.isBusy)
        api.suspend = false; api.userID = 2
        await store.sync([request()], session: session(2), service: "test", api: api)
        XCTAssertEqual(api.tokens, ["token-1", "token-2"])
        XCTAssertNotNil(store.lastSyncedAt)
    }
    func testServiceAndAccountReceiptScopesRemainSeparate() async {
        let store = AutomaticSyncStore(directory: nil), api = MockAutomaticSync()
        await store.sync([request()], session: session(1), service: "one", api: api)
        await store.sync([request()], session: session(1), service: "two", api: api)
        api.userID = 2
        await store.sync([request()], session: session(2), service: "two", api: api)
        XCTAssertEqual(api.requests.count, 3)
    }
    func testNightObservationJSONHasMeasuredAveragesButNoInventedSleepFields() throws {
        let start = StepDates.date("2026-11-11")!
        let sample = WearableVital(device: "synthetic", deviceLabel: "测试", date: start, kind: .oxygen, value: 98, origin: "测试")
        let payload = SleepPayload(id: UUID(), start: start, end: start.addingTimeInterval(60), source: .band, segments: [], heartSamples: [], note: "",
            metadata: SleepMetadata(bioNight: BIONight(device: "synthetic", endDay: "2026-11-11", readAt: start, samples: [sample], sleepInputMinutes: 1)))
        let request = try DeviceSyncRequest.sleep(SleepRecord(payload))
        XCTAssertEqual(request.kind, "night_observation"); XCTAssertNil(request.sleep)
        XCTAssertEqual(request.details.average_spo2, 98); XCTAssertTrue(request.details.stages.isEmpty)
        let text = String(decoding: try request.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("deep_sleep_minutes")); XCTAssertFalse(text.contains("isi_score"))
    }
    func testSleepUploadContainsNightMetricsAndActualStagesOnly() throws {
        let record = try XCTUnwrap(SampleSleepRecords.makeMonth().first)
        record.sourceRawValue = SleepDataSource.band.rawValue
        record.averageSpO2 = 98; record.averageHeartRate = 62
        let request = try DeviceSyncRequest.sleep(record)
        XCTAssertEqual(request.kind, "sleep"); XCTAssertEqual(request.sleep?.deep_sleep_minutes, 102)
        XCTAssertEqual(request.sleep?.extra_meta?.average_spo2, 98)
        XCTAssertEqual(request.details.stages.count, record.segments.count)
        let json = String(decoding: try request.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("isi_score")); XCTAssertTrue(json.contains("average_heart_rate"))
    }
}

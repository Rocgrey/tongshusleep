import XCTest
@testable import sleeptongshu

private final class LiveMemorySession: AccountSessionStorage {
    var value: SavedAccountSession?
    func load() throws -> SavedAccountSession? { value }
    func save(_ value: SavedAccountSession) throws { self.value = value }
    func clear() throws { value = nil }
}

/// Explicit opt-in: keeps a synthetic account/step record and deletes its test sleep record.
/// Enable RunLiveBackendChecks in the simulator app's defaults before running this test.
@MainActor
final class LiveBackendTests: XCTestCase {
    func testDeployedSwiftLoginRestoreUploadAndLogout() async throws {
        guard UserDefaults.standard.bool(forKey: "RunLiveBackendChecks") else { throw XCTSkip("Live writes require explicit opt-in") }
        UserDefaults.standard.removeObject(forKey: "RunLiveBackendChecks")
        UserDefaults.standard.synchronize()
        let client = APIClient()
        let api = AccountAPI(client: client)
        let storage = LiveMemorySession()
        let store = AccountStore(api: api, storage: storage)
        let username = "swiftcheck_" + String(Int(Date.now.timeIntervalSince1970))
        let phone = "139" + String(format: "%08d", Int.random(in: 0...99_999_999))
        let password = UUID().uuidString
        let registered = await store.register(username: username, phone: phone, password: password, confirmation: password)
        XCTAssertTrue(registered, store.message ?? "Registration failed")
        await store.login(identifier: phone, password: password, remember: true)
        XCTAssertTrue(store.canEnter, store.message ?? "Login failed")
        let restored = AccountStore(api: api, storage: storage)
        await restored.restore()
        XCTAssertTrue(restored.canEnter, restored.message ?? "Restore failed")
        guard let user = restored.session?.user, let token = restored.session?.accessToken else { return XCTFail("No verified session") }
        XCTAssertNil(user.email)
        XCTAssertEqual(user.phone, phone)
        let stepAPI = AccountStepsAPI(client: client)
        let day = StepDates.format(.now)
        let step = StepUploadRequest(record_date: day, steps: 1234, source: "healthkit", source_id: "synthetic-swift-check", data_time: StepDates.format(.now, time: true), timezone: "Asia/Shanghai")
        let uploaded = try await stepAPI.upload(step, token: token)
        XCTAssertEqual(uploaded.record.user_id, user.id)
        _ = try await stepAPI.upload(step, token: token)
        let cloud = try await stepAPI.fetch(StepRange(start: day, end: day), token: token)
        XCTAssertEqual(cloud.days.first?.steps, 1234)
        XCTAssertEqual(cloud.summary.total_steps, 1234)
        let start = Date.now.addingTimeInterval(-9 * 3600)
        let record = SleepRecord(SleepPayload(id: UUID(), start: start, end: start.addingTimeInterval(8 * 3600), source: .manual,
                                               segments: [], heartSamples: [], note: "AUTOMATED SWIFT CHECK - synthetic record"))
        let request = try SleepUploadRequest(record: record, ais: 2)
        let result = try await SleepUploadAPI(client: client).upload(request)
        XCTAssertEqual(result.user_id, user.id)
        _ = try await client.request("health/sleep-record/\(result.id)", method: "DELETE", authenticated: true)
        await restored.signOut()
        XCTAssertFalse(restored.canEnter)
        XCTAssertNil(storage.value)
        do { _ = try await api.me(token: token); XCTFail("Revoked JWT was accepted") }
        catch { XCTAssertTrue((error as? APIError)?.isUnauthorized == true) }
        print("Live Swift contract passed. Synthetic account and step record retained: \(username); test sleep record deleted.")
    }
}

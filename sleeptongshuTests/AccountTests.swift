import XCTest
@testable import sleeptongshu

private final class AccountURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class AccountAPITests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountURLProtocol.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() { session.invalidateAndCancel(); AccountURLProtocol.handler = nil }
    private var api: AccountAPI { AccountAPI(baseURL: "https://account.example.test/api/v1", session: session) }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let direct = request.httpBody { data = direct }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        } else { throw AccountError.invalidResponse }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private var sessionJSON: Data {
        Data("""
        {"user":{"id":"test-user","username":"sleeper","displayName":"Test","createdAt":"2026-01-01T00:00:00.000Z"},"accessToken":"test-only-token","expiresAt":"2099-01-01T00:00:00Z"}
        """.utf8)
    }

    func testRegistrationSendsExpectedFieldsAndDecodesBothISODateFormats() async throws {
        AccountURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/register")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let fields = try body(request)
            XCTAssertEqual(Set(fields.keys), ["username", "password", "displayName"])
            XCTAssertEqual(fields["password"] as? String, "test-pass-only")
            XCTAssertEqual(fields["displayName"] as? String, "Test")
            return (201, sessionJSON)
        }
        let result = try await api.register(username: "sleeper", password: "test-pass-only", displayName: "Test")
        XCTAssertEqual(result.user.id, "test-user")
        XCTAssertEqual(result.accessToken, "test-only-token")
        XCTAssertTrue(result.expiresAt > .now)
    }

    func testMeAndLogoutUseBearerAndNeverSendAPassword() async throws {
        AccountURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-token")
            XCTAssertNil(request.httpBody)
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
                let object = try JSONSerialization.jsonObject(with: sessionJSON) as! [String: Any]
                return (200, try JSONSerialization.data(withJSONObject: object["user"]!))
            }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
            return (204, Data())
        }
        let user = try await api.me(token: "test-only-token")
        XCTAssertEqual(user.username, "sleeper")
        try await api.logout(token: "test-only-token")
    }

    func testErrorsAreMappedWithoutShowingRawServerContent() async {
        for (status, expected) in [(401, AccountError.invalidCredentials), (409, .usernameTaken), (429, .rateLimited),
                                   (500, .unavailable), (302, .invalidResponse)] {
            AccountURLProtocol.handler = { _ in (status, Data("internal debug details".utf8)) }
            do { _ = try await api.login(username: "sleeper", password: "test-pass-only"); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? AccountError, expected) }
        }
    }

    func testMalformedAndExpiredSessionsCannotAuthenticate() async {
        for data in [Data("{}".utf8), Data(String(decoding: sessionJSON, as: UTF8.self).replacingOccurrences(of: "2099-01-01", with: "2000-01-01").utf8)] {
            AccountURLProtocol.handler = { _ in (200, data) }
            do { _ = try await api.login(username: "sleeper", password: "test-pass-only"); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? AccountError, .invalidResponse) }
        }
    }

    func testUnconfiguredAndInsecureServicesMakeNoRequest() async {
        AccountURLProtocol.handler = { _ in XCTFail("No request expected"); return (500, Data()) }
        for address in ["", "http://example.test", "https://user:pass@example.test", "$(SLEEP_API_BASE_URL)"] {
            let service = AccountAPI(baseURL: address, session: session)
            XCTAssertFalse(service.isConfigured)
            do { _ = try await service.login(username: "sleeper", password: "test-pass-only"); XCTFail("Expected error") }
            catch { XCTAssertTrue(error is AccountError) }
        }
    }
}

private final class MemoryAccountStorage: AccountSessionStorage {
    var saved: SavedAccountSession?
    var failSave = false
    func load() throws -> SavedAccountSession? { saved }
    func save(_ value: SavedAccountSession) throws { if failSave { throw AccountError.secureStorage }; saved = value }
    func clear() throws { saved = nil }
}

private final class FakeAccountService: AccountServing {
    var isConfigured = true
    let serviceID = "https://account.example.test/api/v1"
    var result = AccountSession(user: AccountUser(id: "test-id", username: "sleeper", displayName: "Test", createdAt: .now),
                                accessToken: "test-only-token", expiresAt: .now.addingTimeInterval(3600))
    var error: AccountError?
    var logoutCount = 0
    var loginCount = 0
    var meCount = 0
    func login(username: String, password: String) async throws -> AccountSession {
        loginCount += 1
        if let error { throw error }
        return result
    }
    func register(username: String, password: String, displayName: String) async throws -> AccountSession {
        try await login(username: username, password: password)
    }
    func me(token: String) async throws -> AccountUser { meCount += 1; if let error { throw error }; return result.user }
    func logout(token: String) async throws { logoutCount += 1 }
}

@MainActor
final class AccountStoreTests: XCTestCase {
    func testUnconfiguredPreviewIsNotALoggedInAccount() async {
        let api = FakeAccountService(); api.isConfigured = false
        let storage = MemoryAccountStorage()
        let store = AccountStore(api: api, storage: storage)
        await store.restore()
        XCTAssertFalse(store.canEnter)
        await store.submit(register: true, username: "sleeper", password: "test-pass-only", confirmation: "test-pass-only", displayName: "Test")
        XCTAssertNotNil(store.message)
        XCTAssertEqual(api.loginCount, 0)
        store.preview()
        XCTAssertTrue(store.canEnter)
        XCTAssertTrue(store.isPreview)
        XCTAssertNil(store.session)
        XCTAssertNil(storage.saved)
        store.leavePreview()
        XCTAssertFalse(store.canEnter)
    }

    func testRegistrationValidationAndSessionPersistenceThenSignOut() async {
        let api = FakeAccountService(); let storage = MemoryAccountStorage()
        let store = AccountStore(api: api, storage: storage)
        await store.restore()
        await store.submit(register: true, username: " sleeper ", password: "test-pass-only", confirmation: "mismatch", displayName: "Test")
        XCTAssertEqual(api.loginCount, 0)
        XCTAssertFalse(store.canEnter)
        await store.submit(register: true, username: " sleeper ", password: "test-pass-only", confirmation: "test-pass-only", displayName: "Test")
        XCTAssertTrue(store.canEnter)
        XCTAssertEqual(storage.saved?.session, api.result)
        XCTAssertEqual(storage.saved?.serviceID, api.serviceID)
        XCTAssertFalse(store.isLoading)
        store.preview()
        XCTAssertFalse(store.isPreview)
        await store.signOut()
        XCTAssertNil(storage.saved)
        XCTAssertFalse(store.canEnter)
        XCTAssertEqual(api.logoutCount, 1)
    }

    func testStorageFailureDoesNotEnterAppAndRevokesNewToken() async {
        let api = FakeAccountService(); let storage = MemoryAccountStorage(); storage.failSave = true
        let store = AccountStore(api: api, storage: storage)
        await store.submit(register: false, username: "sleeper", password: "test-pass-only", confirmation: "", displayName: "")
        XCTAssertFalse(store.canEnter)
        XCTAssertEqual(api.logoutCount, 1)
        XCTAssertNotNil(store.message)
    }

    func testRestoreChecksServerAndDoesNotSendTokenToDifferentService() async {
        let api = FakeAccountService(); let storage = MemoryAccountStorage()
        storage.saved = SavedAccountSession(serviceID: "https://other.example.test", session: api.result)
        let wrong = AccountStore(api: api, storage: storage)
        await wrong.restore()
        XCTAssertFalse(wrong.canEnter)
        XCTAssertEqual(api.meCount, 0)
        storage.saved = SavedAccountSession(serviceID: api.serviceID, session: api.result)
        let store = AccountStore(api: api, storage: storage)
        await store.restore()
        XCTAssertTrue(store.canEnter)
        XCTAssertEqual(api.meCount, 1)
    }

    func testExpiredOrRevokedSessionReturnsToLogin() async {
        let api = FakeAccountService(); let storage = MemoryAccountStorage()
        var expired = api.result; expired.expiresAt = .distantPast
        storage.saved = SavedAccountSession(serviceID: api.serviceID, session: expired)
        let store = AccountStore(api: api, storage: storage)
        await store.restore()
        XCTAssertFalse(store.canEnter)
        XCTAssertNil(storage.saved)
        XCTAssertEqual(api.meCount, 0)
        storage.saved = SavedAccountSession(serviceID: api.serviceID, session: api.result)
        api.error = .expired
        let revoked = AccountStore(api: api, storage: storage)
        await revoked.restore()
        XCTAssertFalse(revoked.canEnter)
        XCTAssertNil(storage.saved)
    }
}

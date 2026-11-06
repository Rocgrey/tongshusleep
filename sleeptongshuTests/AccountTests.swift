import XCTest
@testable import sleeptongshu

private final class AccountURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private final class MemoryAccountStorage: AccountSessionStorage {
    var saved: SavedAccountSession?
    var failSave = false
    func load() throws -> SavedAccountSession? { saved }
    func save(_ value: SavedAccountSession) throws { if failSave { throw APIError.secureStorage }; saved = value }
    func clear() throws { saved = nil }
}

@MainActor
final class AccountTests: XCTestCase {
    private var transport: URLSession!
    private var client: APIClient!
    private var api: AccountAPI!
    private var storage: MemoryAccountStorage!
    private let userJSON = Data(#"{"id":7,"username":"同书test","email":"test@example.com","created_at":"2026-11-06T08:00:00.123456","updated_at":"2026-11-06T08:00:00Z","is_active":true}"#.utf8)
    private var loginJSON: Data {
        Data(#"{"access_token":"test-only-jwt","token_type":"bearer","expire_at":4070908800}"#.utf8)
    }
    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountURLProtocol.self]
        transport = URLSession(configuration: config)
        client = APIClient(configuration: APIConfiguration(baseURL: "https://api.example.test/api/v1"), session: transport)
        api = AccountAPI(client: client)
        storage = MemoryAccountStorage()
    }
    override func tearDown() async throws { transport.invalidateAndCancel(); AccountURLProtocol.handler = nil }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func normalResponses(_ request: URLRequest) -> (Int, Data) {
        switch request.url!.path {
        case "/api/v1/auth/login": (200, loginJSON)
        case "/api/v1/auth/me": (200, userJSON)
        case "/api/v1/auth/logout": (200, Data(#"{"message":"登出成功"}"#.utf8))
        default: (201, Data(#"{"message":"注册成功"}"#.utf8))
        }
    }

    func testRegisterAndLoginUseOnlyBackendFieldsAndRegisterDoesNotAuthenticate() async throws {
        let store = AccountStore(api: api, storage: storage)
        var paths: [String] = []
        AccountURLProtocol.handler = { [self] request in
            let path = request.url!.path
            paths.append(path)
            if path.hasSuffix("register") {
                let json = try body(request)
                XCTAssertEqual(Set(json.keys), ["username", "email", "password"])
                XCTAssertEqual(json["username"] as? String, "同书test")
            } else if path.hasSuffix("login") {
                XCTAssertEqual(Set(try body(request).keys), ["email", "password"])
            } else if path.hasSuffix("me") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-jwt")
            }
            return normalResponses(request)
        }
        let registered = await store.register(username: "同书test", email: " test@example.com ", password: "test-pass", confirmation: "test-pass")
        XCTAssertTrue(registered)
        XCTAssertFalse(store.canEnter)
        XCTAssertNil(storage.saved)
        XCTAssertEqual(paths, ["/api/v1/auth/register"])
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        XCTAssertTrue(store.canEnter)
        XCTAssertEqual(storage.saved?.session.user.email, "test@example.com")
        XCTAssertEqual(paths.suffix(2), ["/api/v1/auth/login", "/api/v1/auth/me"])
    }

    func testRememberOffKeepsSessionInMemoryOnly() async {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: false)
        XCTAssertTrue(store.canEnter)
        XCTAssertNil(storage.saved)
    }

    func testRestoreCallsMeAndRevokedSessionClearsCredentials() async {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let first = AccountStore(api: api, storage: storage)
        await first.login(email: "test@example.com", password: "test-pass", remember: true)
        let restored = AccountStore(api: api, storage: storage)
        await restored.restore()
        XCTAssertTrue(restored.canEnter)
        AccountURLProtocol.handler = { _ in (401, Data(#"{"detail":"未登录或凭证无效"}"#.utf8)) }
        let revoked = AccountStore(api: api, storage: storage)
        await revoked.restore()
        XCTAssertNil(revoked.session)
        XCTAssertNil(storage.saved)
    }

    func testUpload401ClearsLoginAndReturnsToPendingUploadAfterLogin() async throws {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        let id = UUID()
        store.open(.upload(id))
        AccountURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-jwt")
            return (401, Data(#"{"detail":"凭证已过期"}"#.utf8))
        }
        do { _ = try await client.request("health/sleep-record", method: "POST", body: Data("{}".utf8), authenticated: true); XCTFail() }
        catch { XCTAssertTrue((error as? APIError)?.isUnauthorized == true) }
        XCTAssertNil(store.session)
        XCTAssertNil(storage.saved)
        XCTAssertEqual(store.pendingDestination, .upload(id))
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        XCTAssertEqual(store.presentedDestination, .upload(id))
    }

    func testOldUnauthorizedResponseCannotClearNewerSession() async {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        client.onUnauthorized?("old-token", "旧会话已过期")
        XCTAssertTrue(store.canEnter)
    }

    func testExpiredTokenAndDifferentServerAreNeverSent() async {
        AccountURLProtocol.handler = { _ in XCTFail("No network call expected"); return (500, Data()) }
        let user = AccountUser(id: 1, username: "test", email: "t@example.com", createdAt: .now)
        storage.saved = SavedAccountSession(serviceID: client.serviceID, session: AccountSession(user: user, accessToken: "old", expiresAt: .distantPast))
        let store = AccountStore(api: api, storage: storage)
        await store.restore()
        XCTAssertNil(storage.saved)
        XCTAssertFalse(store.canEnter)
        storage.saved = SavedAccountSession(serviceID: "https://other.test", session: AccountSession(user: user, accessToken: "other", expiresAt: .distantFuture))
        await AccountStore(api: api, storage: storage).restore()
        XCTAssertNil(storage.saved)
    }

    func testLogoutClearsLocalCredentialsEvenWhenOffline() async {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        AccountURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.signOut()
        XCTAssertFalse(store.canEnter)
        XCTAssertNil(storage.saved)
        XCTAssertTrue(store.message?.contains("本机已退出") == true)
    }

    func testStorageFailureRevokesNewTokenAndNeverEnters() async {
        var revoked = false
        AccountURLProtocol.handler = { [self] request in
            if request.url!.path.hasSuffix("logout") { revoked = true }
            return normalResponses(request)
        }
        storage.failSave = true
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        XCTAssertFalse(store.canEnter)
        XCTAssertTrue(revoked)
    }

    func testErrorTextAndValidationListsArePreservedWithoutEchoingSensitiveInput() async {
        for (status, raw, expected) in [
            (409, #"{"detail":"邮箱已被注册"}"#, "邮箱已被注册"),
            (409, #"{"detail":"用户名已被占用"}"#, "用户名已被占用"),
            (422, #"{"detail":[{"msg":"value is not a valid email","input":"secret"}]}"#, "value is not a valid email"),
            (400, #"{"message":"格式错误"}"#, "格式错误")
        ] {
            XCTAssertEqual(APIClient.errorMessage(Data(raw.utf8), status: status), expected)
        }
        AccountURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await api.me(token: "test"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .timeout) }
    }

    func testInvalidConfigurationAndUnauthenticatedUploadMakeNoRequests() async {
        AccountURLProtocol.handler = { _ in XCTFail("No request expected"); return (500, Data()) }
        for address in ["http://test.com", "https://user:pass@test.com", "https://test.com/?secret=1"] {
            XCTAssertNil(APIConfiguration(baseURL: address).baseURL)
        }
        do { _ = try await client.request("health/sleep-record", authenticated: true); XCTFail() }
        catch { XCTAssertTrue((error as? APIError)?.isUnauthorized == true) }
    }

    func testFormValidationUsesBackendLimits() throws {
        XCTAssertNoThrow(try AccountInput.validate(email: "t@example.com", password: "123456", username: "同书test", confirmation: "123456"))
        XCTAssertThrowsError(try AccountInput.validate(email: "invalid", password: "123456"))
        XCTAssertThrowsError(try AccountInput.validate(email: "t@example.com", password: "12345", username: "tester"))
        XCTAssertThrowsError(try AccountInput.validate(email: "t@example.com", password: "123456", username: "tester", confirmation: "different"))
        XCTAssertThrowsError(try AccountInput.validate(email: "t@example.com", password: String(repeating: "中", count: 30), username: "tester"))
    }

    func testGatewayBootstrapIsSeparateFromAPIAndOnlyConfiguredGatewayReceivesFallbackHeader() async throws {
        let gatewayClient = APIClient(configuration: APIConfiguration(baseURL: "https://api.example.test/api/v1", gatewayCode: "test-only"), session: transport)
        var paths: [String] = []
        AccountURLProtocol.handler = { [self] request in
            paths.append(request.url!.path)
            if request.url!.path == "/" {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "sharecode")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (200, Data())
            }
            XCTAssertNil(request.url!.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Token"), "Bearer test")
            return (200, userJSON)
        }
        _ = try await gatewayClient.request("auth/me", authenticated: true, token: "test")
        _ = try await gatewayClient.request("auth/me", authenticated: true, token: "test")
        XCTAssertEqual(paths, ["/", "/api/v1/auth/me", "/api/v1/auth/me"])
    }
}

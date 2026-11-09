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

    func testPhoneOnlyRegistrationLoginRestoreAndLogoutWithoutEmail() async throws {
        let phoneUser = Data(#"{"id":71,"username":"phone_test","phone":"13800001234","email":null,"created_at":"2026-11-09T08:00:00Z"}"#.utf8)
        let store = AccountStore(api: api, storage: storage)
        AccountURLProtocol.handler = { [self] request in
            if request.url!.path.hasSuffix("register") {
                let json = try body(request)
                XCTAssertEqual(Set(json.keys), ["username", "phone", "password"])
                XCTAssertEqual(json["phone"] as? String, "13800001234")
                return (201, Data(#"{"message":"注册成功"}"#.utf8))
            }
            if request.url!.path.hasSuffix("login") {
                let json = try body(request)
                XCTAssertEqual(Set(json.keys), ["phone", "password"])
                XCTAssertEqual(json["phone"] as? String, "13800001234")
                return (200, loginJSON)
            }
            if request.url!.path.hasSuffix("me") { return (200, phoneUser) }
            return (200, Data("{}".utf8))
        }
        let registered = await store.register(username: "phone_test", phone: "+86 138-0000-1234", email: "", password: "123456", confirmation: "123456")
        XCTAssertTrue(registered)
        await store.login(identifier: "+86 138-0000-1234", password: "123456", remember: true)
        XCTAssertEqual(store.session?.user.id, 71)
        XCTAssertNil(store.session?.user.email)
        XCTAssertEqual(storage.saved?.session.user.phone, "13800001234")
        let restored = AccountStore(api: api, storage: storage)
        await restored.restore()
        XCTAssertEqual(restored.session?.user.id, 71)
        await restored.signOut()
        XCTAssertNil(restored.session)
        XCTAssertNil(storage.saved)
        let missingEmail = try APIJSON.decode(AccountUser.self, from: Data(#"{"id":71,"username":"phone_test","phone":"13800001234","created_at":"2026-11-09T08:00:00Z"}"#.utf8))
        XCTAssertEqual(missingEmail.id, 71)
        XCTAssertNil(missingEmail.email)
    }

    func testPhoneValidationAndServerErrorsNeverInventAnEmail() async {
        let store = AccountStore(api: api, storage: storage)
        AccountURLProtocol.handler = { _ in XCTFail("Invalid input must not make a request"); return (500, Data()) }
        await store.login(identifier: "123", password: "test-pass", remember: true)
        XCTAssertNil(store.session)
        let invalid = await store.register(username: "tester", phone: "123", password: "123456", confirmation: "123456")
        XCTAssertFalse(invalid)
        for (status, text) in [(409, "手机号已被注册"), (401, "账号不存在或密码错误"), (422, "手机号格式错误")] {
            AccountURLProtocol.handler = { _ in (status, try JSONSerialization.data(withJSONObject: ["detail": text])) }
            await store.login(identifier: "13800001234", password: "test-pass", remember: true)
            XCTAssertEqual(store.message, text)
            XCTAssertNil(store.session)
        }
    }

    func testOldKeychainSessionWithoutPhoneStillDecodes() throws {
        let old = SavedAccountSession(serviceID: "service", session: AccountSession(user: AccountUser(id: 7, username: "legacy", email: "old@example.com", createdAt: .now), accessToken: "legacy-token", expiresAt: .distantFuture))
        let data = try JSONEncoder().encode(old)
        let restored = try JSONDecoder().decode(SavedAccountSession.self, from: data)
        XCTAssertNil(restored.session.user.phone)
        XCTAssertEqual(restored.session.user.id, 7)
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

    func testStepRequestsUseExactContractQueryAndCapturedBearerAnd401ClearsSession() async throws {
        AccountURLProtocol.handler = { [self] in normalResponses($0) }
        let store = AccountStore(api: api, storage: storage)
        await store.login(email: "test@example.com", password: "test-pass", remember: true)
        let steps = AccountStepsAPI(client: client)
        AccountURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-jwt")
            XCTAssertEqual(request.url?.path, "/api/v1/health/step-record")
            let json = try body(request)
            XCTAssertNil(json["user_id"])
            XCTAssertEqual(json["steps"] as? Int, 0)
            return (200, Data(#"{"record_id":1,"applied":true,"record":{"id":1,"user_id":7,"record_date":"2026-11-09","steps":0,"source":"healthkit","data_time":"2026-11-09 12:00:00"}}"#.utf8))
        }
        let upload = StepUploadRequest(record_date: "2026-11-09", steps: 0, source: "healthkit", source_id: "system-health-statistics", data_time: "2026-11-09 12:00:00", timezone: "Asia/Shanghai")
        let result = try await steps.upload(upload, token: "test-only-jwt")
        XCTAssertEqual(result.record.user_id, 7)
        AccountURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/health/step-records")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) }), ["start_date": "2026-11-07", "end_date": "2026-11-09"])
            return (401, Data(#"{"detail":"登录已过期"}"#.utf8))
        }
        do { _ = try await steps.fetch(StepRange(start: "2026-11-07", end: "2026-11-09"), token: "test-only-jwt"); XCTFail() }
        catch { XCTAssertTrue((error as? APIError)?.isUnauthorized == true) }
        XCTAssertNil(store.session); XCTAssertNil(storage.saved)
    }
}

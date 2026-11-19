import XCTest
@testable import sleeptongshu

private final class RecoveryTransport: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class PasswordRecoveryTests: XCTestCase {
    private var transport: URLSession!
    private var client: APIClient!
    private var api: PasswordRecoveryAPI!
    private var challenge: Data {
        Data(#"{"request_id":"synthetic-request","expires_at":4070908800,"retry_after":60,"message":"若资料匹配，验证码将发送至对应邮箱。"}"#.utf8)
    }
    override func setUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryTransport.self]
        transport = URLSession(configuration: configuration)
        client = APIClient(configuration: APIConfiguration(baseURL: "https://recovery.example.test/api/v1"), session: transport)
        api = PasswordRecoveryAPI(client: client, enabled: true)
    }
    override func tearDown() async throws {
        transport.invalidateAndCancel(); RecoveryTransport.handler = nil
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func testDisabledServiceNeverRequestsUnimplementedRoutes() async throws {
        RecoveryTransport.handler = { _ in XCTFail("No online recovery route is deployed yet"); return (200, Data()) }
        let disabled = PasswordRecoveryAPI(client: client, enabled: false)
        let store = PasswordRecoveryStore(api: disabled)
        await store.request(method: .phone, phone: "13800001234", email: "test@example.com")
        XCTAssertNil(store.challenge); XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.message, PasswordRecoveryAPI.unavailableMessage)
        do { _ = try await disabled.confirm(requestID: "test", code: "123456", password: "test-pass"); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, PasswordRecoveryAPI.unavailableMessage) }
    }
    func testPhoneRecoveryRequiresPhoneAndExistingEmailAndUsesNoBearerToken() async throws {
        client.tokenProvider = { "must-not-be-sent" }
        RecoveryTransport.handler = { [self] request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/password-reset/request")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let json = try body(request)
            XCTAssertEqual(Set(json.keys), ["phone", "email"])
            XCTAssertEqual(json["phone"] as? String, "13800001234")
            XCTAssertEqual(json["email"] as? String, "test@example.com")
            return (200, challenge)
        }
        let store = PasswordRecoveryStore(api: api)
        await store.request(method: .phone, phone: "+86 138-0000-1234", email: " test@example.com ")
        XCTAssertEqual(store.challenge?.request_id, "synthetic-request")
        XCTAssertNotNil(store.retryAt); XCTAssertFalse(store.isComplete)
    }
    func testLegacyEmailResetSendsOnlyExactContractFieldsAndDoesNotLogin() async throws {
        var paths: [String] = []
        RecoveryTransport.handler = { [self] request in
            paths.append(request.url!.path)
            let json = try body(request)
            if request.url!.path.hasSuffix("/request") {
                XCTAssertEqual(Set(json.keys), ["email"])
                return (200, challenge)
            }
            XCTAssertEqual(Set(json.keys), ["request_id", "code", "new_password"])
            XCTAssertEqual(json["request_id"] as? String, "synthetic-request")
            XCTAssertEqual(json["code"] as? String, "123456")
            XCTAssertEqual(json["new_password"] as? String, "test-pass")
            return (200, Data(#"{"message":"密码已更新，请重新登录。"}"#.utf8))
        }
        let store = PasswordRecoveryStore(api: api)
        await store.request(method: .email, phone: "", email: "test@example.com")
        await store.confirm(code: "123456", password: "test-pass", confirmation: "test-pass")
        XCTAssertTrue(store.isComplete); XCTAssertNil(store.challenge)
        XCTAssertEqual(paths, ["/api/v1/auth/password-reset/request", "/api/v1/auth/password-reset/confirm"])
    }
    func testInvalidInputAndRepeatClickDoNotSendExtraRequests() async {
        var calls = 0
        RecoveryTransport.handler = { [self] _ in calls += 1; return (200, challenge) }
        let store = PasswordRecoveryStore(api: api)
        await store.request(method: .phone, phone: "123", email: "test@example.com")
        await store.request(method: .phone, phone: "13800001234", email: "invalid")
        XCTAssertEqual(calls, 0)
        async let first: Void = store.request(method: .phone, phone: "13800001234", email: "test@example.com")
        async let second: Void = store.request(method: .phone, phone: "13800001234", email: "test@example.com")
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
        for (code, password, confirmation) in [("123", "test-pass", "test-pass"),
            ("１２３４５６", "test-pass", "test-pass"), ("123456", "123", "123"), ("123456", "test-pass", "other-pass")] {
            await store.confirm(code: code, password: password, confirmation: confirmation)
            XCTAssertFalse(store.isComplete)
        }
        XCTAssertEqual(calls, 1)
    }
    func testInvalidExpiredOrUsedCodesShowServerErrorAndAllowAnotherAttempt() async {
        let store = PasswordRecoveryStore(api: api)
        RecoveryTransport.handler = { [self] _ in (200, challenge) }
        await store.request(method: .email, phone: "", email: "test@example.com")
        for text in ["验证码错误或已过期，请重新获取。", "验证次数过多，请重新获取。"] {
            RecoveryTransport.handler = { _ in (400, try JSONSerialization.data(withJSONObject: ["detail": text])) }
            await store.confirm(code: "123456", password: "test-pass", confirmation: "test-pass")
            XCTAssertEqual(store.message, text); XCTAssertFalse(store.isComplete); XCTAssertFalse(store.isLoading)
        }
    }
    func testNetworkAndRateLimitNeverReportSuccessfulDelivery() async {
        for (status, text) in [(429, "操作过于频繁，请稍后再试。"), (503, "邮件服务暂不可用，请稍后再试。")] {
            let store = PasswordRecoveryStore(api: api)
            RecoveryTransport.handler = { _ in (status, try JSONSerialization.data(withJSONObject: ["detail": text])) }
            await store.request(method: .email, phone: "", email: "test@example.com")
            XCTAssertEqual(store.message, text); XCTAssertNil(store.challenge); XCTAssertNil(store.retryAt)
        }
        for code in [URLError.Code.notConnectedToInternet, .timedOut] {
            let store = PasswordRecoveryStore(api: api)
            RecoveryTransport.handler = { _ in throw URLError(code) }
            await store.request(method: .email, phone: "", email: "test@example.com")
            XCTAssertNil(store.challenge); XCTAssertFalse(store.isLoading)
            XCTAssertEqual(store.message, code == .timedOut ? "连接超时，请稍后再试。" : APIError.network.localizedDescription)
        }
    }
    func testMalformedChallengeDoesNotOpenCodeEntry() async {
        for json in [#"{"request_id":"","expires_at":4070908800,"retry_after":60,"message":"test"}"#,
            #"{"request_id":"test","expires_at":1,"retry_after":60,"message":"test"}"#,
            #"{"request_id":"test","expires_at":4070908800,"retry_after":0,"message":"test"}"#] {
            let store = PasswordRecoveryStore(api: api)
            RecoveryTransport.handler = { _ in (200, Data(json.utf8)) }
            await store.request(method: .email, phone: "", email: "test@example.com")
            XCTAssertNil(store.challenge); XCTAssertEqual(store.message, APIError.invalidResponse.localizedDescription)
        }
    }
}

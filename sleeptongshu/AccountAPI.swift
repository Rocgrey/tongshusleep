import Foundation

struct AccountUser: Codable, Equatable, Identifiable {
    var id: String
    var username: String
    var displayName: String
    var createdAt: Date
}

struct AccountSession: Codable, Equatable {
    var user: AccountUser
    var accessToken: String
    var expiresAt: Date
}

enum AccountError: LocalizedError, Equatable {
    case notConfigured, insecureEndpoint, invalidCredentials, usernameTaken, rateLimited
    case invalidResponse, unavailable, expired, secureStorage, invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "账号服务还在准备，暂时可以预览本机功能。"
        case .insecureEndpoint: "账号服务地址需要使用安全连接，请联系开发者。"
        case .invalidCredentials: "账号或密码不正确，请再检查一下。"
        case .usernameTaken: "这个账号已被使用，可以换一个或返回登录。"
        case .rateLimited: "操作有些频繁，请稍后再试。"
        case .invalidResponse: "账号服务返回的信息不完整，请稍后再试。"
        case .unavailable: "暂时无法连接账号服务，请检查网络后重试。"
        case .expired: "登录已到期，请重新登录。"
        case .secureStorage: "登录信息未能安全保存，请重试。"
        case .invalidInput(let message): message
        }
    }
}

enum AccountInput {
    static func username(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func validate(username: String, password: String, confirmation: String? = nil, displayName: String = "") throws {
        guard username.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil else {
            throw AccountError.invalidInput("账号用 3～32 位字母、数字或下划线。")
        }
        guard (8...128).contains(password.count) else {
            throw AccountError.invalidInput("密码需要 8～128 个字符。")
        }
        if let confirmation, confirmation != password {
            throw AccountError.invalidInput("两次密码不一致，请检查后再注册。")
        }
        guard displayName.count <= 40 else { throw AccountError.invalidInput("昵称最多 40 个字符。") }
    }
}

protocol AccountServing {
    var isConfigured: Bool { get }
    var serviceID: String { get }
    func login(username: String, password: String) async throws -> AccountSession
    func register(username: String, password: String, displayName: String) async throws -> AccountSession
    func me(token: String) async throws -> AccountUser
    func logout(token: String) async throws
}

// Refuse redirects so passwords and bearer tokens cannot be forwarded to another origin.
private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class AccountAPI: AccountServing {
    private let baseURL: URL?
    private let session: URLSession
    private let invalidConfiguration: Bool
    var isConfigured: Bool { baseURL != nil }
    var serviceID: String { baseURL?.absoluteString ?? "unconfigured" }

    init(baseURL: String = Bundle.main.object(forInfoDictionaryKey: "SleepAPIBaseURL") as? String ?? "",
         session: URLSession? = nil) {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw), url.scheme == "https", url.host != nil,
           url.user == nil, url.password == nil, url.query == nil, url.fragment == nil {
            self.baseURL = url
            invalidConfiguration = false
        } else {
            self.baseURL = nil
            invalidConfiguration = !raw.isEmpty && !raw.hasPrefix("$(")
        }
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil)
        }
    }

    func login(username: String, password: String) async throws -> AccountSession {
        struct Body: Encodable { let username: String; let password: String }
        return try await authenticate(path: "auth/login", body: JSONEncoder().encode(Body(username: username, password: password)))
    }
    func register(username: String, password: String, displayName: String) async throws -> AccountSession {
        struct Body: Encodable { let username: String; let password: String; let displayName: String }
        return try await authenticate(path: "auth/register", body: JSONEncoder().encode(Body(username: username, password: password, displayName: displayName)))
    }
    private func authenticate(path: String, body: Data) async throws -> AccountSession {
        let data = try await request(path: path, method: "POST", body: body)
        let result: AccountSession = try decode(data)
        guard !result.accessToken.isEmpty, !result.accessToken.contains(where: { $0.isWhitespace || $0.isNewline }),
              result.expiresAt > .now, !result.user.id.isEmpty, !result.user.username.isEmpty else { throw AccountError.invalidResponse }
        return result
    }
    func me(token: String) async throws -> AccountUser {
        let data = try await request(path: "auth/me", method: "GET", token: token)
        let user: AccountUser = try decode(data)
        guard !user.id.isEmpty, !user.username.isEmpty else { throw AccountError.invalidResponse }
        return user
    }
    func logout(token: String) async throws { _ = try await request(path: "auth/logout", method: "POST", token: token) }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw AccountError.invalidResponse
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw AccountError.invalidResponse }
    }
    private func request(path: String, method: String, body: Data? = nil, token: String? = nil) async throws -> Data {
        guard let baseURL else { throw invalidConfiguration ? AccountError.insecureEndpoint : AccountError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AccountError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw token == nil ? AccountError.invalidCredentials : AccountError.expired
        case 409: throw AccountError.usernameTaken
        case 429: throw AccountError.rateLimited
        case 500...599: throw AccountError.unavailable
        default: throw AccountError.invalidResponse
        }
    }
}

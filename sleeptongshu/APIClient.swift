import Foundation

/// Shared API prefix; gateway access is separate from the user's JWT session.
struct APIConfiguration {
    static let defaultBaseURL = "https://tongshusleep-backend.app.workbuddy.host/api/v1"
    let baseURL: URL?
    let gatewayCode: String
    init(baseURL: String, gatewayCode: String = "") {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.scheme == "https", url.host != nil,
           url.user == nil, url.password == nil, url.query == nil, url.fragment == nil {
            self.baseURL = url
        } else { self.baseURL = nil }
        self.gatewayCode = gatewayCode.hasPrefix("$(") ? "" : gatewayCode
    }
    static var app: APIConfiguration {
        let value = Bundle.main.object(forInfoDictionaryKey: "SleepAPIBaseURL") as? String ?? ""
        let address = value.isEmpty || value.hasPrefix("$(") ? defaultBaseURL : value
        return APIConfiguration(baseURL: address, gatewayCode: Bundle.main.object(forInfoDictionaryKey: "SleepGatewayShareCode") as? String ?? "")
    }
}

enum APIError: LocalizedError, Equatable {
    case configuration, network, timeout, invalidResponse, secureStorage
    case unauthorized(String), business(Int, String), validation(String)
    var errorDescription: String? {
        switch self {
        case .configuration: "账号服务地址未正确配置，请联系开发者。"
        case .network: "暂时无法连接服务，请检查网络后重试。"
        case .timeout: "连接超时，请稍后再试。上传结果请先到平台核对，避免重复。"
        case .invalidResponse: "服务返回的信息不完整，请稍后再试。"
        case .secureStorage: "登录凭证未能安全保存，请重试。"
        case .unauthorized(let message), .business(_, let message), .validation(let message): message
        }
    }
    var isUnauthorized: Bool { if case .unauthorized = self { return true }; return false }
}

private final class APIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    // Never forward passwords or tokens to a redirect target.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// All protected requests obtain the current token here and share one 401 handler.
@MainActor
final class APIClient {
    let configuration: APIConfiguration
    private let session: URLSession
    private var gatewayTask: Task<Void, Error>?
    var tokenProvider: (() -> String?)?
    var onUnauthorized: ((String, String) -> Void)?
    var serviceID: String { configuration.baseURL?.absoluteString ?? "unconfigured" }
    init(configuration: APIConfiguration = .app, session: URLSession? = nil) {
        self.configuration = configuration
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.urlCache = nil
            config.httpCookieAcceptPolicy = .always
            self.session = URLSession(configuration: config, delegate: APIRedirectPolicy(), delegateQueue: nil)
        }
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil,
                 authenticated: Bool = false, token explicitToken: String? = nil, query: [URLQueryItem] = []) async throws -> Data {
        guard let base = configuration.baseURL else { throw APIError.configuration }
        let token = explicitToken ?? (authenticated ? tokenProvider?() : nil)
        if authenticated && token == nil { throw APIError.unauthorized("请先登录，再继续操作。") }
        try await prepareGateway()
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // The deployed gateway documents this fallback when it rewrites Authorization.
            if !configuration.gatewayCode.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Auth-Token") }
        }
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard !(200...299).contains(http.statusCode) else { return data }
        let message = Self.errorMessage(data, status: http.statusCode)
        if http.statusCode == 401 {
            if let token { onUnauthorized?(token, message) }
            throw APIError.unauthorized(message)
        }
        if http.statusCode == 403 { gatewayTask = nil }
        throw APIError.business(http.statusCode, message)
    }
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? APIError.timeout : APIError.network
        } catch { throw APIError.network }
    }
    private func prepareGateway() async throws {
        guard !configuration.gatewayCode.isEmpty, let base = configuration.baseURL else { return }
        if let gatewayTask { try await gatewayTask.value; return }
        let task = Task<Void, Error> {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.path = "/"
            components.queryItems = [URLQueryItem(name: "sharecode", value: configuration.gatewayCode)]
            guard let url = components.url else { throw APIError.configuration }
            let (_, response) = try await send(URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIError.business(403, "服务暂时无法访问，请稍后重试。")
            }
        }
        gatewayTask = task
        do { try await task.value } catch { gatewayTask = nil; throw error }
    }
    /// FastAPI detail is either text or a validation list. Never echo its input fields.
    nonisolated static func errorMessage(_ data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty { return String(detail.prefix(1500)) }
            if let detail = object["detail"] as? [[String: Any]] {
                let messages = detail.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return String(messages.joined(separator: "\n").prefix(1500)) }
            }
            if let message = object["message"] as? String, !message.isEmpty { return String(message.prefix(1500)) }
        }
        switch status {
        case 401: return "登录已失效，请重新登录。"
        case 400, 422: return "请检查填写内容后再试。"
        case 403: return "服务暂时无法访问，或当前账号无权执行此操作。"
        case 409: return "手机号、邮箱或用户名已被使用，请检查后再试。"
        case 429: return "操作有些频繁，请稍后再试。"
        default: return "服务暂时无法处理请求，请稍后再试。"
        }
    }
}

enum APIJSON {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
                if let date = formatter.date(from: value + "Z") { return date }
            }
            throw APIError.invalidResponse
        }
        do { return try decoder.decode(type, from: data) } catch { throw APIError.invalidResponse }
    }
}

import Foundation
import Combine

/// Proposed contract in docs/WORKBUDDY_EMAIL_RECOVERY.md. Keep disabled until
/// the deployed backend implements and verifies it; never probe guessed routes.
@MainActor
final class PasswordRecoveryAPI {
    static var enabledInApp: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SleepEmailRecoveryEnabled") as? String)?.uppercased() == "YES"
    }
    static let unavailableMessage = "邮箱找回暂未开放。若已忘记密码，请联系平台管理员核实账号后处理。"
    let enabled: Bool
    private let client: APIClient
    init(client: APIClient, enabled: Bool? = nil) {
        self.client = client; self.enabled = enabled ?? Self.enabledInApp
    }
    struct Challenge: Decodable {
        let request_id: String
        let expires_at: Double
        let retry_after: Int
        let message: String
    }
    func request(method: AccountInput.Method, phone: String, email: String) async throws -> Challenge {
        guard enabled else { throw APIError.validation(Self.unavailableMessage) }
        struct Body: Encodable { let phone: String?; let email: String }
        let body = Body(phone: method == .phone ? AccountInput.phone(phone) : nil, email: AccountInput.email(email))
        let data = try await client.request("auth/password-reset/request", method: "POST", body: JSONEncoder().encode(body))
        let result = try APIJSON.decode(Challenge.self, from: data)
        guard !result.request_id.isEmpty, result.expires_at.isFinite,
              result.expires_at > Date.now.timeIntervalSince1970,
              (1...3600).contains(result.retry_after) else { throw APIError.invalidResponse }
        return result
    }
    func confirm(requestID: String, code: String, password: String) async throws -> RegistrationResult {
        guard enabled else { throw APIError.validation(Self.unavailableMessage) }
        struct Body: Encodable { let request_id: String; let code: String; let new_password: String }
        let data = try await client.request("auth/password-reset/confirm", method: "POST",
            body: JSONEncoder().encode(Body(request_id: requestID, code: code, new_password: password)))
        return try APIJSON.decode(RegistrationResult.self, from: data)
    }
}

/// Recovery credentials live in memory only. This flow does not create a session,
/// alter account IDs, or touch any local sleep/health data.
@MainActor
final class PasswordRecoveryStore: ObservableObject {
    @Published private(set) var challenge: PasswordRecoveryAPI.Challenge?
    @Published private(set) var retryAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isComplete = false
    @Published private(set) var message: String?
    let api: PasswordRecoveryAPI
    init(api: PasswordRecoveryAPI) { self.api = api }

    func request(method: AccountInput.Method, phone: String, email: String) async {
        guard !isLoading, !isComplete else { return }
        message = nil
        do {
            guard api.enabled else { throw APIError.validation(PasswordRecoveryAPI.unavailableMessage) }
            if method == .phone { try AccountInput.validatePhone(phone) }
            try AccountInput.validateEmail(AccountInput.email(email))
            if let retryAt, retryAt > .now { throw APIError.validation("请稍等片刻，再获取验证码。") }
            isLoading = true
            defer { isLoading = false }
            let next = try await api.request(method: method, phone: phone, email: email)
            challenge = next
            retryAt = .now.addingTimeInterval(Double(next.retry_after))
            message = next.message
        } catch { message = Self.errorMessage(error) }
    }
    func confirm(code: String, password: String, confirmation: String) async {
        guard !isLoading, !isComplete else { return }
        message = nil
        do {
            guard let challenge else { throw APIError.validation("请先获取邮箱验证码。") }
            guard challenge.expires_at > Date.now.timeIntervalSince1970 else {
                self.challenge = nil
                throw APIError.validation("验证码已过期，请重新获取。")
            }
            let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
                throw APIError.validation("请输入邮件中的 6 位数字验证码。")
            }
            guard (6...72).contains(password.count), password.utf8.count <= 72 else {
                throw APIError.validation("新密码至少 6 个字符，且不能超过 72 字节。")
            }
            guard password == confirmation else { throw APIError.validation("两次密码不一致，请检查。") }
            isLoading = true
            defer { isLoading = false }
            let result = try await api.confirm(requestID: challenge.request_id, code: code, password: password)
            self.challenge = nil; retryAt = nil
            isComplete = true; message = result.message
        } catch { message = Self.errorMessage(error) }
    }
    private static func errorMessage(_ error: Error) -> String {
        if error as? APIError == .timeout { return "连接超时，请稍后再试。" }
        return error.localizedDescription
    }
}

import Foundation

struct AccountUser: Codable, Equatable, Identifiable {
    var id: Int
    var username: String
    var email: String?
    var phone: String? = nil
    var createdAt: Date
    var contactLabel: String { phone ?? email ?? username }
    enum CodingKeys: String, CodingKey { case id, username, email, phone; case createdAt = "created_at" }
}

struct AccountSession: Codable, Equatable {
    var user: AccountUser
    var accessToken: String
    var expiresAt: Date
}

struct RegistrationResult: Decodable { let message: String }

enum AccountInput {
    enum Method: String, CaseIterable {
        case phone, email
        var title: String { self == .phone ? "手机号" : "邮箱" }
    }
    static func phone(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if value.hasPrefix("+86") { value.removeFirst(3) }
        return value
    }
    static func email(_ input: String) -> String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func validate(email: String, password: String, username: String? = nil, confirmation: String? = nil) throws {
        guard email.count <= 254, email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            throw APIError.validation("请填写完整的邮箱地址。")
        }
        if let username {
            guard username.range(of: "^[a-zA-Z0-9_\\u4e00-\\u9fa5]{3,32}$", options: .regularExpression) != nil else {
                throw APIError.validation("用户名用 3～32 位中文、字母、数字或下划线。")
            }
            guard (6...72).contains(password.count), password.utf8.count <= 72 else {
                throw APIError.validation("密码至少 6 个字符，最多 72 个英文字符；中文等字符占用更多长度。")
            }
        } else if password.isEmpty { throw APIError.validation("请输入密码。") }
        if let confirmation, confirmation != password { throw APIError.validation("两次密码不一致，请检查后再注册。") }
    }
    static func validatePhone(_ input: String) throws {
        guard phone(input).range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else {
            throw APIError.validation("请填写 11 位大陆手机号，可带 +86 前缀。")
        }
    }
    static func validateRegistration(username: String, phone: String?, email: String?, password: String, confirmation: String) throws {
        if let phone { try validatePhone(phone) }
        guard phone != nil || email != nil else { throw APIError.validation("请填写手机号。") }
        // Phone-only accounts never need a fabricated email to pass validation.
        guard username.range(of: "^[a-zA-Z0-9_\\u4e00-\\u9fa5]{3,32}$", options: .regularExpression) != nil else {
            throw APIError.validation("用户名用 3～32 位中文、字母、数字或下划线。")
        }
        guard (6...72).contains(password.count), password.utf8.count <= 72 else { throw APIError.validation("密码至少 6 个字符，且不能超过 72 字节。") }
        guard confirmation == password else { throw APIError.validation("两次密码不一致，请检查后再注册。") }
        if let email { try validate(email: email, password: password) }
    }
}

@MainActor
protocol AccountServing {
    var client: APIClient { get }
    func login(identifier: String, method: AccountInput.Method, password: String) async throws -> AccountSession
    func register(username: String, phone: String?, email: String?, password: String) async throws -> RegistrationResult
    func me(token: String) async throws -> AccountUser
    func logout(token: String) async throws
}

/// Only the exact v1 request fields are encoded; registration never impersonates login.
@MainActor
final class AccountAPI: AccountServing {
    let client: APIClient
    init(client: APIClient) { self.client = client }
    func login(identifier: String, method: AccountInput.Method, password: String) async throws -> AccountSession {
        struct Body: Encodable { let phone: String?; let email: String?; let password: String }
        struct Token: Decodable {
            let access_token: String
            let token_type: String
            let expire_at: Double
        }
        let body = Body(phone: method == .phone ? AccountInput.phone(identifier) : nil,
                        email: method == .email ? AccountInput.email(identifier) : nil, password: password)
        let data = try await client.request("auth/login", method: "POST", body: JSONEncoder().encode(body))
        let token = try APIJSON.decode(Token.self, from: data)
        let expiry = Date(timeIntervalSince1970: token.expire_at)
        guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty,
              !token.access_token.contains(where: { $0.isWhitespace || $0.isNewline }), expiry > .now else { throw APIError.invalidResponse }
        // /me is the authority for the current user's identity.
        let user = try await me(token: token.access_token)
        return AccountSession(user: user, accessToken: token.access_token, expiresAt: expiry)
    }
    func register(username: String, phone: String?, email: String?, password: String) async throws -> RegistrationResult {
        struct Body: Encodable { let username: String; let phone: String?; let email: String?; let password: String }
        let data = try await client.request("auth/register", method: "POST", body: JSONEncoder().encode(Body(username: username, phone: phone, email: email, password: password)))
        return try APIJSON.decode(RegistrationResult.self, from: data)
    }
    func me(token: String) async throws -> AccountUser {
        let data = try await client.request("auth/me", authenticated: true, token: token)
        let user = try APIJSON.decode(AccountUser.self, from: data)
        guard user.id > 0, !user.username.isEmpty else { throw APIError.invalidResponse }
        return user
    }
    func logout(token: String) async throws { _ = try await client.request("auth/logout", method: "POST", authenticated: true, token: token) }
}

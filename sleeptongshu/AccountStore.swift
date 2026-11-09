import Foundation
import Combine
import Security

struct SavedAccountSession: Codable {
    var serviceID: String
    var session: AccountSession
}

protocol AccountSessionStorage {
    func load() throws -> SavedAccountSession?
    func save(_ value: SavedAccountSession) throws
    func clear() throws
}

struct KeychainAccountStorage: AccountSessionStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.rocgrey.sleeptongshu.account",
         kSecAttrAccount as String: "session-v1"]
    }
    func load() throws -> SavedAccountSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = try? JSONDecoder().decode(SavedAccountSession.self, from: data) else { throw APIError.secureStorage }
        return value
    }
    func save(_ value: SavedAccountSession) throws {
        let data = try JSONEncoder().encode(value)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(update) { _, value in value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw APIError.secureStorage }
        } else if status != errSecSuccess { throw APIError.secureStorage }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.secureStorage }
    }
}

/// Protected destinations survive an expired session; no upload is retried automatically.
enum AccountDestination: Identifiable, Equatable {
    case profile, upload(UUID)
    var id: String {
        switch self { case .profile: "profile"; case .upload(let id): "upload-\(id)" }
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var session: AccountSession?
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoring = true
    @Published var message: String?
    @Published var presentedDestination: AccountDestination?
    private(set) var pendingDestination: AccountDestination?
    let api: any AccountServing
    var client: APIClient { api.client }
    private let storage: any AccountSessionStorage
    private var restored = false
    private var generation = UUID()
    private var expiryTask: Task<Void, Never>?
    var canEnter: Bool { session != nil }

    init(api: (any AccountServing)? = nil, storage: any AccountSessionStorage = KeychainAccountStorage()) {
        self.api = api ?? AccountAPI(client: APIClient())
        self.storage = storage
        client.tokenProvider = { [weak self] in
            self?.checkExpiry()
            return self?.session?.accessToken
        }
        client.onUnauthorized = { [weak self] token, text in
            // An old response must never sign out a newer session.
            guard self?.session?.accessToken == token else { return }
            self?.invalidate(message: text)
        }
    }
    static func appStore() -> AccountStore {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), args.contains("-ui-testing-account-service") {
            return AccountStore(api: PreviewAccountAPI(), storage: PreviewAccountStorage())
        }
        #endif
        return AccountStore()
    }
    func open(_ destination: AccountDestination) {
        checkExpiry()
        if session != nil { presentedDestination = destination }
        else { pendingDestination = destination }
    }
    func checkExpiry() {
        if let session, session.expiresAt <= .now { invalidate(message: "登录已到期，请重新登录。") }
    }
    private func invalidate(message: String) {
        generation = UUID()
        expiryTask?.cancel()
        if let destination = presentedDestination { pendingDestination = destination }
        presentedDestination = nil
        session = nil
        self.message = message
        do { try storage.clear() }
        catch { self.message = message + "\n本机凭证未能清除，重新打开时会再次检查有效性。" }
    }
    private func activate(_ value: AccountSession) {
        session = value
        presentedDestination = pendingDestination
        pendingDestination = nil
        expiryTask?.cancel()
        let seconds = max(0, value.expiresAt.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(min(seconds, 31_536_000))); self?.checkExpiry() }
            catch { }
        }
    }
    /// Remembered sessions are accepted only after /me verifies them.
    func restore() async {
        guard !restored else { return }
        restored = true
        let operation = generation
        defer { isRestoring = false }
        do {
            guard let saved = try storage.load() else { return }
            guard saved.serviceID == client.serviceID else { try storage.clear(); return }
            guard saved.session.expiresAt > .now else { invalidate(message: "登录已到期，请重新登录。"); return }
            let user = try await api.me(token: saved.session.accessToken)
            guard operation == generation else { return }
            guard user.id == saved.session.user.id else { throw APIError.invalidResponse }
            var next = saved.session
            next.user = user
            try storage.save(SavedAccountSession(serviceID: client.serviceID, session: next))
            activate(next)
        } catch {
            guard operation == generation else { return }
            if (error as? APIError)?.isUnauthorized == true { invalidate(message: error.localizedDescription) }
            else { message = error.localizedDescription }
        }
    }
    /// Registration returns no token. Phone and email remain separate optional credentials.
    func register(username: String, phone: String? = nil, email: String? = nil, password: String, confirmation: String) async -> Bool {
        guard !isLoading else { return false }
        message = nil
        do {
            let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = email.map(AccountInput.email).flatMap { $0.isEmpty ? nil : $0 }
            let phone = phone.map(AccountInput.phone).flatMap { $0.isEmpty ? nil : $0 }
            try AccountInput.validateRegistration(username: name, phone: phone, email: email, password: password, confirmation: confirmation)
            isLoading = true
            defer { isLoading = false }
            let result = try await api.register(username: name, phone: phone, email: email, password: password)
            message = result.message
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func login(email: String, password: String, remember: Bool) async {
        await login(identifier: email, method: .email, password: password, remember: remember)
    }
    func login(identifier: String, method: AccountInput.Method = .phone, password: String, remember: Bool) async {
        guard !isLoading else { return }
        message = nil
        let operation = generation
        do {
            if method == .phone { try AccountInput.validatePhone(identifier) }
            else { try AccountInput.validate(email: AccountInput.email(identifier), password: password) }
            guard !password.isEmpty else { throw APIError.validation("请输入密码。") }
            isLoading = true
            defer { isLoading = false }
            let next = try await api.login(identifier: identifier, method: method, password: password)
            guard operation == generation else { return }
            do {
                if remember { try storage.save(SavedAccountSession(serviceID: client.serviceID, session: next)) }
                else { try storage.clear() }
            } catch {
                try? await api.logout(token: next.accessToken)
                throw APIError.secureStorage
            }
            activate(next)
        } catch { if operation == generation { message = error.localizedDescription } }
    }
    /// Logout clears this device immediately, even when revocation cannot reach the server.
    func signOut() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let token = session?.accessToken
        pendingDestination = nil
        presentedDestination = nil
        invalidate(message: "已退出登录。")
        pendingDestination = nil
        if let token {
            do { try await api.logout(token: token) }
            catch { message = "本机已退出。服务暂时无法确认退出，请稍后重试登录。" }
        }
    }
}

#if DEBUG
// In-memory service is enabled only by explicit UI-automation arguments.
private final class PreviewAccountStorage: AccountSessionStorage {
    var saved: SavedAccountSession?
    func load() throws -> SavedAccountSession? { saved }
    func save(_ value: SavedAccountSession) throws { saved = value }
    func clear() throws { saved = nil }
}
private final class PreviewAccountAPI: AccountServing {
    let client = APIClient(configuration: APIConfiguration(baseURL: "https://ui.example.test/api/v1"))
    func login(identifier: String, method: AccountInput.Method, password: String) async throws -> AccountSession {
        if password == "wrongpass" { throw APIError.unauthorized("账号或密码错误") }
        return AccountSession(user: AccountUser(id: 1, username: "sleeper_test", email: method == .email ? identifier : nil, phone: method == .phone ? identifier : nil, createdAt: .now),
                              accessToken: "ui-test-only", expiresAt: .now.addingTimeInterval(3600))
    }
    func register(username: String, phone: String?, email: String?, password: String) async throws -> RegistrationResult {
        RegistrationResult(message: "注册成功，请登录")
    }
    func me(token: String) async throws -> AccountUser { throw APIError.unauthorized("登录已失效") }
    func logout(token: String) async throws { }
}
#endif

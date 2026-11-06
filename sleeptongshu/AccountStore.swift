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
              let value = try? JSONDecoder().decode(SavedAccountSession.self, from: data) else { throw AccountError.secureStorage }
        return value
    }
    func save(_ value: SavedAccountSession) throws {
        let data = try JSONEncoder().encode(value)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(update) { _, value in value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AccountError.secureStorage }
        } else if status != errSecSuccess { throw AccountError.secureStorage }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.secureStorage }
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var session: AccountSession?
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoring = true
    @Published private(set) var isPreview = false
    @Published var message: String?
    private let api: any AccountServing
    private let storage: any AccountSessionStorage
    private var restored = false
    var isConfigured: Bool { api.isConfigured }
    var canEnter: Bool { session != nil || isPreview }

    init(api: any AccountServing = AccountAPI(), storage: any AccountSessionStorage = KeychainAccountStorage()) {
        self.api = api
        self.storage = storage
    }
    static func appStore() -> AccountStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), arguments.contains("-ui-testing-account-service") {
            return AccountStore(api: PreviewAccountAPI(), storage: PreviewAccountStorage())
        }
        #endif
        return AccountStore()
    }
    func checkExpiry() {
        guard let session, session.expiresAt <= .now else { return }
        self.session = nil
        try? storage.clear()
        message = AccountError.expired.localizedDescription
    }
    func restore() async {
        guard !restored else { return }
        restored = true
        defer { isRestoring = false }
        guard isConfigured else { return }
        do {
            guard let saved = try storage.load(), saved.serviceID == api.serviceID else { return }
            guard saved.session.expiresAt > .now else { try storage.clear(); message = AccountError.expired.localizedDescription; return }
            let user = try await api.me(token: saved.session.accessToken)
            guard user.id == saved.session.user.id else { throw AccountError.invalidResponse }
            var renewed = saved.session
            renewed.user = user
            try storage.save(SavedAccountSession(serviceID: api.serviceID, session: renewed))
            session = renewed
        } catch {
            if error as? AccountError == .expired { try? storage.clear() }
            message = error.localizedDescription
        }
    }
    func submit(register: Bool, username: String, password: String, confirmation: String, displayName: String) async {
        guard !isLoading else { return }
        message = nil
        guard isConfigured else { message = AccountError.notConfigured.localizedDescription; return }
        let username = AccountInput.username(username)
        do {
            try AccountInput.validate(username: username, password: password, confirmation: register ? confirmation : nil,
                                      displayName: register ? displayName : "")
            isLoading = true
            defer { isLoading = false }
            let next: AccountSession
            if register { next = try await api.register(username: username, password: password, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)) }
            else { next = try await api.login(username: username, password: password) }
            do { try storage.save(SavedAccountSession(serviceID: api.serviceID, session: next)) }
            catch {
                try? await api.logout(token: next.accessToken)
                throw AccountError.secureStorage
            }
            isPreview = false
            session = next
        } catch is CancellationError { }
        catch { message = error.localizedDescription }
    }
    func preview() {
        guard !isConfigured else { return }
        isPreview = true
        message = nil
    }
    func leavePreview() { isPreview = false; message = nil }
    func signOut() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do { try storage.clear() }
        catch { message = AccountError.secureStorage.localizedDescription; return }
        let token = session?.accessToken
        session = nil
        isPreview = false
        message = nil
        if let token {
            do { try await api.logout(token: token) }
            catch { message = "本机已退出。账号服务暂未确认退出，请稍后重新登录。" }
        }
    }
}

#if DEBUG
// UI automation only: no network, keychain writes or real registrations.
private final class PreviewAccountStorage: AccountSessionStorage {
    var saved: SavedAccountSession?
    func load() throws -> SavedAccountSession? { saved }
    func save(_ value: SavedAccountSession) throws { saved = value }
    func clear() throws { saved = nil }
}

private struct PreviewAccountAPI: AccountServing {
    let isConfigured = true
    let serviceID = "ui-test-memory"
    func login(username: String, password: String) async throws -> AccountSession {
        if password == "wrongpass" { throw AccountError.invalidCredentials }
        return make(username: username, displayName: "测试用户")
    }
    func register(username: String, password: String, displayName: String) async throws -> AccountSession {
        make(username: username, displayName: displayName)
    }
    func me(token: String) async throws -> AccountUser { throw AccountError.expired }
    func logout(token: String) async throws { }
    private func make(username: String, displayName: String) -> AccountSession {
        AccountSession(user: AccountUser(id: "ui-only", username: username, displayName: displayName, createdAt: .now),
                       accessToken: "ui-test-only", expiresAt: .now.addingTimeInterval(3600))
    }
}
#endif

import Foundation
import Combine
import CryptoKit

struct ClassroomItem: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var summary: String
    var body: String
    var kind: String
    var category: String
    var cover: String
    var media_url: String?
    var duration: Double?
    var preview_seconds: Double?
    var parent_id: String?
    var sort_order: Int
    var route: String
    var featured: Bool
    var updated_at: Double
    var external_url: String?
    var mediaURL: URL? { Self.https(media_url) }
    static func https(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
struct ContentPage: Decodable { let items: [ClassroomItem]; let total: Int }

@MainActor final class ContentStore: ObservableObject {
    @Published private(set) var items: [ClassroomItem] = []
    @Published private(set) var message: String?
    @Published private(set) var isLoading = false
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var hasRemoteCatalog = false
    private var service = ""
    private var bundled: [ClassroomItem] = []
    private let directory: URL
    init(directory: URL = .applicationSupportDirectory.appendingPathComponent("ContentCache")) {
        self.directory = directory
        if let url = Bundle.main.url(forResource: "ClassroomCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url), let bundled = try? JSONDecoder().decode([ClassroomItem].self, from: data) { items = bundled; self.bundled = bundled }
    }
    var courses: [ClassroomItem] { items.filter { $0.kind == "course" } }
    var articles: [ClassroomItem] { items.filter { $0.kind == "article" } }
    func children(_ id: String) -> [ClassroomItem] { items.filter { $0.parent_id == id }.sorted { $0.sort_order < $1.sort_order } }
    func daily(on date: Date = .now) -> ClassroomItem? {
        let list = articles.sorted { $0.id < $1.id }
        guard !list.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return list[abs(day) % list.count]
    }
    func refresh(client: APIClient, force: Bool = false) async {
        guard !isLoading else { return }
        if service != client.serviceID {
            service = client.serviceID; refreshedAt = nil
            items = bundled; hasRemoteCatalog = false
            if let data = try? Data(contentsOf: cacheURL(service)), let cached = try? JSONDecoder().decode([ClassroomItem].self, from: data) { items = cached; hasRemoteCatalog = true }
        }
        guard force || refreshedAt.map({ Date.now.timeIntervalSince($0) > 900 }) ?? true else { return }
        isLoading = true; defer { isLoading = false }
        do {
            var collected: [ClassroomItem] = [], page = 1
            while true {
                let bytes = try await client.request("content/items", query: [.init(name: "page", value: "\(page)"), .init(name: "page_size", value: "100")])
                let result = try JSONDecoder().decode(ContentPage.self, from: bytes)
                collected += result.items
                if collected.count >= result.total || result.items.isEmpty { break }
                page += 1
                guard page <= 100 else { throw APIError.invalidResponse }
            }
            guard !Task.isCancelled else { return }
            items = collected; refreshedAt = .now; message = nil; hasRemoteCatalog = true
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: cacheURL(service), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = "内容服务暂不可用，当前显示本机保存内容。下次刷新再检查。" }
    }
    func freshItem(_ id: String, client: APIClient) async throws -> ClassroomItem {
        // Before the additive API is deployed, actual bundled content remains usable.
        // After receiving a server catalog, never restore server-unpublished items.
        if !hasRemoteCatalog, let local = bundled.first(where: { $0.id == id }) { return local }
        do { return try JSONDecoder().decode(ClassroomItem.self, from: await client.request("content/items/" + id)) }
        catch let error as APIError {
            if case .business(404, _) = error { items.removeAll { $0.id == id || $0.parent_id == id } }
            throw error
        }
    }
    private func cacheURL(_ service: String) -> URL {
        directory.appendingPathComponent(SHA256.hash(data: Data(service.utf8)).map { String(format: "%02x", $0) }.joined() + ".json")
    }
}
struct LessonProgress: Codable { var seconds: Double; var duration: Double; var updatedAt: Date }
enum LearningProgress {
    static func key(service: String, user: Int, item: String) -> String {
        "lesson." + SHA256.hash(data: Data("\(service)|\(user)|\(item)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ key: String) -> LessonProgress? { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LessonProgress.self, from: $0) } }
    static func save(_ value: LessonProgress, key: String) {
        guard value.seconds.isFinite, value.duration.isFinite, value.seconds >= 0 else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

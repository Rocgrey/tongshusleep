import Foundation
import Combine
import CryptoKit

struct StepCache: Codable {
    let range: StepRange
    let response: CloudStepResponse
    let fetchedAt: Date
}

@MainActor protocol StepCacheStorage {
    func load(scope: String) throws -> StepCache?
    func save(_ value: StepCache, scope: String) throws
}

struct FileStepCache: StepCacheStorage {
    private func url(_ scope: String) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AccountSteps", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
    func load(scope: String) throws -> StepCache? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return nil }
        #endif
        let path = try url(scope)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(StepCache.self, from: Data(contentsOf: path))
    }
    func save(_ value: StepCache, scope: String) throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        #endif
        try JSONEncoder().encode(value).write(to: url(scope), options: [.atomic, .completeFileProtection])
    }
}

/// A captured session owns the entire operation. Late results cannot cross an account boundary.
@MainActor final class AccountStepsStore: ObservableObject {
    @Published private(set) var cloud: CloudStepResponse?
    @Published private(set) var range: StepRange?
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isCached = false
    @Published private(set) var message: String?
    private var session: AccountSession?
    private var serviceID = ""
    private var api: (any StepsServing)?
    private let cache: any StepCacheStorage
    private var generation = UUID()
    private var subscription: AnyCancellable?
    init(cache: (any StepCacheStorage)? = nil) { self.cache = cache ?? FileStepCache() }
    private var scope: String? { session.map { serviceID + "|user:\($0.user.id)" } }

    func observe(_ account: AccountStore) {
        guard subscription == nil else { return }
        subscription = account.$session.sink { [weak self, weak account] value in
            guard let self, let account else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.arguments.contains("-ui-testing-steps-chart") {
                self.bind(session: value, serviceID: account.client.serviceID, api: PreviewStepsAPI())
                return
            }
            #endif
            self.bind(session: value, serviceID: account.client.serviceID, api: AccountStepsAPI(client: account.client))
        }
    }
    func bind(session: AccountSession?, serviceID: String, api: any StepsServing) {
        guard self.session != session || self.serviceID != serviceID else { return }
        generation = UUID()
        self.session = session; self.serviceID = serviceID; self.api = api
        cloud = nil; range = nil; fetchedAt = nil; isLoading = false; isCached = false; message = nil
    }
    func refresh(_ nextRange: StepRange) async { await perform(nextRange, local: nil) }
    func sync(_ nextRange: StepRange, snapshot: HealthOverviewSnapshot?) async {
        let days = LocalStepDay.read(snapshot).filter { nextRange.contains($0.date) }
        guard !days.isEmpty else { message = "先到健康页读取系统健康中的步数；没有记录的日期不会上传为 0 步。"; return }
        await perform(nextRange, local: days)
    }
    private func perform(_ nextRange: StepRange, local: [LocalStepDay]?) async {
        guard let session, let api, let scope else { message = "请先登录，再读取账号步数。"; return }
        // A range change supersedes an old read. Repeated taps on the same range are ignored.
        if isLoading && range == nextRange { return }
        generation = UUID()
        let operation = generation
        if range != nextRange {
            cloud = nil; fetchedAt = nil; isCached = false
            if let saved = try? cache.load(scope: scope), saved.range == nextRange {
                cloud = saved.response; fetchedAt = saved.fetchedAt; isCached = true
            }
        }
        range = nextRange; isLoading = true; message = nil
        defer { if generation == operation { isLoading = false } }
        do {
            if let local {
                for day in local {
                    guard operation == generation else { return }
                    let result = try await api.upload(day.request, token: session.accessToken)
                    guard operation == generation else { return }
                    guard result.record.user_id == session.user.id, result.record.record_date == day.date,
                          result.record.source == "healthkit" else { throw APIError.invalidResponse }
                }
            }
            let response = try await api.fetch(nextRange, token: session.accessToken)
            guard operation == generation else { return }
            let now = Date.now
            cloud = response; fetchedAt = now; isCached = false
            message = local == nil ? "已读取账号最新步数" : "同步完成，已按账号返回的记录更新；重复同步不会累加。"
            do { try cache.save(StepCache(range: nextRange, response: response, fetchedAt: now), scope: scope) }
            catch { message = "已读取账号步数，但本机缓存未能保存。" }
        } catch is CancellationError {
            guard operation == generation else { return }
            isCached = cloud != nil; message = nil
        } catch {
            guard operation == generation else { return }
            isCached = cloud != nil
            message = error.localizedDescription + (local != nil ? " 部分记录可能已保存，重试会更新同一天的累计值，不会重复相加。" : "")
        }
    }
}

#if DEBUG
/// Chart fixtures are opt-in automation only; never written to disk or uploaded.
@MainActor private struct PreviewStepsAPI: StepsServing {
    func upload(_ request: StepUploadRequest, token: String) async throws -> StepUpsertResult {
        throw APIError.validation("界面示例不会上传。")
    }
    func fetch(_ range: StepRange, token: String) async throws -> CloudStepResponse {
        let days = range.dates.enumerated().compactMap { index, date -> CloudStepDay? in
            guard index % 4 != 1 else { return nil }
            return CloudStepDay(record_date: date, steps: index == 0 ? 0 : 3800 + index % 7 * 930,
                source: "healthkit", source_id: "ui-test-only", data_time: date + " 18:00:00", updated_at: StepDates.date(date)!, is_real_zero: index == 0)
        }
        let stats = StepStatistics(values: Dictionary(uniqueKeysWithValues: days.map { ($0.record_date, $0.steps) }), range: range)
        return CloudStepResponse(days: days, summary: CloudStepSummary(start_date: range.start, end_date: range.end,
            days_in_range: range.dates.count, days_with_record: stats.recordedDays, days_real_zero: stats.zeroDays,
            days_missing: stats.missingDays, range_incomplete: stats.missingDays > 0, total_steps: stats.total, avg_steps: stats.average))
    }
}
#endif

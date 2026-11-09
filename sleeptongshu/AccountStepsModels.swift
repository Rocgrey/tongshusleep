import Foundation

/// The current server groups dates and marks today in UTC+8, without a query timezone.
/// Use that same day boundary for both HealthKit queries and account statistics.
enum StepDates {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value }
    static func format(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = timeZone
        formatter.dateFormat = time ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let result = formatter.date(from: value), format(result) == value else { return nil }
        return result
    }
}

struct StepRange: Equatable, Codable {
    let start: String
    let end: String
    init(days: Int, now: Date = .now) {
        end = StepDates.format(now)
        start = StepDates.format(StepDates.calendar.date(byAdding: .day, value: 1 - days, to: now)!)
    }
    init(start: String, end: String) { self.start = start; self.end = end }
    var dates: [String] {
        guard var day = StepDates.date(start), let last = StepDates.date(end), day <= last else { return [] }
        var values: [String] = []
        while day <= last && values.count < 366 {
            values.append(StepDates.format(day))
            day = StepDates.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return values
    }
    func contains(_ day: String) -> Bool { day >= start && day <= end }
}

struct LocalStepDay: Equatable, Identifiable {
    let date: String
    let steps: Int
    let measuredAt: Date
    var id: String { date }
    var request: StepUploadRequest {
        StepUploadRequest(record_date: date, steps: steps, source: "healthkit", source_id: "system-health-statistics",
                          data_time: StepDates.format(measuredAt, time: true), timezone: StepDates.timeZone.identifier)
    }
    /// Only known daily totals from a newly-read, timezone-tagged snapshot are uploadable.
    /// Nil quantities were never saved by HealthKit; an explicit numeric zero remains valid.
    static func read(_ snapshot: HealthOverviewSnapshot?) -> [LocalStepDay] {
        guard let snapshot, snapshot.stepsTimeZone == StepDates.timeZone.identifier,
              !snapshot.truncatedMetrics.contains(.steps) else { return [] }
        let groups = Dictionary(grouping: snapshot.observations.filter { $0.metric == .steps }) { StepDates.format($0.start) }
        return groups.compactMap { date, entries in
            guard entries.count == 1, let value = entries.first, let start = StepDates.date(date),
                  value.sourceID == "system-health-statistics", value.start == start, value.end >= value.start,
                  value.end <= StepDates.calendar.date(byAdding: .day, value: 1, to: start)!,
                  value.value.isFinite, (0...200000).contains(value.value), value.value.rounded() == value.value else { return nil }
            return LocalStepDay(date: date, steps: Int(value.value), measuredAt: snapshot.stepsReadAt ?? snapshot.readAt)
        }.sorted { $0.date < $1.date }
    }
}

struct StepUploadRequest: Codable, Equatable {
    let record_date: String
    let steps: Int
    let source: String
    let source_id: String?
    let data_time: String
    let timezone: String
}

struct CloudStepDay: Codable, Equatable, Identifiable {
    let record_date: String
    let steps: Int
    let source: String
    let source_id: String?
    let data_time: String?
    let updated_at: Date
    var sources_available: [String] = []
    var is_today = false
    var is_real_zero = false
    var id: String { record_date }
}
struct CloudStepSummary: Codable {
    let start_date: String
    let end_date: String
    let days_in_range: Int
    let days_with_record: Int
    let days_real_zero: Int
    let days_missing: Int
    let range_incomplete: Bool
    let total_steps: Int
    let avg_steps: Double?
}
struct CloudStepResponse: Codable { let days: [CloudStepDay]; let summary: CloudStepSummary }
struct StepStoredRecord: Decodable {
    let id: Int
    let user_id: Int
    let record_date: String
    let steps: Int
    let source: String
    let data_time: String?
}
struct StepUpsertResult: Decodable {
    let record_id: Int
    let applied: Bool
    let reason: String?
    let record: StepStoredRecord
}

struct StepStatistics: Equatable {
    let total: Int
    let recordedDays: Int
    let zeroDays: Int
    let missingDays: Int
    var average: Double? { recordedDays > 0 ? Double(total) / Double(recordedDays) : nil }
    init(values: [String: Int], range: StepRange) {
        let valid = values.filter { range.contains($0.key) && (0...200000).contains($0.value) }
        total = valid.values.reduce(0, +); recordedDays = valid.count
        zeroDays = valid.values.filter { $0 == 0 }.count
        missingDays = max(0, range.dates.count - recordedDays)
    }
}

@MainActor protocol StepsServing {
    func upload(_ request: StepUploadRequest, token: String) async throws -> StepUpsertResult
    func fetch(_ range: StepRange, token: String) async throws -> CloudStepResponse
}
@MainActor struct AccountStepsAPI: StepsServing {
    let client: APIClient
    func upload(_ request: StepUploadRequest, token: String) async throws -> StepUpsertResult {
        guard (0...200000).contains(request.steps), StepDates.date(request.record_date) != nil else { throw APIError.validation("步数记录不完整，请重新读取系统健康。") }
        let data = try await client.request("health/step-record", method: "POST", body: JSONEncoder().encode(request), authenticated: true, token: token)
        return try APIJSON.decode(StepUpsertResult.self, from: data)
    }
    func fetch(_ range: StepRange, token: String) async throws -> CloudStepResponse {
        let data = try await client.request("health/step-records", authenticated: true, token: token,
            query: [URLQueryItem(name: "start_date", value: range.start), URLQueryItem(name: "end_date", value: range.end)])
        let result = try APIJSON.decode(CloudStepResponse.self, from: data)
        guard result.summary.start_date == range.start, result.summary.end_date == range.end,
              Set(result.days.map(\.record_date)).count == result.days.count,
              result.days.allSatisfy({ range.contains($0.record_date) && StepDates.date($0.record_date) != nil && (0...200000).contains($0.steps) }) else { throw APIError.invalidResponse }
        return result
    }
}

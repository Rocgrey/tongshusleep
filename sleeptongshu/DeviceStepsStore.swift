import Foundation
import Combine

/// Daily device totals only. Minute packets may be incomplete and are never summed here.
struct DeviceStepDay: Codable, Equatable, Identifiable {
    var device: String
    var deviceName: String
    var day: String
    var steps: Int
    var readAt: Date
    var dayBasis: String
    var id: String { "\(device)|\(day)" }

    static func read(_ report: WearableProbeReport) -> Self? {
        guard WearableHistoryDecoder.isBIO(model: report.observedModel, firmware: report.observedFirmware),
              let count = report.currentSteps, count <= 200_000 else { return nil }
        // Older reports have no exact realtime timestamp. Recover only reads that did
        // not cross midnight; never assign an old value to today's date on app launch.
        let date: Date
        if let measured = report.currentStepsReadAt { date = measured }
        else {
            guard let end = report.finishedAt, StepDates.format(end) == StepDates.format(report.startedAt) else { return nil }
            date = report.startedAt
        }
        return Self(device: report.deviceKey, deviceName: report.deviceName, day: StepDates.format(date),
                    steps: Int(count), readAt: date, dayBasis: "北京时间（UTC+8）")
    }

    static func merge(_ incoming: [Self], into existing: [Self]) -> [Self] {
        var rows: [String: Self] = [:]
        for row in existing + incoming where !row.device.isEmpty && StepDates.date(row.day) != nil && (0...200_000).contains(row.steps) {
            if let old = rows[row.id], old.readAt > row.readAt { continue }
            rows[row.id] = row // Replace cumulative totals, including real zero and corrections.
        }
        return rows.values.sorted { $0.day == $1.day ? $0.device < $1.device : $0.day > $1.day }
    }
}

/// Local device data is independent of HealthKit permission and cloud account data.
@MainActor final class DeviceStepsStore: ObservableObject {
    @Published private(set) var rows: [DeviceStepDay] = []
    @Published private(set) var saveError: String?
    private let url: URL?

    init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([DeviceStepDay].self, from: data) {
            rows = DeviceStepDay.merge(saved, into: [])
        }
    }
    static func appStore() -> DeviceStepsStore {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return DeviceStepsStore(url: nil) }
        let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return DeviceStepsStore(url: folder?.appendingPathComponent("device-steps-v1.json"))
    }
    var latest: DeviceStepDay? { rows.max { $0.readAt < $1.readAt } }
    var devices: [DeviceStepDay] {
        Dictionary(grouping: rows, by: \.device).values.compactMap { $0.max { $0.readAt < $1.readAt } }
            .sorted { $0.readAt > $1.readAt }
    }
    func days(for device: String?) -> [DeviceStepDay] { rows.filter { $0.device == (device ?? latest?.device) } }

    func merge(_ incoming: [DeviceStepDay]) {
        let next = DeviceStepDay.merge(incoming, into: rows)
        guard next != rows else { return }
        do {
            if let url { try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            rows = next; saveError = nil
        } catch { saveError = "设备步数未能保存，请重新连接设备后重试。" }
    }
}

enum SleepDashboardSource: String, CaseIterable {
    case device, health, all
    var label: String { switch self { case .device: "设备记录"; case .health: "系统健康"; case .all: "全部记录" } }

    /// An empty HealthKit read must not hide actual device records. A manual picker
    /// choice takes precedence, while automatic selection follows incoming local data.
    static func preferred(records: [SleepRecord], hasDeviceData: Bool, hasReadHealth: Bool) -> Self {
        if hasDeviceData || records.contains(where: { $0.isVisible && $0.source == .band }) { return .device }
        if hasReadHealth || records.contains(where: { $0.isVisible && $0.source == .healthKit }) { return .health }
        return .all
    }
    func includes(_ record: SleepRecord) -> Bool {
        record.isVisible && (self == .all || record.source == (self == .device ? .band : .healthKit))
    }
}

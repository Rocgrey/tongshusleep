import Foundation
import Combine
import CryptoKit
import CoreFoundation

enum VitalKind: String, Codable, CaseIterable, Identifiable {
    case heart, oxygen, respiration, systolic, diastolic, hrv, stress, glucose
    case cholesterol, triglycerides, hdl, ldl, uricAcid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .heart: "心率"
        case .oxygen: "血氧"
        case .respiration: "呼吸率"
        case .systolic: "收缩压"
        case .diastolic: "舒张压"
        case .hrv: "HRV（设备值）"
        case .stress: "压力（设备值）"
        case .glucose: "血糖（设备估计）"
        case .cholesterol: "总胆固醇（设备估计）"
        case .triglycerides: "甘油三酯（设备估计）"
        case .hdl: "高密度脂蛋白（设备估计）"
        case .ldl: "低密度脂蛋白（设备估计）"
        case .uricAcid: "尿酸（设备估计）"
        }
    }
    var unit: String {
        switch self {
        case .heart, .respiration: "次/分"
        case .oxygen: "%"
        case .systolic, .diastolic: "mmHg"
        case .hrv, .stress: "设备值"
        case .glucose: "设备原值"
        case .cholesterol, .triglycerides, .hdl, .ldl: "mmol/L"
        case .uricAcid: "umol/L"
        }
    }
    func accepts(_ value: Double) -> Bool {
        guard value.isFinite, value != 255 else { return false }
        switch self {
        case .heart: return (20...250).contains(value)
        case .oxygen: return (1...100).contains(value)
        case .respiration: return (1...80).contains(value)
        case .systolic: return (40...300).contains(value)
        case .diastolic: return (20...200).contains(value)
        case .hrv, .stress: return value > 0 && value < 255
        case .glucose: return value > 0 && value < 1000
        case .cholesterol, .triglycerides, .hdl, .ldl: return value > 0 && value < 100
        case .uricAcid: return value > 0 && value < 2000
        }
    }
}

struct WearableVital: Identifiable, Codable, Equatable {
    var device: String
    var deviceLabel: String
    var date: Date
    var kind: VitalKind
    var value: Double
    var origin: String
    var id: String { "\(device)|\(kind.rawValue)|\(date.timeIntervalSince1970)|\(origin)" }

    static func deviceKey(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum WearableVitalDecoder {
    static func decode(_ result: [String: Any], calendar: Calendar = .current) throws -> [WearableVital] {
        guard let device = result["deviceID"] as? String, !device.isEmpty,
              let rows = result["vitals"] as? [[String: Any]], rows.count <= 100_000 else { throw VeepooImportError.malformed }
        let key = WearableVital.deviceKey(device)
        let label = "戒指 · \(key.prefix(6))"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        var candidates: [String: WearableVital] = [:]
        var conflicts: Set<String> = []
        for row in rows {
            guard let time = row["time"] as? String else { continue }
            var date: Date?
            for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: time), formatter.string(from: parsed) == time { date = parsed; break }
            }
            guard let date, date <= Date.now.addingTimeInterval(300) else { continue }
            for kind in VitalKind.allCases {
                guard let value = number(row[kind.rawValue]), kind.accepts(value) else { continue }
                if kind == .systolic || kind == .diastolic {
                    guard let systolic = number(row["systolic"]), let diastolic = number(row["diastolic"]),
                          VitalKind.systolic.accepts(systolic), VitalKind.diastolic.accepts(diastolic), systolic > diastolic else { continue }
                }
                let origin = row["origin"] as? String ?? "设备历史"
                let sample = WearableVital(device: key, deviceLabel: label, date: date, kind: kind, value: value, origin: origin)
                if let old = candidates[sample.id], old.value != value { conflicts.insert(sample.id) }
                candidates[sample.id] = sample
            }
        }
        return candidates.values.filter { !conflicts.contains($0.id) }.sorted { $0.date < $1.date }
    }

    private static func number(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        return (raw as? String).flatMap(Double.init)
    }
}

@MainActor
final class WearableVitalsStore: ObservableObject {
    @Published private(set) var samples: [WearableVital] = []
    @Published private(set) var error: String?
    private let url: URL?

    static func appStore() -> WearableVitalsStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            let store = WearableVitalsStore(url: nil)
            if arguments.contains("-ui-testing-vitals") {
                let kinds: [(VitalKind, Double)] = [(.heart, 64), (.oxygen, 98), (.hrv, 42)]
                let points = (0..<7).flatMap { day in
                    kinds.map { kind, value in
                        WearableVital(device: "ui-fixture", deviceLabel: "示例戒指", date: Date.now.addingTimeInterval(-Double(day) * 86400),
                                      kind: kind, value: value + Double(day % 2), origin: "界面测试示例")
                    }
                }
                try? store.merge(points)
            }
            return store
        }
        #endif
        return WearableVitalsStore()
    }

    init(url: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("wearable-vitals-v1.json")) {
        self.url = url
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { samples = try JSONDecoder().decode([WearableVital].self, from: Data(contentsOf: url)) }
        catch { self.error = "本机体征文件未能打开，原文件已保留。" }
    }

    @discardableResult
    func merge(_ incoming: [WearableVital]) throws -> Int {
        guard error == nil else { throw VeepooImportError.failure(error!) }
        var indexed = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        var changed = 0
        for sample in incoming where sample.kind.accepts(sample.value) && sample.date <= Date.now.addingTimeInterval(300) {
            if indexed[sample.id] != sample { changed += 1 }
            indexed[sample.id] = sample
        }
        let next = indexed.values.sorted { $0.date < $1.date }
        try persist(next)
        samples = next
        return changed
    }

    func clear() throws { try persist([]); samples = []; error = nil }
    func export() throws -> Data { try JSONEncoder().encode(samples) }

    private func persist(_ next: [WearableVital]) throws {
        if let url { try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection]) }
    }
}

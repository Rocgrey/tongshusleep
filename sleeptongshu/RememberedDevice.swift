import Foundation

enum DevicePresentation {
    static func name(_ raw: String) -> String {
        let lower = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if ["xiaomi", "小米", "miband", "smartband"].contains(where: lower.contains) { return "手环" }
        if ["gband", "veepoo", "协立"].contains(where: lower.contains) { return "戒指" }
        if ["apple", "苹果"].contains(where: lower.contains) { return "穿戴设备" }
        return raw
    }
}

struct RememberedDevice: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var lastConnected: Date
}

struct RememberedDeviceStorage {
    let defaults: UserDefaults
    private let key = "rememberedWearablesV1"

    func load() -> [RememberedDevice] {
        guard let data = defaults.data(forKey: key), let records = try? JSONDecoder().decode([RememberedDevice].self, from: data) else { return [] }
        return records.sorted { $0.lastConnected > $1.lastConnected }
    }

    func save(_ records: [RememberedDevice]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}

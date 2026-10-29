import Foundation

enum DevicePresentation {
    static func bluetoothName(advertised: String?, peripheral: String?, previous: String? = nil, id: UUID) -> String {
        for candidate in [advertised, peripheral, previous] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        }
        return "未命名蓝牙设备 · \(id.uuidString.prefix(4))"
    }

    static func name(_ raw: String) -> String {
        let lower = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if ["xiaomi", "小米", "miband", "smartband"].contains(where: lower.contains) { return "设备" }
        if ["gband", "veepoo", "协立"].contains(where: lower.contains) { return "戒指" }
        if ["apple", "苹果"].contains(where: lower.contains) { return "系统健康来源" }
        return raw
    }
}

enum RingDevicePolicy {
    static func recognizes(name: String, services: [String] = []) -> Bool {
        let value = name.lowercased().replacingOccurrences(of: " ", with: "")
        if services.contains(where: { $0.uppercased() == VeepooGatt.service }) { return true }
        return ["ring", "戒指", "l03", "gband", "veepoo", "协立"].contains(where: value.contains)
    }
}

struct RememberedDevice: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var lastConnected: Date
    var verifiedRing: Bool? = nil
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

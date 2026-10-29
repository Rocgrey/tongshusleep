import Foundation

struct DeviceBatteryReading: Equatable {
    let level: Int
    let isPercentage: Bool
    let isLow: Bool
    let readAt: Date

    init?(level: Int, isPercentage: Bool, isLow: Bool = false, readAt: Date = .now) {
        guard (0...(isPercentage ? 100 : 4)).contains(level) else { return nil }
        self.level = level
        self.isPercentage = isPercentage
        self.isLow = isLow || (isPercentage ? level <= 20 : level <= 1)
        self.readAt = readAt
    }

    var fraction: Double { Double(level) / (isPercentage ? 100 : 4) }
    var text: String { isPercentage ? "\(level)%" : "\(level)/4 格" }
}

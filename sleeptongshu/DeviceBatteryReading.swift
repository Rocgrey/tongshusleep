import Foundation

struct DeviceBatteryReading: Equatable {
    let level: Int
    let isPercentage: Bool
    let isLow: Bool
    let readAt: Date
    var maximumLevel: Int { isPercentage ? 100 : gridMaximum }
    private var gridMaximum = 4

    init?(level: Int, isPercentage: Bool, isLow: Bool = false, readAt: Date = .now) {
        guard (0...(isPercentage ? 100 : 4)).contains(level) else { return nil }
        self.level = level
        self.isPercentage = isPercentage
        self.isLow = isLow || (isPercentage ? level <= 20 : level <= 1)
        self.readAt = readAt
    }

    init?(gridLevel: Int, maximum: Int, readAt: Date = .now) {
        guard maximum > 0, maximum <= 100, (0...maximum).contains(gridLevel) else { return nil }
        self.level = gridLevel
        self.isPercentage = false
        self.isLow = gridLevel <= 1
        self.readAt = readAt
        self.gridMaximum = maximum
    }

    var fraction: Double { Double(level) / Double(maximumLevel) }
    var text: String { isPercentage ? "\(level)%" : "\(level)/\(gridMaximum) 格" }
}

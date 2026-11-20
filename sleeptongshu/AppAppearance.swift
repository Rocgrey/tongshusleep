import SwiftUI

extension UIColor {
    var lighter: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r + 0.27), green: min(1, g + 0.27), blue: min(1, b + 0.27), alpha: a)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case business, fresh, cute
    var id: String { rawValue }
    var title: String { switch self { case .business: "商务"; case .fresh: "清新"; case .cute: "可爱" } }
    var accent: UIColor {
        switch self {
        case .business: UIColor(red: 0.12, green: 0.36, blue: 0.44, alpha: 1)
        case .fresh: UIColor(red: 10 / 255, green: 117 / 255, blue: 107 / 255, alpha: 1)
        case .cute: UIColor(red: 0.67, green: 0.21, blue: 0.39, alpha: 1)
        }
    }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "fresh") ?? .fresh }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        }
    }
}

struct AppSettingsView: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.fresh.rawValue
    var body: some View {
        List {
            Section("通用") {
                NavigationLink("外观") {
                    List(AppAppearance.allCases) { theme in
                        Button { appearance = theme.rawValue } label: {
                            HStack {
                                Circle().fill(Color(uiColor: theme.accent)).frame(width: 20, height: 20)
                                Text(theme.title).foregroundStyle(.primary)
                                Spacer()
                                if theme.rawValue == appearance { Image(systemName: "checkmark") }
                            }.padding(.vertical, 8)
                        }.accessibilityIdentifier("theme-" + theme.rawValue)
                            .accessibilityValue(theme.rawValue == appearance ? "已选择" : "未选择")
                    }.navigationTitle("外观")
                }
                NavigationLink("提醒") { ReminderSettingsView() }
            }
            Section("本机音频") { NavigationLink("候选语音与存储") { NightAudioLibraryView() } }
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
    }
}

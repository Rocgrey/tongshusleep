import SwiftUI
import UserNotifications
import Combine

@MainActor final class AppRoutes: ObservableObject {
    static let shared = AppRoutes()
    @Published var target: String?
    static func valid(_ value: String) -> Bool {
        ["breathing", "noise", "goodnight", "monitoring", "classroom"].contains(value) ||
        value.range(of: "^content/[a-zA-Z0-9_-]{1,80}$", options: .regularExpression) != nil
    }
    func open(_ url: URL) {
        guard url.scheme == "sleeptongshu", let host = url.host else { return }
        let route = host + url.path
        target = Self.valid(route) ? route : "goodnight"
    }
}

final class SleepAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ReminderService.shared.install()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in ReminderService.shared.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined() }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in ReminderService.shared.remoteStatus = "远程推送暂不可用，本地提醒仍可使用。" }
    }
}

@MainActor final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    @Published var deviceToken: String? {
        didSet { if let account = activeAccount, deviceToken != oldValue { Task { await sync(account: account) } } }
    }
    private weak var activeAccount: AccountStore?
    @Published var remoteStatus = "远程推送待配置"
    @Published var message: String?
    func install() { UNUserNotificationCenter.current().delegate = self }
    func apply(items: [ClassroomItem]) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        let daily = defaults.bool(forKey: "dailyReminder"), bedtime = defaults.bool(forKey: "bedtimeReminder")
        center.removePendingNotificationRequests(withIdentifiers: ["bedtime"] + (0..<14).map { "daily-\($0)" })
        guard daily || bedtime else { return }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
                message = "提醒未开启，请在系统设置中允许通知。"; return
            }
            if defaults.bool(forKey: "remoteReminders") {
                UIApplication.shared.registerForRemoteNotifications()
                message = "已选择远程提醒，本机不重复安排；投递需后台完成 APNs 配置。"
                return
            }
            let calendar = Calendar.current
            if bedtime {
                let minute = defaults.object(forKey: "bedtimeMinute") as? Int ?? 1320
                let notification = UNMutableNotificationContent()
                notification.title = "给今天一个温柔的收尾"; notification.body = "你的晚安卡已准备好，来放松一会儿。"
                notification.userInfo = ["route": "goodnight"]; notification.sound = .default
                try await center.add(UNNotificationRequest(identifier: "bedtime", content: notification, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minute / 60, minute: minute % 60), repeats: true)))
            }
            if daily {
                let minute = defaults.object(forKey: "dailyMinute") as? Int ?? 1200
                let articles = items.filter { $0.kind == "article" }.shuffled()
                for index in 0..<14 {
                    let day = calendar.date(byAdding: .day, value: index, to: .now)!
                    var parts = calendar.dateComponents([.year, .month, .day], from: day)
                    parts.hour = minute / 60; parts.minute = minute % 60
                    guard let date = calendar.date(from: parts), date > .now else { continue }
                    let notification = UNMutableNotificationContent()
                    notification.title = "今天，了解一点睡眠"; notification.body = "一小段阅读，陪你慢慢建立自己的休息节奏。"
                    notification.userInfo = ["route": articles.isEmpty ? "classroom" : "content/" + articles[index % articles.count].id]
                    notification.sound = .default
                    try await center.add(UNNotificationRequest(identifier: "daily-\(index)", content: notification, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                }
            }
            message = "本地提醒已更新；每日内容已安排未来两周，打开 App 时续排。"
        } catch { message = "提醒未能保存，请稍后再试。" }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String ?? "goodnight"
        Task { @MainActor in AppRoutes.shared.target = AppRoutes.valid(route) ? route : "goodnight" }
        completionHandler()
    }
    func sync(account: AccountStore) async {
        activeAccount = account
        guard let session = account.session else { return }
        struct Preferences: Encodable { var daily: Bool; var bedtime: Bool; var daily_minute: Int; var bedtime_minute: Int; var timezone: String }
        let d = UserDefaults.standard
        let remote = d.bool(forKey: "remoteReminders")
        let body = Preferences(daily: remote && d.bool(forKey: "dailyReminder"), bedtime: remote && d.bool(forKey: "bedtimeReminder"), daily_minute: d.object(forKey: "dailyMinute") as? Int ?? 1200, bedtime_minute: d.object(forKey: "bedtimeMinute") as? Int ?? 1320, timezone: TimeZone.current.identifier)
        do {
            _ = try await account.client.request("notifications/preferences", method: "PUT", body: JSONEncoder().encode(body), authenticated: true, token: session.accessToken)
            guard account.session?.accessToken == session.accessToken else { return }
            if remote, let deviceToken {
                struct Device: Encodable { var token: String; var environment: String }
                let environment = Bundle.main.object(forInfoDictionaryKey: "SleepAPNSEnvironment") as? String ?? "sandbox"
                _ = try await account.client.request("notifications/devices", method: "POST", body: JSONEncoder().encode(Device(token: deviceToken, environment: environment)), authenticated: true, token: session.accessToken)
            }
            remoteStatus = "提醒偏好已同步；远程投递取决于后台推送配置。"
        } catch { remoteStatus = "远程提醒尚未同步，本地提醒设置保留。" }
    }
    func unregister(account: AccountStore) async {
        guard let deviceToken, account.session != nil else { return }
        struct Body: Encodable { let token: String }
        _ = try? await account.client.request("notifications/devices/unregister", method: "POST", body: JSONEncoder().encode(Body(token: deviceToken)), authenticated: true)
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @StateObject private var service = ReminderService.shared
    @AppStorage("dailyReminder") private var daily = false
    @AppStorage("bedtimeReminder") private var bedtime = false
    @AppStorage("dailyMinute") private var dailyMinute = 1200
    @AppStorage("bedtimeMinute") private var bedtimeMinute = 1320
    @AppStorage("remoteReminders") private var remote = false
    private func time(_ binding: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(binding.wrappedValue) * 60) }, set: { date in let c = Calendar.current.dateComponents([.hour, .minute], from: date); binding.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
    var body: some View {
        Form {
            Section("提醒方式") {
                Toggle("使用远程内容推送", isOn: $remote)
                Text(remote ? "需要后台推送服务已开通；不会重复发送本地提醒。" : "使用本机提醒，无需远程推送服务。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("每日内容") { Toggle("每日内容提醒", isOn: $daily); DatePicker("提醒时间", selection: time($dailyMinute), displayedComponents: .hourAndMinute).disabled(!daily) }
            Section("睡前") { Toggle("睡前提醒", isOn: $bedtime); DatePicker("睡前时间", selection: time($bedtimeMinute), displayedComponents: .hourAndMinute).disabled(!bedtime) }
            Section {
                Button("保存提醒设置") { Task { await service.apply(items: content.items); await service.sync(account: account) } }
                if let message = service.message { Text(message).font(.footnote) }
                Text(service.remoteStatus).font(.footnote).foregroundStyle(.secondary)
                Text("锁屏提醒不包含心率、睡眠分期等私人信息。关闭开关并保存即可退订。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("提醒").toolbar(.visible, for: .navigationBar)
    }
}

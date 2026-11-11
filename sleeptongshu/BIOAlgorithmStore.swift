import Foundation
import Combine
import SwiftData

@MainActor final class BIOAlgorithmStore: ObservableObject {
    @Published private(set) var message = "等待设备同步；睡眠分期由厂家算法计算"
    private var lastAttempt: [String: Date] = [:]
    func analyze(_ report: WearableProbeReport?, account: AccountStore, context: ModelContext) async {
        guard let report, let session = account.session else { return }
        do {
            let requests = try BIOSleepAlgorithmRequest.make(report)
            guard !requests.isEmpty else {
                message = "夜间观测已保存；分期还需要真实设备标识及前后两日输入，重连设备后会再检查。"; return
            }
            for request in requests {
                let key = "\(account.client.serviceID)|\(session.user.id)|\(report.deviceKey)|\(request.recordDate)|\(report.finishedAt!.timeIntervalSince1970)"
                guard lastAttempt[key].map({ Date.now.timeIntervalSince($0) > 300 }) ?? true else { continue }
                lastAttempt[key] = .now
                message = "正在计算设备睡眠；原始输入经平台发送到厂家算法服务"
                let bytes = try await account.client.request("health/bio-sleep-analysis", method: "POST", body: JSONEncoder().encode(request), authenticated: true, token: session.accessToken, requestTimeout: 40)
                guard account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                let response = try APIJSON.decode(BIOSleepAlgorithmEnvelope.self, from: bytes)
                guard response.return_code == 0, let result = response.result else { message = response.message; continue }
                let all = try context.fetch(FetchDescriptor<SleepRecord>())
                let day = String(format: "%08d", request.recordDate)
                let label = "\(day.prefix(4))-\(day.dropFirst(4).prefix(2))-\(day.suffix(2))"
                if let record = all.first(where: { $0.metadata?.bioNight?.device == report.deviceKey && $0.metadata?.bioNight?.endDay == label }) {
                    let payload = try BIOSleepResultAdapter.payload(result, observation: record.payload)
                    record.replace(with: payload); try context.save()
                    message = result.completed == 1 ? "设备睡眠结果已更新" : "已取得阶段性睡眠结果，之后同步时继续更新"
                }
            }
        } catch {
            guard account.session?.accessToken == session.accessToken else { return }
            message = error.localizedDescription + " 夜间观测保留，不补造分期。"
        }
    }
}

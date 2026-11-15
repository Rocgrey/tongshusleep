import Foundation
import Combine
import SwiftData

@MainActor final class BIOAlgorithmStore: ObservableObject {
    @Published private(set) var message = "等待设备同步；睡眠分期由厂家算法计算"
    private var lastAttempt: [String: Date] = [:]
    private var completedInputs: Set<String> = []
    private var prepared: BIOPreparedSleep?
    private var preparedKey = ""
    private var scope = ""
    private var generation = UUID()
    private var operation: UUID?
    private let worker: WearableProbeWorker
    private let directory: URL
    private let localCalculation: ((BIOSleepAlgorithmRequest) async throws -> BIOSleepAlgorithmResult)?
    @Published private var serviceIssue: String?
    private var serviceRetryAfter: Date?
    @Published private(set) var statusByNight: [String: String] = [:]

    init(worker: WearableProbeWorker = .shared, directory: URL = WearableProbeStorage.directory,
         localCalculation: ((BIOSleepAlgorithmRequest) async throws -> BIOSleepAlgorithmResult)? = nil) {
        self.worker = worker; self.directory = directory
        self.localCalculation = localCalculation ?? (BIOLocalSleep.available ? { request in try await worker.localSleep(request) } : nil)
    }

    func reset() {
        scope = ""; generation = UUID(); operation = nil
        prepared = nil; preparedKey = ""; lastAttempt = [:]; completedInputs = []
        serviceIssue = nil; serviceRetryAfter = nil
        statusByNight = [:]; message = BIOLocalSleep.available ? "登录后检查设备睡眠计算" : "登录并开启自动同步后检查睡眠分析"
    }
    func status(for night: BIONight) -> String? {
        if prepared?.report.deviceKey == night.device, let serviceIssue { return serviceIssue }
        return statusByNight["\(night.device)|\(night.endDay)"]
    }

    func analyze(_ report: WearableProbeReport?, account: AccountStore, context: ModelContext) async {
        guard let session = account.session else { reset(); return }
        let owner = "\(account.client.serviceID)|\(session.user.id)|\(session.accessToken)"
        if scope != owner { reset(); scope = owner }
        guard serviceRetryAfter.map({ Date.now >= $0 }) ?? true else { return }
        guard operation == nil, let report, report.finishedAt != nil,
              WearableHistoryDecoder.isBIO(model: report.observedModel, firmware: report.observedFirmware) else { return }
        let run = UUID(); operation = run
        defer { if operation == run { operation = nil } }
        let version = generation
        let binding = "\(account.client.serviceID)|\(session.user.id)"
        var diagnostic = BIOAnalysisDiagnostic(inputRecordCount: 0, previousDayRRI: 0, nextDayRRI: 0, stageCount: 0, message: "")
        do {
            let identity = "\(binding)|\(RawSensorBatchRequest.captureID(report))|\(report.finishedAt!.timeIntervalSince1970)|\(report.records.count)"
            if preparedKey != identity {
                let next = try await worker.prepareSleep(report, owner: binding, base: directory)
                guard version == generation, account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                prepared = next; preparedKey = identity
                // Restore locally saved observations even when the last BLE read is empty.
                try BIONight.save(next.observations, in: context)
            }
            guard let prepared else { return }
            diagnostic.inputRecordCount = prepared.report.records.count
            guard !prepared.requests.isEmpty else {
                message = report.algorithmDeviceID == nil ? "缺少设备标识，请重新连接设备后再检查。" : "已检查本机历史记录；暂缺相邻两天的睡眠输入，请佩戴过夜后同步。"
                diagnostic.message = message
                await worker.saveSleepDiagnostic(diagnostic, base: directory)
                return
            }
            for (request, body) in zip(prepared.requests, prepared.bodies) {
                let fingerprint = WearableVital.deviceKey((localCalculation == nil ? "cloud|" : BIOLocalSleep.version + "|") + body.base64EncodedString())
                let key = "\(binding)|\(fingerprint)"
                if completedInputs.contains(key) { continue }
                guard lastAttempt[key].map({ Date.now.timeIntervalSince($0) > 300 }) ?? true else { continue }
                try Task.checkCancellation()
                guard version == generation, account.session?.accessToken == session.accessToken else { return }
                lastAttempt[key] = .now
                diagnostic.recordDate = request.recordDate
                diagnostic.previousDayRRI = request.prevDayRri.count; diagnostic.nextDayRRI = request.nextDayRri.count
                diagnostic.returnCode = nil; diagnostic.httpStatus = nil; diagnostic.stageCount = 0
                let isLocal = localCalculation != nil
                diagnostic.engine = isLocal ? BIOLocalSleep.version : "vendor-cloud-sleep-v1"
                message = isLocal ? "正在手机上计算设备睡眠" : "正在计算设备睡眠；原始输入经平台发送到厂家算法服务"
                let day = String(format: "%08d", request.recordDate)
                let label = "\(day.prefix(4))-\(day.dropFirst(4).prefix(2))-\(day.suffix(2))"
                let nightKey = "\(report.deviceKey)|\(label)"
                statusByNight[nightKey] = message
                let response: BIOSleepAlgorithmEnvelope
                if let localCalculation {
                    do {
                        let result = try await localCalculation(request)
                        response = BIOSleepAlgorithmEnvelope(return_code: 0, message: "本机计算完成", result: result)
                    } catch {
                        guard version == generation, account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                        message = "该日期的睡眠输入暂时无法计算，已保留夜间观测。"
                        statusByNight[nightKey] = message; diagnostic.message = message
                        completedInputs.insert(key)
                        await worker.saveSleepDiagnostic(diagnostic, base: directory)
                        continue
                    }
                } else {
                    let bytes = try await account.client.request("health/bio-sleep-analysis", method: "POST", body: body, authenticated: true, token: session.accessToken, requestTimeout: 40)
                    response = try APIJSON.decode(BIOSleepAlgorithmEnvelope.self, from: bytes)
                    diagnostic.httpStatus = 200
                }
                guard version == generation, account.session?.accessToken == session.accessToken, !Task.isCancelled else { return }
                serviceIssue = nil; serviceRetryAfter = nil
                diagnostic.returnCode = response.return_code
                guard response.return_code == 0, let result = response.result else {
                    message = response.message; statusByNight[nightKey] = message
                    diagnostic.message = message
                    await worker.saveSleepDiagnostic(diagnostic, base: directory)
                    continue
                }
                if isLocal && result.sections.isEmpty {
                    message = "本机已计算，当前输入暂未识别到有效睡眠阶段；已保留夜间观测，补充过夜记录后会再更新。"
                    statusByNight[nightKey] = message; diagnostic.message = message
                    completedInputs.insert(key)
                    await worker.saveSleepDiagnostic(diagnostic, base: directory)
                    continue
                }
                let all = try context.fetch(FetchDescriptor<SleepRecord>())
                if let record = all.first(where: { $0.metadata?.bioNight?.device == report.deviceKey && $0.metadata?.bioNight?.endDay == label }) {
                    let payload: SleepPayload
                    do {
                        payload = try BIOSleepResultAdapter.payload(result, observation: record.payload,
                            algorithm: isLocal ? BIOLocalSleep.version : "vendor-cloud-sleep-v1")
                    } catch {
                        if !isLocal { throw error }
                        message = "该日期的计算结果未通过时间和阶段检查，已保留原有记录。"
                        statusByNight[nightKey] = message; diagnostic.message = message
                        completedInputs.insert(key)
                        await worker.saveSleepDiagnostic(diagnostic, base: directory)
                        continue
                    }
                    record.replace(with: payload); try context.save()
                    message = isLocal ? "设备睡眠已在本机计算并更新；有新记录时继续更新" : (result.completed == 1 ? "设备睡眠结果已更新" : "已取得阶段性睡眠结果，之后同步时继续更新")
                    if isLocal || result.completed == 1 { completedInputs.insert(key) }
                    statusByNight[nightKey] = message
                    diagnostic.stageCount = result.sections.count
                } else {
                    message = "分析结果已返回，但未找到对应日期的夜间观测。请重新同步设备。"
                }
                diagnostic.message = message
                await worker.saveSleepDiagnostic(diagnostic, base: directory)
            }
        } catch is CancellationError { return }
        catch let error as APIError {
            guard version == generation, account.session?.accessToken == session.accessToken else { return }
            if case .business(let code, _) = error {
                diagnostic.httpStatus = code
                if [403, 404, 503].contains(code) {
                    serviceIssue = error.localizedDescription
                    serviceRetryAfter = Date.now.addingTimeInterval(300)
                }
            }
            message = error.localizedDescription + " 夜间观测保留，暂不生成睡眠阶段。"
            diagnostic.message = message
            if let date = diagnostic.recordDate {
                let text = String(date)
                statusByNight["\(report.deviceKey)|\(text.prefix(4))-\(text.dropFirst(4).prefix(2))-\(text.suffix(2))"] = message
            }
            await worker.saveSleepDiagnostic(diagnostic, base: directory)
        } catch {
            guard version == generation, account.session?.accessToken == session.accessToken else { return }
            message = "睡眠结果暂时无法解析，已保留原始记录。"
            diagnostic.message = message
            await worker.saveSleepDiagnostic(diagnostic, base: directory)
        }
    }
}

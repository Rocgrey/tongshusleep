import Foundation
import CoreBluetooth
import Combine

@MainActor
final class VeepooRingClient: ObservableObject {
    #if SLEEP_VEEPOO
    static let enabled = true
    private var bridge: STVeepooBridge?
    #else
    static let enabled = false
    #endif
    @Published private(set) var isBusy = false
    @Published private(set) var status = "等待开始戒指同步"
    @Published private(set) var progress: Double?
    @Published private(set) var rejectedCount = 0
    @Published private(set) var events: [String] = []
    private var watchdog: Task<Void, Never>?
    private var continuation: CheckedContinuation<VeepooDecodedSleep, Error>?
    private var attempt = UUID()
    private var reading = false
    private var lastDiagnosticWrite = Date.distantPast

    func preparing() { isBusy = true; record("正在切换到厂商数据通道…") }

    func sync(peripheral: CBPeripheral) async throws -> VeepooDecodedSleep {
        guard Self.enabled, continuation == nil else { isBusy = false; throw VeepooImportError.unavailable }
        attempt = UUID()
        let token = attempt
        events = []; progress = nil; rejectedCount = 0; reading = false; isBusy = true
        record("正在连接并验证设备…")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { callback in
                continuation = callback
                #if SLEEP_VEEPOO
                let current = STVeepooBridge()
                bridge = current
                current.event = { [weak self] message in
                    guard let self, self.attempt == token, self.continuation != nil else { return }
                    self.record(message)
                }
                current.progress = { [weak self] total, day, percent in
                    guard let self, self.attempt == token, self.continuation != nil else { return }
                    if !self.reading { self.reading = true; self.armTimeout(seconds: 180, token: token) }
                    let fraction = min(1, Double(percent) / 100)
                    self.progress = total > 0 ? min(1, (Double(day) + fraction) / Double(total)) : nil
                    self.status = "正在读取历史 · 第 \(day + 1) 天 / \(max(total, day + 1)) 天 · \(min(percent, 100))%"
                    self.persistDiagnostic(force: false)
                }
                current.failed = { [weak self] message in
                    guard let self, self.attempt == token else { return }
                    self.finish(.failure(VeepooImportError.failure(message)))
                }
                current.completed = { [weak self] value in
                    guard let self, self.attempt == token, self.continuation != nil else { return }
                    let raw = value as? [String: Any] ?? [:]
                    self.record("厂商返回 \((raw["sleeps"] as? [Any])?.count ?? 0) 段睡眠、\((raw["vitals"] as? [Any])?.count ?? 0) 条体征窗口")
                    self.record("历史传输已结束，正在验证睡眠分期…")
                    let encoded: Data
                    do { encoded = try JSONSerialization.data(withJSONObject: raw) }
                    catch { self.finish(.failure(VeepooImportError.malformed)); return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let decoded = Result { try VeepooSleepDecoder.decode(JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]) }
                        DispatchQueue.main.async {
                            guard self.attempt == token, self.continuation != nil else { return }
                            switch decoded {
                            case .success(let download):
                                self.rejectedCount = download.rejected
                                self.finish(.success(download))
                            case .failure(let error): self.finish(.failure(error))
                            }
                        }
                    }
                }
                armTimeout(seconds: 40, token: token)
                current.start(peripheral: peripheral)
                #else
                finish(.failure(VeepooImportError.unavailable))
                #endif
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() {
        if continuation != nil { finish(.failure(CancellationError())) }
        else { isBusy = false; record("已取消戒指同步") }
    }

    func reportFailure(_ error: Error) {
        isBusy = false
        progress = nil
        if status != error.localizedDescription { record(error.localizedDescription) }
    }

    var diagnosticReport: String {
        (["sleeptongshu · 设备同步诊断", "状态：\(status)", "未保存的异常或不完整记录：\(rejectedCount)"] + events).joined(separator: "\n")
    }

    private func record(_ value: String) {
        status = value
        events.append("\(Date.now.formatted(date: .omitted, time: .standard)) \(value)")
        if events.count > 30 { events.removeFirst() }
        persistDiagnostic()
    }

    private func persistDiagnostic(force: Bool = true) {
        guard force || Date.now.timeIntervalSince(lastDiagnosticWrite) >= 1 else { return }
        lastDiagnosticWrite = .now
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(diagnosticReport.utf8).write(to: directory.appendingPathComponent("veepoo-last-sync.txt"), options: [.atomic, .completeFileProtection])
        } catch { /* Diagnostics must not interrupt a device transfer. */ }
    }

    private func armTimeout(seconds: Double, token: UUID) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.attempt == token, self.continuation != nil else { return }
            self.finish(.failure(VeepooImportError.failure("设备同步超时，已断开连接。请结束其他 App 的同步后重新连接再试。")))
        }
    }

    private func finish(_ result: Result<VeepooDecodedSleep, Error>) {
        guard let callback = continuation else { return }
        continuation = nil
        watchdog?.cancel(); watchdog = nil
        #if SLEEP_VEEPOO
        bridge?.cancel(); bridge = nil
        #endif
        isBusy = false
        switch result {
        case .success(let download):
            progress = 1
            record("同步结束 · 有效睡眠 \(download.records.count) 段 · 有效体征 \(download.vitals.count) 条\(download.rejected > 0 ? " · 部分睡眠未通过验证" : "")")
        case .failure(let error): progress = nil; record(error is CancellationError ? "已取消戒指同步" : error.localizedDescription)
        }
        callback.resume(with: result)
    }

    func saved(count: Int, vitals: Int) {
        record(count == 0 && vitals == 0
               ? "设备已连接并验证，暂无有效记录；请完成测量或佩戴过夜后再同步"
               : "本机已保存 · 睡眠 \(count) 段 · 体征 \(vitals) 条\(rejectedCount > 0 ? "，部分睡眠未通过验证" : "")")
    }
}

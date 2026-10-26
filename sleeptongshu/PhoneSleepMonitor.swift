import AVFoundation
import CoreMotion
import SoundAnalysis
import Combine
import UIKit

enum PhoneMonitoringPolicy {
    static let maximumDuration: TimeInterval = 23 * 3600
    static let signalTimeout: TimeInterval = 30
    enum StopReason: Equatable { case timeLimit, signalLost }

    static func elapsed(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start)))
    }

    static func stopReason(start: Date, lastSignal: Date, now: Date) -> StopReason? {
        if now.timeIntervalSince(start) >= maximumDuration { return .timeLimit }
        if now.timeIntervalSince(lastSignal) > signalTimeout { return .signalLost }
        return nil
    }

    static func shouldStopForRouteChange(reason: UInt?, inputChanged: Bool, engineRunning: Bool) -> Bool {
        // Activating our own recording category also posts route changes with the same input.
        !engineRunning || inputChanged || reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue
    }
}

// SoundAnalysis uses Apple's on-device classifier. Audio buffers are discarded after analysis.
private final class NightSoundAnalyzer: NSObject, SNResultsObserving {
    let analyzer: SNAudioStreamAnalyzer
    let queue = DispatchQueue(label: "sleeptongshu.sound", qos: .utility)
    var onLevel: ((Double, Double) -> Void)?
    var onClassification: ((String, Double) -> Void)?
    var onFailure: (() -> Void)?
    let available: Bool
    private let inFlight = DispatchSemaphore(value: 8)
    private var samples = 0.0
    private var squareSum = 0.0
    private let sampleRate: Double

    init(format: AVAudioFormat) throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        analyzer = SNAudioStreamAnalyzer(format: format)
        sampleRate = format.sampleRate
        available = request.knownClassifications.contains("snoring") && request.knownClassifications.contains("speech")
        super.init()
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
    }

    func accept(_ buffer: AVAudioPCMBuffer, at position: AVAudioFramePosition) {
        guard let data = buffer.floatChannelData?[0], let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            copy.floatChannelData?[channel].update(from: buffer.floatChannelData![channel], count: Int(buffer.frameLength))
        }
        var sum = 0.0
        for index in 0..<Int(buffer.frameLength) { sum += Double(data[index] * data[index]) }
        let count = Double(buffer.frameLength)
        queue.async { [self] in
            defer { inFlight.signal() }
            analyzer.analyze(copy, atAudioFramePosition: position)
            squareSum += sum
            samples += count
            if samples >= sampleRate {
                let db = max(-160, min(0, 10 * log10(max(1e-16, squareSum / samples))))
                onLevel?(db, samples / sampleRate)
                squareSum = 0; samples = 0
            }
        }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        for label in ["snoring", "speech"] {
            if let classification = result.classification(forIdentifier: label), classification.confidence >= 0.75 {
                onClassification?(label, 0.75)
            }
        }
    }
    func finish() { queue.async { [self] in analyzer.completeAnalysis(); analyzer.removeAllRequests() } }
    func request(_ request: SNRequest, didFailWithError error: Error) { onFailure?() }
    func requestDidComplete(_ request: SNRequest) {}
}

@MainActor
final class PhoneSleepMonitor: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var checkpoint: PhoneCheckpoint?
    @Published private(set) var status = "今晚，从手机开始"
    @Published private(set) var currentDB: Double = -80
    @Published private(set) var motionAvailable = false
    @Published private(set) var elapsedSeconds = 0
    @Published var error: String?
    private var engine: AVAudioEngine?
    private var sound: NightSoundAnalyzer?
    private let motion = CMMotionManager()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let url: URL
    private var lastCheckpoint = Date.distantPast
    private var previousIdleSetting = false
    private var activeID: UUID?
    private var inputPortIDs: [String] = []
    private var audioSessionActive = false
    private let sessionQueue = DispatchQueue(label: "sleeptongshu.audio-session")

    init(draftURL: URL? = nil) {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PhoneMonitoring", isDirectory: true)
        url = draftURL ?? directory.appendingPathComponent("active.json")
        if !ProcessInfo.processInfo.arguments.contains("-ui-testing"), let data = try? Data(contentsOf: url) {
            do {
                var saved = try JSONDecoder().decode(PhoneCheckpoint.self, from: data)
                if !saved.epochs.isEmpty { try saved.payload.validate() }
                saved.interrupted = true
                checkpoint = saved
                elapsedSeconds = PhoneMonitoringPolicy.elapsed(from: saved.start, to: saved.stoppedAt ?? saved.end)
                status = "发现上次未结束的采集，请保存或舍弃"
            } catch { self.error = "上次采集草稿无法读取，文件已保留：\(error.localizedDescription)" }
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, .AVAudioEngineConfigurationChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleAudioNotification(note) }
            })
        }
    }

    private func handleAudioNotification(_ notification: Notification) {
        guard isRecording else { return }
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
        case AVAudioSession.routeChangeNotification:
            let currentInputs = AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid).sorted()
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard PhoneMonitoringPolicy.shouldStopForRouteChange(reason: reason,
                inputChanged: currentInputs != inputPortIDs, engineRunning: engine?.isRunning == true) else { return }
        case .AVAudioEngineConfigurationChange:
            guard let changedEngine = notification.object as? AVAudioEngine, changedEngine === engine,
                  !changedEngine.isRunning else { return }
        default: break
        }
        stop(interrupted: true)
        status = "监测已中断 · 请保存已有数据后重新开始"
    }

    func start() async {
        guard !isRecording, !isStarting, checkpoint == nil else { return }
        isStarting = true
        status = "正在准备麦克风，请允许录音权限"
        defer { isStarting = false }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else {
            status = "尚未开始 · 麦克风未授权"
            error = "请在 iPhone 设置 → 隐私与安全性 → 麦克风中允许 sleeptongshu 使用麦克风。"
            return
        }
        do {
            try await activateAudioSession()
            let session = AVAudioSession.sharedInstance()
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
            let sound = try NightSoundAnalyzer(format: format)
            let captureID = UUID()
            activeID = captureID
            sound.onLevel = { [weak self] db, seconds in
                Task { @MainActor in
                    guard self?.activeID == captureID else { return }
                    self?.receive(db: db, seconds: seconds)
                }
            }
            sound.onClassification = { [weak self] label, seconds in
                Task { @MainActor in
                    guard self?.activeID == captureID else { return }
                    self?.receive(label: label, seconds: seconds)
                }
            }
            sound.onFailure = { [weak self] in
                Task { @MainActor in
                    guard self?.activeID == captureID else { return }
                    self?.checkpoint?.classifierAvailable = false
                }
            }
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in sound.accept(buffer, at: time.sampleTime) }
            self.engine = engine
            self.sound = sound
            let now = Date()
            checkpoint = PhoneCheckpoint(start: now, end: now, epochs: [], classifierAvailable: sound.available)
            try engine.start()
            inputPortIDs = session.currentRoute.inputs.map(\.uid).sorted()
            isRecording = true
            elapsedSeconds = 0
            previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            motionAvailable = motion.isAccelerometerAvailable
            motion.accelerometerUpdateInterval = 0.5
            if motionAvailable {
                motion.startAccelerometerUpdates(to: .main) { [weak self] data, failure in
                    Task { @MainActor in
                        guard let self, self.isRecording, self.activeID == captureID else { return }
                        if failure != nil { self.motionAvailable = false; return }
                        guard let data else { return }
                        let a = data.acceleration
                        let activity = min(20, abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1))
                        self.updateEpoch { $0.movement = max($0.movement ?? 0, activity) }
                    }
                }
            }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.heartbeat() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            status = "正在监测 · 声音仅在本机分析"
            persist(force: true)
        } catch {
            stop(interrupted: true)
            if checkpoint?.epochs.isEmpty == true { discard() }
            self.error = "无法开始采集：\(error.localizedDescription)"
            status = "未能开始监测，请检查提示后重试"
        }
    }

    private func heartbeat() {
        guard isRecording, let checkpoint else { return }
        let now = Date()
        elapsedSeconds = PhoneMonitoringPolicy.elapsed(from: checkpoint.start, to: now)
        switch PhoneMonitoringPolicy.stopReason(start: checkpoint.start, lastSignal: checkpoint.end, now: now) {
        case .timeLimit:
            stop(interrupted: true)
            status = "已到 23 小时上限 · 请保存报告"
        case .signalLost:
            stop(interrupted: true)
            status = "超过 30 秒未收到麦克风信号 · 监测已停止"
        case nil: persist()
        }
    }

    private func updateEpoch(_ update: (inout PhoneEpoch) -> Void) {
        guard isRecording, var saved = checkpoint else { return }
        let now = Date()
        let offset = floor(now.timeIntervalSince(saved.start) / 60) * 60
        let date = saved.start.addingTimeInterval(offset)
        if saved.epochs.last?.date != date { saved.epochs.append(PhoneEpoch(date: date)) }
        update(&saved.epochs[saved.epochs.count - 1])
        checkpoint = saved
    }

    private func receive(db: Double, seconds: Double) {
        guard isRecording else { return }
        currentDB = db
        updateEpoch { epoch in
            let weight = min(seconds, 60 - epoch.audioSeconds)
            epoch.soundDB = (epoch.soundDB * epoch.audioSeconds + db * weight) / max(0.001, epoch.audioSeconds + weight)
            epoch.audioSeconds += weight
        }
        checkpoint?.end = Date()
        if let start = checkpoint?.start, Date().timeIntervalSince(start) >= PhoneMonitoringPolicy.maximumDuration {
            stop(interrupted: true)
            status = "已到 23 小时上限 · 请保存报告"
        }
    }

    private func receive(label: String, seconds: Double) {
        updateEpoch { epoch in
            if label == "snoring" { epoch.snoreSeconds = min(60, epoch.snoreSeconds + seconds) }
            if label == "speech" { epoch.speechSeconds = min(60, epoch.speechSeconds + seconds) }
        }
    }

    func stop(interrupted: Bool = false) {
        let wasRecording = isRecording
        if wasRecording, let start = checkpoint?.start {
            let now = Date()
            elapsedSeconds = PhoneMonitoringPolicy.elapsed(from: start, to: now)
            checkpoint?.stoppedAt = now
        }
        isRecording = false
        activeID = nil
        timer?.invalidate(); timer = nil
        motion.stopAccelerometerUpdates()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        sound?.finish()
        engine = nil; sound = nil
        deactivateAudioSession()
        if wasRecording { UIApplication.shared.isIdleTimerDisabled = previousIdleSetting }
        if interrupted { checkpoint?.interrupted = true }
        status = "本次采集已结束，等待保存"
        persist(force: true)
    }

    func discard() {
        stop()
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            checkpoint = nil; elapsedSeconds = 0; status = "今晚，从手机开始"
        } catch { self.error = "草稿清理失败：\(error.localizedDescription)" }
    }

    func saved() { discard() }

    private func persist(force: Bool = false) {
        guard let checkpoint, force || Date().timeIntervalSince(lastCheckpoint) >= 30 else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(checkpoint).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastCheckpoint = Date()
        } catch {
            // Stop collecting if local storage fails, so a displayed active night is never silently lost.
            if isRecording { stopAfterStorageFailure() }
            self.error = "本地草稿保存失败：\(error.localizedDescription)"
        }
    }
    private func stopAfterStorageFailure() {
        if let start = checkpoint?.start {
            let now = Date()
            elapsedSeconds = PhoneMonitoringPolicy.elapsed(from: start, to: now)
            checkpoint?.stoppedAt = now
        }
        isRecording = false
        activeID = nil
        timer?.invalidate(); motion.stopAccelerometerUpdates(); engine?.stop()
        engine?.inputNode.removeTap(onBus: 0); sound?.finish(); engine = nil; sound = nil
        UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
        deactivateAudioSession()
        checkpoint?.interrupted = true
        status = "存储异常，采集已停止；请重试保存"
    }
    private enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "未找到可用麦克风，请断开耳机后重试。" }
    }

    private func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: [])
                    try session.setActive(true)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        audioSessionActive = true
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

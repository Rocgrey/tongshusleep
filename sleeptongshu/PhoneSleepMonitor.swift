import AVFoundation
import CoreMotion
import SoundAnalysis
import Combine
import UIKit

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

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PhoneMonitoring", isDirectory: true)
        url = directory.appendingPathComponent("active.json")
        if !ProcessInfo.processInfo.arguments.contains("-ui-testing"), let data = try? Data(contentsOf: url) {
            do {
                var saved = try JSONDecoder().decode(PhoneCheckpoint.self, from: data)
                if !saved.epochs.isEmpty { try saved.payload.validate() }
                saved.interrupted = true
                checkpoint = saved
                status = "发现上次未结束的采集，请保存或舍弃"
            } catch { self.error = "上次采集草稿无法读取，文件已保留：\(error.localizedDescription)" }
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == AVAudioSession.interruptionNotification,
                   (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue { return }
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.stop(interrupted: true)
                    self.status = "声音采集中断，请保存本次记录后重新开始"
                }
            })
        }
    }

    func start() async {
        guard !isRecording, !isStarting, checkpoint == nil else { return }
        isStarting = true
        defer { isStarting = false }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { error = "请在 iPhone 设置 → 隐私与安全性 → 麦克风中允许 sleeptongshu 使用麦克风。"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
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
            isRecording = true
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
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if let start = self.checkpoint?.start, Date().timeIntervalSince(start) >= 23 * 3600 {
                        self.stop(interrupted: true); self.status = "采集已达 23 小时上限，请保存记录"; return
                    }
                    // An audio engine that silently stops must not produce an imaginary night.
                    if let end = self.checkpoint?.end, Date().timeIntervalSince(end) > 30 {
                        self.stop(interrupted: true); self.status = "未收到音频信号，采集已暂停"; return
                    }
                    self.persist()
                }
            }
            status = "正在监测 · 声音仅在本机分析"
            persist(force: true)
        } catch {
            stop(interrupted: true)
            if checkpoint?.epochs.isEmpty == true { discard() }
            self.error = "无法开始采集：\(error.localizedDescription)"
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
        if let start = checkpoint?.start, Date().timeIntervalSince(start) >= 23 * 3600 { stop(interrupted: true) }
    }

    private func receive(label: String, seconds: Double) {
        updateEpoch { epoch in
            if label == "snoring" { epoch.snoreSeconds = min(60, epoch.snoreSeconds + seconds) }
            if label == "speech" { epoch.speechSeconds = min(60, epoch.speechSeconds + seconds) }
        }
    }

    func stop(interrupted: Bool = false) {
        let wasRecording = isRecording
        isRecording = false
        activeID = nil
        timer?.invalidate(); timer = nil
        motion.stopAccelerometerUpdates()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        sound?.finish()
        engine = nil; sound = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if wasRecording { UIApplication.shared.isIdleTimerDisabled = previousIdleSetting }
        if interrupted { checkpoint?.interrupted = true }
        status = "本次采集已结束，等待保存"
        persist(force: true)
    }

    func discard() {
        stop()
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            checkpoint = nil; status = "今晚，从手机开始"
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
        isRecording = false
        activeID = nil
        timer?.invalidate(); motion.stopAccelerometerUpdates(); engine?.stop()
        engine?.inputNode.removeTap(onBus: 0); sound?.finish(); engine = nil; sound = nil
        UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
        try? AVAudioSession.sharedInstance().setActive(false)
        checkpoint?.interrupted = true
        status = "存储异常，采集已停止；请重试保存"
    }
    private enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "未找到可用麦克风，请断开耳机后重试。" }
    }
}

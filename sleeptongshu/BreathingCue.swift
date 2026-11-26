import AVFoundation
import Combine

/// Rank installed Mandarin female voices without depending on undocumented voice names.
enum BreathingVoiceSelection {
    struct Candidate {
        let identifier: String
        let language: String
        let female: Bool
        let quality: Int
    }
    static func preferred(_ voices: [Candidate]) -> Candidate? {
        voices.filter { $0.female && ["zh-CN", "zh-Hans", "zh-TW"].contains($0.language) }
            .sorted {
                let left = $0.language == "zh-TW" ? 0 : 1
                let right = $1.language == "zh-TW" ? 0 : 1
                if left != right { return left > right }
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                return $0.identifier < $1.identifier
            }.first
    }
}

/// A short original bell with a soft attack/tail; no bundled/licensed recording.
enum BreathingCueTone {
    static let rate = 22050
    static func samples(phase: Int) -> [Float] {
        let frequency = [523.25, 659.25, 392.0][max(0, min(2, phase))]
        let count = rate * 9 / 10
        return (0..<count).map { index in
            let t = Double(index) / Double(rate)
            let attack = min(1, t / 0.035)
            let release = min(1, Double(count - 1 - index) / Double(rate) / 0.12)
            let envelope = attack * release * exp(-t * 3.8)
            let tone = sin(2 * .pi * frequency * t) + 0.18 * sin(2 * .pi * frequency * 2 * t)
            return Float(tone * envelope * 0.42)
        }
    }
    static func waveData(phase: Int) -> Data {
        let values = samples(phase: phase)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(36 + values.count * 2)); text("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16))
        text("data"); integer(UInt32(values.count * 2))
        for value in values { integer(Int16(max(-1, min(1, value)) * 32767)) }
        return data
    }
}

@MainActor final class BreathingCuePlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var volume: Float = 0.55 { didSet { player?.volume = volume } }
    @Published private(set) var message: String?
    private let owner = UUID()
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private var introID: ObjectIdentifier?
    private var introCompletion: (() -> Void)?
    private var introWatchdog: Task<Void, Never>?
    private var selectedVoice: AVSpeechSynthesisVoice?
    @Published private(set) var voiceDescription = ""
    override init() { super.init(); speech.delegate = self; refreshVoice() }

    func refreshVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let choice = BreathingVoiceSelection.preferred(voices.map {
            .init(identifier: $0.identifier, language: $0.language, female: $0.gender == .female, quality: $0.quality.rawValue)
        })
        selectedVoice = choice.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
        guard let voice = selectedVoice else {
            voiceDescription = "未找到中文女声。可在系统设置 → 辅助功能 → 朗读与语音（或朗读内容）中下载中文女声。"; return
        }
        voiceDescription = voice.quality == .default ? "轻声女声 · \(voice.name)。想更自然，可在系统辅助功能的中文声音中下载增强或优质声音，返回后自动优先使用。" : "轻声女声 · \(voice.name) · 高质量声音"
    }

    private func acquire() -> Bool {
        guard !AudioCoordinator.shared.recording else {
            message = "手机监测正在录音，语音和提示音暂不播放。"; return false
        }
        guard WhiteNoisePlayer.shared.deadline == nil else {
            message = "请先停止声音陪伴，再开始呼吸引导。"; return false
        }
        guard AudioCoordinator.shared.ownsPlayback(owner) || AudioCoordinator.shared.beginPlayback(owner: owner) else {
            message = "声音暂不可用，请检查音频输出后重试。"; return false
        }
        AudioCoordinator.shared.stopPlayback = { [weak self] in self?.stop() }
        message = nil
        return true
    }
    func introduction(completion: @escaping () -> Void) {
        stop()
        guard acquire() else { completion(); return }
        guard let utterance = utterance("把呼吸，慢慢交给自己。") else { completion(); return }
        introCompletion = completion; introID = ObjectIdentifier(utterance)
        speech.speak(utterance)
        // A missing system voice must not leave the exercise stuck in preparation.
        introWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.introID != nil else { return }
            let finish = self.introCompletion
            self.introID = nil; self.introCompletion = nil
            self.speech.stopSpeaking(at: .immediate)
            finish?()
            self.message = "中文开场语暂不可用，已开始倒计时。请检查系统中文声音。"
        }
    }
    func play(phase: Int, tone: Bool = true, voice: Bool = false) {
        guard tone || voice else { stop(); return }
        guard acquire() else { return }
        introCompletion = nil; introID = nil
        introWatchdog?.cancel(); introWatchdog = nil
        speech.stopSpeaking(at: .immediate)
        if voice, let word = utterance(["吸气", "屏息", "呼气"][max(0, min(2, phase))]) { speech.speak(word) }
        guard tone else { return }
        do {
            player = try AVAudioPlayer(data: BreathingCueTone.waveData(phase: phase))
            player?.volume = volume
            player?.prepareToPlay()
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
        } catch {
            stop(); message = "未能播放提示音，请检查媒体音量和耳机连接。"
        }
    }
    func stop() {
        introID = nil; introCompletion = nil
        introWatchdog?.cancel(); introWatchdog = nil
        speech.stopSpeaking(at: .immediate)
        player?.stop(); player = nil
        AudioCoordinator.shared.endPlayback(owner: owner)
    }
    private func utterance(_ text: String) -> AVSpeechUtterance? {
        guard let voice = selectedVoice else {
            message = "中文语音暂不可用，可在系统辅助功能的朗读内容中下载中文声音；轻柔提示音仍可使用。"; return nil
        }
        let word = AVSpeechUtterance(string: text)
        word.voice = voice; word.rate = 0.38; word.pitchMultiplier = 1.02; word.volume = volume
        word.preUtteranceDelay = 0; word.postUtteranceDelay = 0.08
        return word
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.introID == id else { return }
            let finish = self.introCompletion
            self.introWatchdog?.cancel(); self.introWatchdog = nil
            self.introID = nil; self.introCompletion = nil; finish?()
        }
    }
}

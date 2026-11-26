import AVFoundation
import Combine

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

@MainActor final class BreathingCuePlayer: ObservableObject {
    @Published var volume: Float = 0.55 { didSet { player?.volume = volume } }
    @Published private(set) var message: String?
    private let owner = UUID()
    private var player: AVAudioPlayer?
    private var completion: Task<Void, Never>?

    func play(phase: Int) {
        guard !AudioCoordinator.shared.recording else {
            message = "手机监测正在录音，提示音暂不播放。"; return
        }
        guard WhiteNoisePlayer.shared.deadline == nil else {
            message = "请先停止声音陪伴，再试听呼吸提示音。"; return
        }
        completion?.cancel()
        guard AudioCoordinator.shared.beginPlayback(owner: owner) else {
            message = "声音暂不可用，请检查音频输出后重试。"; return
        }
        do {
            player = try AVAudioPlayer(data: BreathingCueTone.waveData(phase: phase))
            player?.volume = volume
            player?.prepareToPlay()
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
            message = nil
            AudioCoordinator.shared.stopPlayback = { [weak self] in self?.stop() }
            completion = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                self?.stop()
            }
        } catch {
            stop(); message = "未能播放提示音，请检查媒体音量和耳机连接。"
        }
    }
    func stop() {
        completion?.cancel(); completion = nil
        player?.stop(); player = nil
        AudioCoordinator.shared.endPlayback(owner: owner)
    }
}

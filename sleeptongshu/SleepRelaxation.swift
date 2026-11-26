import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

@MainActor final class AudioCoordinator {
    static let shared = AudioCoordinator()
    var recording = false
    var stopPlayback: (() -> Void)?
    private var playbackOwner: UUID?
    func ownsPlayback(_ owner: UUID) -> Bool { playbackOwner == owner && !recording }
    func beginPlayback(owner: UUID) -> Bool {
        guard !recording else { return false }
        let stop = stopPlayback; stopPlayback = nil; stop?()
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try AVAudioSession.sharedInstance().setActive(true); playbackOwner = owner; return true }
        catch { return false }
    }
    func endPlayback(owner: UUID) {
        guard playbackOwner == owner else { return }
        playbackOwner = nil; stopPlayback = nil
        if !recording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func beginRecording() { let stop = stopPlayback; stopPlayback = nil; stop?(); playbackOwner = nil; recording = true }
    func endRecording() { recording = false }
}

enum BreathingCycle {
    static func phase(elapsed: TimeInterval) -> (title: String, remaining: Int, expanded: Bool) {
        let second = max(0, Int(elapsed)) % 19
        if second < 4 { return ("吸气", 4 - second, true) }
        if second < 11 { return ("屏息", 11 - second, true) }
        return ("呼气", 19 - second, false)
    }
}
enum AudioCountdown {
    static func gain(remaining: TimeInterval) -> Float { Float(max(0, min(1, remaining / 10))) }
}
struct BreathingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var cue = BreathingCuePlayer()
    @State private var running = false
    @State private var elapsed: TimeInterval = 0
    @State private var lastTick = Date.now
    @AppStorage("breathingCueEnabled") private var cues = true
    private var phaseIndex: Int { let second = max(0, Int(elapsed)) % 19; return second < 4 ? 0 : second < 11 ? 1 : 2 }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !running)) { context in
            let phase = BreathingCycle.phase(elapsed: elapsed)
            ScrollView { VStack(spacing: 28) {
                ZStack {
                    ForEach(0..<3) { index in
                        Circle().stroke(SleepPalette.teal.opacity(0.04 + Double(index) * 0.025), lineWidth: 1)
                            .padding(CGFloat(index) * 14)
                    }
                    Circle().stroke(SleepPalette.teal.opacity(0.15), lineWidth: 20)
                    Circle().fill(SleepPalette.teal.opacity(0.2)).scaleEffect(phase.expanded ? 0.95 : 0.62)
                        .animation(reduceMotion ? nil : .easeInOut(duration: phase.expanded ? 4 : 8), value: phase.expanded)
                    VStack { Text(phase.title).font(.largeTitle.bold()); Text("\(phase.remaining)").font(.title.monospacedDigit()) }
                }.frame(width: 230, height: 230).accessibilityElement(children: .combine)
                HStack(spacing: 18) {
                    Label("吸气 4秒", systemImage: "arrow.up")
                    Label("屏息 7秒", systemImage: "pause")
                    Label("呼气 8秒", systemImage: "arrow.down")
                }.font(.caption).foregroundStyle(SleepPalette.muted)
                HStack {
                    Button {
                        running.toggle(); lastTick = .now
                        if running && cues { cue.play(phase: phaseIndex) } else { cue.stop() }
                    } label: { Label(running ? "暂停" : "开始", systemImage: running ? "pause.fill" : "play.fill").padding(.vertical, 8) }.buttonStyle(.borderedProminent)
                    Button { running = false; elapsed = 0; cue.stop() } label: { Label("结束", systemImage: "stop.fill").padding(.vertical, 8) }.buttonStyle(.bordered)
                }
                Text("把呼吸，慢慢交还给自己").font(.title3.bold()).multilineTextAlignment(.center)
                Toggle("阶段提示音", isOn: $cues).frame(maxWidth: 300)
                HStack {
                    Image(systemName: "speaker.wave.1")
                    Slider(value: $cue.volume, in: 0.1...1).accessibilityLabel("提示音音量")
                    Button { cue.play(phase: phaseIndex) } label: { Image(systemName: "speaker.wave.2.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("试听轻柔提示音").accessibilityIdentifier("previewBreathingCue")
                }.frame(maxWidth: 350)
                if let message = cue.message { Text(message).font(.caption).foregroundStyle(SleepPalette.rose) }
                Text("开始及切换阶段时响起轻柔提示音。听不到时请调高手机媒体音量，并检查是否连着耳机。录音或声音陪伴期间不播放提示音。").font(.caption).foregroundStyle(SleepPalette.muted)
                Text("量力而行，不适时停止，恢复自然呼吸。").font(.caption).foregroundStyle(SleepPalette.muted)
                Spacer(minLength: 0)
                }.padding(24).padding(.top, 30).frame(maxWidth: .infinity) }.background(SleepPalette.background)
                .onChange(of: context.date) { _, now in if running { elapsed += max(0, now.timeIntervalSince(lastTick)) }; lastTick = now }
                .onChange(of: phase.title) { _, _ in
                    if running, cues { cue.play(phase: phaseIndex) }
                }
        }.navigationTitle("4-7-8 呼吸").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onChange(of: cues) { _, enabled in if !enabled { cue.stop() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { running = false; cue.stop() } }
            .onDisappear { running = false; cue.stop() }
    }
}

@MainActor final class WhiteNoisePlayer: ObservableObject {
    static let shared = WhiteNoisePlayer()
    @Published private(set) var playing = false
    @Published private(set) var message: String?
    @Published var volume: Float = 0.35 { didSet { player?.volume = volume } }
    @Published private(set) var deadline: Date?
    @Published private(set) var loading = false
    @Published private(set) var sound = GroveNoise.library[0]
    private let owner = UUID()
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var interruption: NSObjectProtocol?
    private init() {
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pause() } }
    }
    func start(minutes: Int, sound next: GroveNoise = GroveNoise.library[0]) async {
        guard !playing, !loading else { return }
        loading = true; defer { loading = false }
        message = nil
        guard AudioCoordinator.shared.beginPlayback(owner: owner) else { message = "手机正在监测或音频不可用，请结束监测后再播放。"; return }
        do {
            if player == nil || sound != next {
                // Original procedural white noise: no external recording/license or large download.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("sleepgrove-noise-\(next.id).wav")
                try await Task.detached(priority: .utility) { try Self.render(next, to: url) }.value
                player = try AVAudioPlayer(contentsOf: url); player?.numberOfLoops = -1
                sound = next
            }
            guard AudioCoordinator.shared.ownsPlayback(owner) else { message = "音频任务已切换，未开始播放。"; return }
            AudioCoordinator.shared.stopPlayback = { [weak self] in self?.stop() }
            deadline = .now.addingTimeInterval(Double(minutes) * 60)
            resume()
            task?.cancel()
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let end = self.deadline else { return }
                    let remaining = end.timeIntervalSinceNow
                    if remaining <= 0 { self.stop(); return }
                    if self.playing { self.player?.volume = self.volume * AudioCountdown.gain(remaining: remaining) }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } catch { message = "暂时无法播放白噪音，请稍后重试。"; AudioCoordinator.shared.endPlayback(owner: owner) }
    }
    func resume() {
        guard !AudioCoordinator.shared.recording, let player, deadline.map({ $0 > .now }) ?? false else { return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback); try AVAudioSession.sharedInstance().setActive(true) }
        catch { message = "音频暂不可用，请稍后再试。"; return }
        player.volume = volume; playing = player.play()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "SleepGrove · " + sound.title, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1 : 0]
    }
    func pause() { player?.pause(); playing = false; MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0 }
    func stop() { task?.cancel(); task = nil; player?.stop(); playing = false; deadline = nil; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; AudioCoordinator.shared.endPlayback(owner: owner) }
    nonisolated private static func render(_ sound: GroveNoise, to url: URL) throws {
        let rate = 22050.0, samples = sound.samples()
        let count = samples.count
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { buffer.floatChannelData![0][i] = samples[i] }
        let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer)
    }
}
struct WhiteNoiseView: View {
    @StateObject private var audio = WhiteNoisePlayer.shared
    @State private var minutes = 30
    @State private var selection = 0
    var body: some View {
        Form {
            Section {
                Image(systemName: "waveform").font(.system(size: 60)).frame(maxWidth: .infinity).padding(30).foregroundStyle(SleepPalette.teal)
                Text(GroveNoise.library[selection].title).font(.title2.bold())
                Text("24 种本机合成音色，包含白噪、粉噪和棕噪的不同变化。风、雨与水声为声音意象，不是实地录音。手机监测开始时停止播放。").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("选择合成音色") {
                Picker("音色", selection: $selection) {
                    ForEach(GroveNoise.library) { sound in Text(sound.title).tag(sound.id) }
                }.disabled(audio.loading || audio.deadline != nil).accessibilityIdentifier("groveNoiseSelection")
                Text("先停止播放，再切换音色。").font(.caption).foregroundStyle(.secondary)
            }
            Section("音量") { Slider(value: $audio.volume, in: 0...1).accessibilityLabel("音量") }
            Section("关闭定时") {
                Picker("时长", selection: $minutes) { ForEach([5,15,30,45,60,90], id: \.self) { Text("\($0) 分钟").tag($0) } }.disabled(audio.deadline != nil)
                if let end = audio.deadline { Text("将在 \(end.formatted(date: .omitted, time: .shortened)) 前渐弱停止，离开页面后仍有效。") }
                Button { if audio.playing { audio.pause() } else if audio.deadline != nil { audio.resume() } else { Task { await audio.start(minutes: minutes, sound: GroveNoise.library[selection]) } } } label: { Label(audio.loading ? "准备中" : audio.playing ? "暂停" : "播放", systemImage: audio.playing ? "pause.fill" : "play.fill") }.disabled(audio.loading)
                Button { audio.stop() } label: { Label("停止并关闭定时", systemImage: "stop.fill") }
                if let message = audio.message { Text(message).foregroundStyle(.secondary) }
            }
        }.navigationTitle("白噪音").toolbar(.visible, for: .navigationBar)
            .onAppear { if audio.deadline != nil { selection = audio.sound.id } }
    }
}
struct GoodnightView: View {
    @EnvironmentObject private var content: ContentStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image("kepu-02").resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                Text("今晚，先放下未完成").font(.largeTitle.bold())
                Text(content.items.first(where: { $0.kind == "goodnight" })?.body ?? "给自己一点不必赶路的时间。放松肩膀，慢慢呼吸，让今天到这里就好。").font(.title3).lineSpacing(9)
                NavigationLink { BreathingView() } label: { Label("一起慢慢呼吸", systemImage: "wind") }.buttonStyle(.borderedProminent)
                NavigationLink { WhiteNoiseView() } label: { Label("听一会儿白噪音", systemImage: "waveform") }
            }.padding(24).frame(maxWidth: 680)
        }.background(SleepPalette.background).navigationTitle("晚安").toolbar(.visible, for: .navigationBar)
    }
}

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
    @State private var preparing = false
    @State private var elapsed: TimeInterval = 0
    @State private var lastTick = Date.now
    @AppStorage("breathingCueEnabled") private var cues = true
    @AppStorage("breathingVoiceEnabled") private var voice = true
    private var phaseIndex: Int { let second = max(0, Int(elapsed)) % 19; return second < 4 ? 0 : second < 11 ? 1 : 2 }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !running)) { context in
            let phase = BreathingCycle.phase(elapsed: elapsed)
            ScrollView { VStack(spacing: 28) {
                GroveSectionBanner(title: "把呼吸，慢慢交给自己", subtitle: preparing ? "听完开场语，再一起吸气" : "跟随声音，也跟随自己的节奏", symbol: "wind", color: .lavender)
                ZStack {
                    ForEach(0..<3) { index in
                        Circle().stroke(SleepPalette.teal.opacity(0.04 + Double(index) * 0.025), lineWidth: 1)
                            .padding(CGFloat(index) * 14)
                    }
                    Circle().stroke(GroveColor.coral.tint.opacity(0.25), lineWidth: 20)
                    Circle().fill(GroveColor.lavender.wash).scaleEffect(phase.expanded ? 0.95 : 0.62)
                        .animation(reduceMotion ? nil : .easeInOut(duration: phase.expanded ? 4 : 8), value: phase.expanded)
                    VStack { Text(preparing ? "准备" : phase.title).font(.largeTitle.bold()); Text(preparing ? "放松肩膀" : "\(phase.remaining)").font(.title.monospacedDigit()) }
                }.frame(width: 230, height: 230).accessibilityElement(children: .combine)
                HStack(spacing: 18) {
                    Label("吸气 4秒", systemImage: "arrow.up")
                    Label("屏息 7秒", systemImage: "pause")
                    Label("呼气 8秒", systemImage: "arrow.down")
                }.font(.caption).foregroundStyle(SleepPalette.muted)
                HStack {
                    Button {
                        if running || preparing { running = false; preparing = false; cue.stop() }
                        else if elapsed == 0, voice {
                            preparing = true
                            cue.introduction { guard preparing else { return }; preparing = false; startClock() }
                        } else { startClock() }
                    } label: { Label(running || preparing ? "暂停" : "开始", systemImage: running || preparing ? "pause.fill" : "play.fill").padding(.vertical, 8) }.buttonStyle(.borderedProminent).tint(GroveColor.lavender.tint).foregroundStyle(SleepPalette.onAccent)
                    Button { running = false; preparing = false; elapsed = 0; cue.stop() } label: { Label("结束", systemImage: "stop.fill").padding(.vertical, 8) }.buttonStyle(.bordered)
                }
                Toggle("轻声语音引导", isOn: $voice).frame(maxWidth: 300)
                Toggle("阶段提示音", isOn: $cues).frame(maxWidth: 300)
                HStack {
                    Image(systemName: "speaker.wave.1")
                    Slider(value: $cue.volume, in: 0.1...1).accessibilityLabel("提示音音量")
                    Button { cue.play(phase: phaseIndex) } label: { Image(systemName: "speaker.wave.2.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("试听轻柔提示音").accessibilityIdentifier("previewBreathingCue")
                }.frame(maxWidth: 350)
                if let message = cue.message { Text(message).font(.caption).foregroundStyle(SleepPalette.rose) }
                Text("开场语结束后开始计时，阶段语音与倒计时同步切换。听不到时请检查媒体音量和耳机连接。录音或声音陪伴期间不播放引导。").font(.caption).foregroundStyle(SleepPalette.muted)
                Text("量力而行，不适时停止，恢复自然呼吸。").font(.caption).foregroundStyle(SleepPalette.muted)
                Spacer(minLength: 0)
                }.padding(24).padding(.top, 30).frame(maxWidth: .infinity) }.background(SleepPalette.background)
                .onChange(of: context.date) { _, now in if running { elapsed += max(0, now.timeIntervalSince(lastTick)) }; lastTick = now }
                .onChange(of: phase.title) { _, _ in
                    if running { cue.play(phase: phaseIndex, tone: cues, voice: voice) }
                }
        }.navigationTitle("4-7-8 呼吸").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onChange(of: cues) { _, _ in if running { cue.play(phase: phaseIndex, tone: cues, voice: voice) } }
            .onChange(of: voice) { _, _ in preparing = false; if running { cue.play(phase: phaseIndex, tone: cues, voice: voice) } else { cue.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in running = false; preparing = false; cue.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { running = false; preparing = false; cue.stop() } }
            .onDisappear { running = false; preparing = false; cue.stop() }
    }
    private func startClock() { lastTick = .now; running = true; cue.play(phase: phaseIndex, tone: cues, voice: voice) }
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
    private var operation = UUID()
    private var interruption: NSObjectProtocol?
    private init() {
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pause() } }
    }
    func start(minutes: Int, sound next: GroveNoise = GroveNoise.library[0]) async {
        stop()
        let request = UUID(); operation = request
        loading = true; defer { if operation == request { loading = false } }
        message = nil
        guard AudioCoordinator.shared.beginPlayback(owner: owner) else { message = "手机正在监测或音频不可用，请结束监测后再播放。"; return }
        AudioCoordinator.shared.stopPlayback = { [weak self] in self?.stop() }
        do {
            if player == nil || sound != next {
                // Original procedural white noise: no external recording/license or large download.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("sleepgrove-noise-\(request).wav")
                defer { try? FileManager.default.removeItem(at: url) }
                try await Task.detached(priority: .utility) { try Self.render(next, to: url) }.value
                guard operation == request, !Task.isCancelled, AudioCoordinator.shared.ownsPlayback(owner) else { return }
                player = try AVAudioPlayer(data: Data(contentsOf: url)); player?.numberOfLoops = -1
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
        } catch {
            guard operation == request else { return }
            stop(); message = "暂时无法播放白噪音，请稍后重试。"
        }
    }
    func resume() {
        guard AudioCoordinator.shared.ownsPlayback(owner), let player, deadline.map({ $0 > .now }) ?? false else { return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback); try AVAudioSession.sharedInstance().setActive(true) }
        catch { message = "音频暂不可用，请稍后再试。"; return }
        player.volume = volume; playing = player.play()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "SleepGrove · " + sound.title, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1 : 0]
    }
    func pause() { player?.pause(); playing = false; MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0 }
    func stop() { operation = UUID(); loading = false; task?.cancel(); task = nil; player?.stop(); playing = false; deadline = nil; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; AudioCoordinator.shared.endPlayback(owner: owner) }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var minutes = 30
    @State private var selection = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                controls
                Text("24 种声音，选一个陪伴今晚").font(.title2.bold())
                Text("点选即可播放和切换，每次选择重新开启定时。白噪、粉噪、棕噪均在本机合成；风、雨、水声是音色意象，并非自然实录。开始手机录音时自动停止。").font(.caption).foregroundStyle(SleepPalette.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
                    ForEach(GroveNoise.library) { sound in
                        Button {
                            selection = sound.id
                            Task { await audio.start(minutes: minutes, sound: sound) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                NoiseArtwork(sound: sound).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                                HStack(alignment: .top) {
                                    Text(sound.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: selection == sound.id && audio.playing ? "speaker.wave.2.fill" : "play.circle")
                                }
                                Text(["白噪 · 细密", "粉噪 · 柔和", "棕噪 · 低沉"][sound.family]).font(.caption).foregroundStyle(SleepPalette.muted)
                            }.foregroundStyle(SleepPalette.ink).padding(10)
                                .background(selection == sound.id ? GroveColor.allCases[sound.id % 5].wash : SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == sound.id ? GroveColor.allCases[sound.id % 5].tint : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityIdentifier("noise-\(sound.id)")
                            .accessibilityLabel(sound.title + "，点按播放")
                    }
                }.accessibilityIdentifier("groveNoiseSelection")
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).navigationTitle("声音陪伴").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear { if audio.deadline != nil { selection = audio.sound.id } }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.largeTitle).foregroundStyle(GroveColor.lavender.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GroveNoise.library[selection].title).font(.headline)
                    Text(audio.loading ? "正在准备声音…" : audio.playing ? "正在陪伴你" : "留一点安静给自己").font(.caption).foregroundStyle(SleepPalette.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 20) {
                Button { if audio.playing { audio.pause() } else if audio.deadline != nil { audio.resume() } else { Task { await audio.start(minutes: minutes, sound: GroveNoise.library[selection]) } } } label: {
                    Label(audio.playing ? "暂停" : "播放", systemImage: audio.playing ? "pause.fill" : "play.fill").frame(minHeight: 32)
                }.buttonStyle(.borderedProminent).tint(GroveColor.lavender.tint).foregroundStyle(SleepPalette.onAccent).disabled(audio.loading).accessibilityIdentifier("noisePlayPause")
                Button { audio.stop() } label: { Label("停止", systemImage: "stop.fill").frame(minHeight: 32) }.buttonStyle(.bordered).accessibilityIdentifier("noiseStop")
            }
            HStack { Image(systemName: "speaker.wave.1"); Slider(value: $audio.volume, in: 0...1).accessibilityLabel("音量"); Image(systemName: "speaker.wave.3") }.tint(GroveColor.coral.tint)
            Picker(selection: $minutes) { ForEach([5,15,30,45,60,90], id: \.self) { Text("\($0) 分钟").tag($0) } } label: { Label("关闭定时", systemImage: "timer") }
                .pickerStyle(.menu).disabled(audio.deadline != nil).accessibilityIdentifier("noiseTimer")
            if let end = audio.deadline { Text("\(end.formatted(date: .omitted, time: .shortened)) 渐弱停止，离开页面仍有效。停止后可重新设置时长。").font(.caption).foregroundStyle(SleepPalette.muted) }
            if let message = audio.message { Text(message).font(.caption).foregroundStyle(SleepPalette.rose) }
        }.groveWash(.lavender)
    }
}

/// Small native illustrations; each preset has its own color, symbol and wave contour.
private struct NoiseArtwork: View {
    let sound: GroveNoise
    private var color: GroveColor { GroveColor.allCases[sound.id % 5] }
    private var symbol: String {
        ["sparkles", "sun.haze.fill", "wind", "cloud.rain.fill", "cloud.fill", "leaf.fill", "fan.fill", "cloud.drizzle.fill",
         "waveform", "cloud.rain.fill", "water.waves", "tree.fill", "drop.fill", "cloud.moon.rain.fill", "leaf.fill", "water.waves",
         "moon.stars.fill", "wind", "water.waves", "cloud.rain.fill", "drop.fill", "cloud.moon.fill", "waveform", "water.waves"][sound.id]
    }
    var body: some View {
        ZStack {
            color.wash
            Canvas { context, size in
                for row in 0..<3 {
                    var path = Path()
                    for step in 0...60 {
                        let x = size.width * Double(step) / 60
                        let y = size.height * 0.7 + Double(row) * 11 + sin(Double(step) / 60 * .pi * Double(sound.id % 4 + 2) + Double(row)) * 7
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(color.tint.opacity(0.15)), lineWidth: 2)
                }
            }
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).symbolRenderingMode(.hierarchical).foregroundStyle(color.tint).offset(y: -8)
        }.accessibilityHidden(true)
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

import Foundation
import AVFoundation
import SwiftUI
import SwiftData

struct NightVoiceClip: Codable, Identifiable {
    var id: UUID
    var start: Date
    var duration: Double
    var confidence: Double
    var file: String
    var source = "手机麦克风 · 本机声音分类"
}
enum NightAudioStorage {
    static let directory = URL.applicationSupportDirectory.appendingPathComponent("NightVoice", isDirectory: true)
    static let maximumBytes: Int64 = 200 * 1024 * 1024
    static let retention: TimeInterval = 7 * 86400
    static func clips(at directory: URL = directory) -> [NightVoiceClip] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let bytes = try? Data(contentsOf: url), let clip = try? JSONDecoder().decode(NightVoiceClip.self, from: bytes),
                  URL(fileURLWithPath: clip.file).lastPathComponent == clip.file,
                  clip.file == clip.id.uuidString + ".caf", clip.duration.isFinite, clip.duration > 0,
                  (0...1).contains(clip.confidence),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent(clip.file).path) else { return nil }
            return clip
        }.sorted { $0.start > $1.start }
    }
    static func delete(_ clip: NightVoiceClip, at directory: URL = directory) throws {
        guard clip.file == clip.id.uuidString + ".caf" else { throw CocoaError(.fileReadInvalidFileName) }
        let audio = directory.appendingPathComponent(clip.file)
        if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
        let meta = directory.appendingPathComponent(clip.id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: meta.path) { try FileManager.default.removeItem(at: meta) }
    }
    static func clean(now: Date = .now, at directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for clip in clips(at: directory) where now.timeIntervalSince(clip.start) > retention { try delete(clip, at: directory) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let known = Set(clips(at: directory).map(\.file))
        for file in files where file.pathExtension == "caf" && !known.contains(file.lastPathComponent) {
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? now
            if now.timeIntervalSince(modified) > 3600 { try FileManager.default.removeItem(at: file) }
        }
    }
    static func bytes(at directory: URL = directory) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

/// Used only on NightSoundAnalyzer.queue. Non-speech segments are discarded;
/// at most two recent segments wait for asynchronous classification results.
final class NightVoiceWriter {
    private struct Segment { var clip: NightVoiceClip; var end: Date }
    private var file: AVAudioFile?
    private var current: Segment?
    private var recent: [Segment] = []
    private var frames: AVAudioFrameCount = 0
    private var stopped = false
    private var checkedAt = Date.distantPast
    private let directory: URL
    var failure: (() -> Void)?
    init(directory: URL = NightAudioStorage.directory) throws { self.directory = directory; try NightAudioStorage.clean(at: directory) }
    func accept(_ buffer: AVAudioPCMBuffer, start: Date) {
        guard !stopped else { return }
        do {
            // Directory scans belong at segment boundaries, never on every audio buffer.
            if Date.now.timeIntervalSince(checkedAt) >= 15 {
                let available = (try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])).volumeAvailableCapacity ?? 0
                guard available > 100 * 1024 * 1024, NightAudioStorage.bytes(at: directory) < NightAudioStorage.maximumBytes - 12 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
                checkedAt = .now
            }
            if file == nil {
                let id = UUID()
                current = Segment(clip: NightVoiceClip(id: id, start: start, duration: 0, confidence: 0, file: id.uuidString + ".caf"), end: start)
                let url = directory.appendingPathComponent(current!.clip.file)
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
                frames = 0
            }
            try file?.write(from: buffer); frames += buffer.frameLength
            current?.clip.duration = Double(frames) / buffer.format.sampleRate
            if let clip = current?.clip { current?.end = clip.start.addingTimeInterval(clip.duration) }
            if Double(frames) / buffer.format.sampleRate >= 15 { rotate() }
        } catch { stopped = true; file = nil; failure?() }
    }
    func speech(start: Date, end: Date, confidence: Double) {
        if let segment = current, segment.clip.start < end && segment.end > start { current?.clip.confidence = max(segment.clip.confidence, confidence) }
        for index in recent.indices where recent[index].clip.start < end && recent[index].end > start { recent[index].clip.confidence = max(recent[index].clip.confidence, confidence) }
    }
    private func rotate() {
        file = nil
        if let current { recent.append(current) }; current = nil
        while recent.count > 2 { persist(recent.removeFirst()) }
    }
    private func persist(_ segment: Segment) {
        do {
            if segment.clip.confidence >= 0.75 {
                let data = try JSONEncoder().encode(segment.clip)
                try data.write(to: directory.appendingPathComponent(segment.clip.id.uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else { try FileManager.default.removeItem(at: directory.appendingPathComponent(segment.clip.file)) }
        } catch { failure?() }
    }
    func finish() { rotate(); for segment in recent { persist(segment) }; recent = [] }
}

struct NightAudioLibraryView: View {
    @Query private var records: [SleepRecord]
    @State private var clips: [NightVoiceClip] = []
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var message: String?
    @State private var position = 0.0
    @State private var audioOwner = UUID()
    var body: some View {
        List {
            Section {
                Text("候选语音不一定是梦话，也可能来自他人或环境。置信度仅表示分类模型对语音的判断，不判断说话者。仅在本机保留 7 天，上限 200 MB；不会自动上传。").font(.footnote).foregroundStyle(.secondary)
                Button("清理过期音频") { Task { try? await Task.detached { try NightAudioStorage.clean() }.value; reload() } }
            }
            if clips.isEmpty { ContentUnavailableView("暂无候选语音", systemImage: "waveform", description: Text("开启手机监测前，同意保存候选语音后才会记录。")) }
            ForEach(clips) { clip in
                Section {
                    Text(clip.start.formatted(date: .abbreviated, time: .standard)).font(.headline)
                    Text("\(Int(clip.duration)) 秒 · 语音置信度 \(Int(clip.confidence * 100))% · 手机麦克风").font(.caption)
                    let aligned = records.filter { $0.start < clip.start.addingTimeInterval(clip.duration) && $0.end > clip.start }
                    if !aligned.isEmpty { Text("与 \(aligned.count) 条睡眠记录时间重叠，可对照同晚记录查看；不据此推算睡眠阶段。").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button { play(clip) } label: { Label(playingID == clip.id ? "暂停" : "播放", systemImage: playingID == clip.id ? "pause.fill" : "play.fill") }
                        ShareLink(item: NightAudioStorage.directory.appendingPathComponent(clip.file)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("主动导出音频")
                        Spacer()
                        Button(role: .destructive) { if playingID == clip.id { stop() }; do { try NightAudioStorage.delete(clip); reload() } catch { message = "音频未能删除，请重试。" } } label: { Image(systemName: "trash") }.accessibilityLabel("删除音频")
                    }.buttonStyle(.borderless)
                    if playingID == clip.id {
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Slider(value: Binding(get: { player?.currentTime ?? 0 }, set: { player?.currentTime = $0 }), in: 0...max(1, clip.duration)).accessibilityLabel("播放位置")
                        }
                    }
                }
            }
            if let message { Section { Text(message) } }
        }.navigationTitle("候选语音").toolbar(.visible, for: .navigationBar)
            .task { try? await Task.detached { try NightAudioStorage.clean() }.value; reload() }.onDisappear { stop() }
    }
    private func reload() { clips = NightAudioStorage.clips() }
    private func stop() { player?.stop(); player = nil; playingID = nil; AudioCoordinator.shared.endPlayback(owner: audioOwner) }
    private func play(_ clip: NightVoiceClip) {
        if playingID == clip.id { stop(); return }
        guard AudioCoordinator.shared.beginPlayback(owner: audioOwner) else { message = "请结束手机监测后再回听。"; return }
        do {
            player = try AVAudioPlayer(contentsOf: NightAudioStorage.directory.appendingPathComponent(clip.file))
            AudioCoordinator.shared.stopPlayback = { stop() }
            playingID = clip.id; player?.play()
        } catch { message = "无法打开音频，文件可能已清理。" }
    }
}

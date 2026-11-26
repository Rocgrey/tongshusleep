import SwiftUI
import AVKit

/// Manufacturer introduction is separate from the live, published shopping catalog.
struct ProductIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "认识掌心安睡仪", subtitle: "TS-601-A · 低频脉冲治疗仪")
            Link(destination: URL(string: "https://sleep.tongshugene.net/product.html#pdUse")!) {
                HStack(spacing: 14) {
                    Image(systemName: "book.closed.fill").font(.title)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("查看官方使用说明").font(.headline)
                        Text("操作步骤 · 适用范围 · 使用注意事项").font(.caption)
                    }
                    Spacer(minLength: 0); Image(systemName: "arrow.up.right")
                }.foregroundStyle(GroveColor.coral.tint).groveWash(.coral)
            }.accessibilityIdentifier("productOfficialManual")
            ProductVideoView()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { frequencies }
                VStack(alignment: .leading, spacing: 14) { frequencies }
            }.padding(.vertical, 6)
            Text("设备通过耳部电极使用，配合导电凝胶贴。三档脉冲频率可按说明书选择，操作方式、适用范围与注意事项请以随附说明书为准。")
                .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                Text("产品参数").font(.headline)
                ForEach(Array(Self.specifications.enumerated()), id: \.offset) { index, spec in
                    HStack(alignment: .top, spacing: 12) {
                        Text(spec.0).font(.subheadline).foregroundStyle(GroveColor.allCases[index % 5].tint).frame(width: 96, alignment: .leading)
                        Text(spec.1).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 4)
                    Divider()
                }
            }
            Text("资料与图片来自桐树家医官网。设备介绍不替代使用说明；商品信息与购买入口以平台发布的内容为准。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
        }
    }
    // Only parameters explicitly listed on the manufacturer's product page.
    static let specifications = [
        ("型号", "TS-601-A"), ("技术方式", "经颅微电流刺激（CES），按说明书使用"),
        ("输出频率", "2 / 5 / 10 Hz"), ("输出电流", "0.1–0.6 mA，6 档，最大不超过 0.6 mA"),
        ("输出波形", "非对称方波"), ("电极耗材", "导电水凝胶片"), ("单次时长", "15 分钟，自动停止"),
        ("供电与充电", "3.7 V 锂电池 · Type-C"), ("使用期限", "5 年"),
        ("保修", "主机 1 年，凝胶贴 3 个月；以随附条款为准")
    ]
    @ViewBuilder private var frequencies: some View {
        ForEach([2, 5, 10], id: \.self) { value in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value) Hz").font(.title2.weight(.semibold)).foregroundStyle(GroveColor.allCases[value % 3].tint)
                Text("脉冲频率").font(.caption).foregroundStyle(SleepPalette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline and fullscreen share a single player, position and audio-session owner.
@MainActor final class ProductVideoPlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var message: String?
    private let owner = UUID()
    nonisolated static let url = URL(string: "https://vid.sleep.phoenixtreeai.com/video/product-promo.mp4")!
    private let makePlayer: () -> AVPlayer
    init(makePlayer: @escaping () -> AVPlayer = { AVPlayer(url: ProductVideoPlayback.url) }) { self.makePlayer = makePlayer }
    func play() {
        guard AudioCoordinator.shared.ownsPlayback(owner) || AudioCoordinator.shared.beginPlayback(owner: owner) else {
            message = "手机正在监测，请结束监测后播放。"; return
        }
        message = nil
        // Exact resource listed by the manufacturer. No media request before a user tap.
        let next = player ?? makePlayer()
        player = next
        AudioCoordinator.shared.stopPlayback = { [weak self] in self?.stop() }
        next.play()
    }
    func stop() {
        player?.pause(); player = nil
        AudioCoordinator.shared.endPlayback(owner: owner)
    }
    func failed() { stop(); message = "视频暂不可用，请检查网络后重试。" }
}

struct ProductVideoView: View {
    @StateObject private var playback = ProductVideoPlayback()
    @Environment(\.scenePhase) private var scenePhase
    @State private var fullscreen = false
    @State private var landscape = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            surface.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Label("掌心安睡仪 · 产品介绍", systemImage: "film").font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Button { fullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("全屏播放产品介绍").accessibilityIdentifier("productVideoFullscreen")
            }
            if let message = playback.message {
                Text(message).font(.caption).foregroundStyle(SleepPalette.rose)
                Button("重试播放", systemImage: "arrow.clockwise") { playback.play() }.buttonStyle(GroveButtonStyle(.secondary))
            }
        }
        .fullScreenCover(isPresented: $fullscreen, onDismiss: { landscape = false; CourseOrientation.restorePortrait() }) {
            NavigationStack {
                ZStack { Color.black.ignoresSafeArea(); surface }
                    .navigationTitle("产品介绍").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                landscape.toggle()
                                CourseOrientation.request(landscape ? .landscape : .portrait) { landscape = false }
                            } label: { Image(systemName: "rotate.right") }
                                .accessibilityLabel(landscape ? "退出横屏" : "横屏播放")
                        }
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { fullscreen = false } }
                    }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop() }
        .onDisappear { if !fullscreen { playback.stop() } }
    }
    @ViewBuilder private var surface: some View {
        if let player = playback.player, let item = player.currentItem {
            VideoPlayer(player: player).accessibilityIdentifier("productVideoPlayer")
                .onReceive(item.publisher(for: \.status).receive(on: RunLoop.main)) { status in
                    if status == .failed, playback.player === player { playback.failed() }
                }
        } else {
            Button { playback.play() } label: {
                ContentCover(name: "palm-device-official", ratio: 16 / 9)
                    .overlay { Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 6, y: 2) }
            }.buttonStyle(GrovePressStyle()).accessibilityLabel("播放产品介绍")
                .accessibilityIdentifier("productIntroductionVideo")
        }
    }
}

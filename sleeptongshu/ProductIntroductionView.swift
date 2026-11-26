import SwiftUI
import AVKit

/// Manufacturer introduction is separate from the live, published shopping catalog.
struct ProductIntroductionView: View {
    @State private var showingVideo = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ContentCover(name: "palm-device-official", ratio: 1.5)
                .accessibilityLabel("掌心安睡仪官方产品图：蓝色与白色机身")
            VStack(alignment: .leading, spacing: 8) {
                Text("桐树家医 · 掌心安睡仪").font(.caption.weight(.semibold)).foregroundStyle(SleepPalette.teal)
                Text("把睡前时光，留给自己").font(.title2.bold()).foregroundStyle(SleepPalette.ink)
                Text("TS-601-A · 低频脉冲设备").font(.subheadline).foregroundStyle(SleepPalette.muted)
            }
            Button { showingVideo = true } label: {
                Label("观看产品介绍", systemImage: "play.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("productIntroductionVideo")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { frequencies }
                VStack(alignment: .leading, spacing: 14) { frequencies }
            }.padding(.vertical, 6)
            Text("设备通过耳部电极使用，配合导电凝胶贴。三档脉冲频率可按说明书选择，操作方式、适用范围与注意事项请以随附说明书为准。")
                .font(.subheadline).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://sleep.tongshugene.net/product.html#pdUse")!) {
                Label("查看官方使用说明", systemImage: "doc.text")
            }.font(.subheadline).foregroundStyle(SleepPalette.teal)
            Text("资料与图片来自桐树家医官网。设备介绍不替代使用说明；商品信息与购买入口以平台发布的内容为准。")
                .font(.caption).foregroundStyle(SleepPalette.muted)
            Divider()
            SectionHeading(title: "商品与购买", subtitle: "来自平台的已发布商品")
        }.sheet(isPresented: $showingVideo) { ProductIntroductionVideo() }
    }
    @ViewBuilder private var frequencies: some View {
        ForEach([2, 5, 10], id: \.self) { value in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value) Hz").font(.title2.weight(.semibold)).foregroundStyle(SleepPalette.teal)
                Text("脉冲频率").font(.caption).foregroundStyle(SleepPalette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProductIntroductionVideo: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var message: String?
    @State private var owner = UUID()
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let player {
                    VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit)
                        .onReceive(player.publisher(for: \.status)) { status in
                            if status == .failed { message = "视频暂不可用，请检查网络后重试。" }
                        }
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
            }.padding().background(SleepPalette.background)
                .navigationTitle("掌心安睡仪介绍").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear {
                    guard AudioCoordinator.shared.beginPlayback(owner: owner) else {
                        message = "手机正在监测，请结束监测后播放。"; return
                    }
                    // Exact URL published by the manufacturer, not a guessed CDN path.
                    let p = AVPlayer(url: URL(string: "https://vid.sleep.phoenixtreeai.com/video/product-promo.mp4")!)
                    player = p
                    AudioCoordinator.shared.stopPlayback = { p.pause() }
                    p.play()
                }
                .onDisappear { player?.pause(); player = nil; AudioCoordinator.shared.endPlayback(owner: owner) }
        }
    }
}

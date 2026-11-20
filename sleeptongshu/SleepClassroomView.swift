import SwiftUI
import AVKit

struct SleepClassroomView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var routes: AppRoutes
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appAppearance") private var appearance = "fresh"
    @State private var selection = "课程"
    @State private var target: ClassroomItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("睡眠课堂").font(.largeTitle.bold())
                            Text("了解睡眠，也练习好好休息").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink { AppSettingsView() } label: { Image(systemName: "gearshape").font(.title2) }
                            .accessibilityLabel("设置").accessibilityIdentifier("enhancedSettings")
                    }
                    Picker("课堂栏目", selection: $selection) { ForEach(["课程", "阅读", "助眠", "产品"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("classroomSections")
                    if let message = content.message { Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary) }
                    if !content.hasRemoteCatalog { Text("随 App 提供的课堂内容").font(.caption).foregroundStyle(.secondary) }
                    if selection == "课程" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 145), spacing: 14, alignment: .top)], spacing: 18) {
                            ForEach(content.courses) { item in NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(.plain) }
                        }
                        if content.courses.isEmpty { empty("课程正在准备中") }
                    } else if selection == "阅读" {
                        ForEach(content.articles) { item in NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(.plain) }
                        if content.articles.isEmpty { empty("暂无已发布文章") }
                    } else if selection == "助眠" {
                        NavigationLink { BreathingView() } label: { tool("4-7-8 呼吸", "跟随自己的节奏慢下来", "wind") }
                        NavigationLink { WhiteNoiseView() } label: { tool("白噪音", "安静陪伴，定时渐弱停止", "waveform") }
                        NavigationLink { GoodnightView() } label: { tool("晚安卡", "给今天一个温柔的收尾", "moon.stars") }
                        ForEach(content.items.filter { ["noise", "breathing", "goodnight"].contains($0.kind) }) { item in
                            NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(content.items.filter { $0.kind == "product" }) { item in NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(.plain) }
                        if !content.items.contains(where: { $0.kind == "product" }) { empty("商品信息核实后会在这里展示") }
                    }
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .refreshable { await content.refresh(client: account.client, force: true) }
                .task { await content.refresh(client: account.client); resolveRoute() }
                .onChange(of: routes.target) { _, _ in resolveRoute() }
                .navigationDestination(item: $target) { ClassroomDetailView(item: $0) }
                .sheet(isPresented: Binding(get: { ["breathing", "noise", "goodnight"].contains(routes.target ?? "") }, set: { if !$0 { routes.target = nil } })) {
                    NavigationStack {
                        Group { if routes.target == "breathing" { BreathingView() } else if routes.target == "noise" { WhiteNoiseView() } else { GoodnightView() } }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { routes.target = nil } } }
                    }
                }
        }
    }
    private func resolveRoute() {
        if let route = routes.target, route.hasPrefix("content/") {
            if let item = content.items.first(where: { $0.id == String(route.dropFirst(8)) }) { target = item }
            else { routes.target = "goodnight" }
        }
    }
    private func empty(_ title: String) -> some View { ContentUnavailableView(title, systemImage: "books.vertical") }
    private func tool(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title).frame(width: 50).foregroundStyle(SleepPalette.teal)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right")
        }.padding(.vertical, 18).foregroundStyle(.primary)
    }
}
struct ContentCover: View {
    let name: String
    var body: some View {
        Rectangle().fill(SleepPalette.mint.opacity(0.15)).aspectRatio(1.6, contentMode: .fit)
            .overlay {
                GeometryReader { size in
                    Group {
                        if let url = ClassroomItem.https(name) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Image(systemName: "book.closed").frame(maxWidth: .infinity, maxHeight: .infinity) }
                            }
                        } else if UIImage(named: name) != nil { Image(name).resizable().scaledToFill() }
                        else { Image(systemName: "book.closed").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }.frame(width: size.size.width, height: size.size.height).clipped()
                }
            }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct ContentTile: View {
    let item: ClassroomItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContentCover(name: item.cover)
            Text(item.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Label(item.category, systemImage: item.kind == "course" ? "play.circle" : "book").font(.caption).foregroundStyle(SleepPalette.teal)
        }.padding(10).background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
struct ClassroomDetailView: View {
    private let initialItem: ClassroomItem
    @State private var refreshedItem: ClassroomItem?
    private var item: ClassroomItem { refreshedItem ?? initialItem }
    init(item: ClassroomItem) { initialItem = item }
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openURL) private var openURL
    @State private var lesson: ClassroomItem?
    @State private var unavailable = false
    @State private var external: URL?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if unavailable { ContentUnavailableView("内容暂不可用", systemImage: "book.closed", description: Text("内容可能已下架，返回课堂刷新后再试。")) }
                else {
                    ContentCover(name: item.cover)
                    Text(item.title).font(.title2.bold())
                    Text(item.summary).foregroundStyle(.secondary)
                    Text(item.body).font(.body).lineSpacing(7).textSelection(.enabled)
                    ForEach(content.children(item.id)) { chapter in
                        Button { lesson = chapter } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.title2)
                                VStack(alignment: .leading, spacing: 5) { Text(chapter.title).font(.headline); Text(chapter.preview_seconds == nil ? "完整播放" : "试看 \(Int(chapter.preview_seconds!)) 秒").font(.caption) }
                                Spacer()
                                if let key = progressKey(chapter), let progress = LearningProgress.read(key), progress.duration > 0 { ProgressView(value: min(1, progress.seconds / progress.duration)).frame(width: 45) }
                            }.padding(.vertical, 12)
                        }.buttonStyle(.plain).foregroundStyle(SleepPalette.teal)
                    }
                    if item.kind == "product", let url = ClassroomItem.https(item.external_url) {
                        Button { external = url } label: { Label("前往京东购买", systemImage: "arrow.up.right.square") }.buttonStyle(.borderedProminent)
                        Button { UIPasteboard.general.url = url } label: { Label("复制链接", systemImage: "doc.on.doc") }
                    }
                    if item.kind == "noise", item.mediaURL != nil {
                        Button { lesson = item } label: { Label("播放已发布音频", systemImage: "play.circle") }.buttonStyle(.borderedProminent)
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).navigationTitle(item.category).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .sheet(item: $lesson) { chapter in NavigationStack { ClassroomVideoView(item: chapter, progressKey: progressKey(chapter)) } }
            .confirmationDialog("将前往京东完成购买", isPresented: Binding(get: { external != nil }, set: { if !$0 { external = nil } })) {
                Button("继续前往") { if let external { openURL(external) }; external = nil }
            }
            .task {
                do { refreshedItem = try await content.freshItem(item.id, client: account.client) }
                catch let error as APIError { if case .business(404, _) = error { unavailable = true } }
                catch { }
            }
    }
    private func progressKey(_ chapter: ClassroomItem) -> String? { account.session.map { LearningProgress.key(service: account.client.serviceID, user: $0.user.id, item: chapter.id) } }
}
struct ClassroomVideoView: View {
    let item: ClassroomItem
    let progressKey: String?
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var content: ContentStore
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var observer: Any?
    @State private var message: String?
    @State private var limited = false
    @State private var active = true
    @State private var audioOwner = UUID()
    var body: some View {
        VStack(spacing: 20) {
            if let player { VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit) } else { ContentCover(name: item.cover) }
            Text(item.title).font(.title3.bold()).padding(.horizontal)
            if let message { Text(message).foregroundStyle(.secondary).padding() }
            if limited { Label("试看已结束，完整内容需原平台授权。", systemImage: "lock").padding() }
            Spacer()
        }.navigationTitle("课程播放").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { active = true; await load() }.onDisappear { active = false; stop() }
    }
    private func load() async {
        do {
            let fresh = try await content.freshItem(item.id, client: account.client)
            guard active, !Task.isCancelled else { return }
            guard let url = fresh.mediaURL else { message = "暂未提供可播放地址"; return }
            guard AudioCoordinator.shared.beginPlayback(owner: audioOwner) else { message = "手机正在监测，请结束监测后播放课程。"; return }
            let p = AVPlayer(url: url); player = p
            AudioCoordinator.shared.stopPlayback = { stop() }
            if let key = progressKey, let saved = LearningProgress.read(key), fresh.preview_seconds.map({ saved.seconds < $0 }) ?? true { await p.seek(to: CMTime(seconds: saved.seconds, preferredTimescale: 600)) }
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { time in
                Task { @MainActor in
                guard active, player === p else { return }
                let seconds = time.seconds
                if let limit = fresh.preview_seconds, seconds >= limit { p.pause(); limited = true; await p.seek(to: CMTime(seconds: limit, preferredTimescale: 600)) }
                if let key = progressKey, seconds.isFinite { LearningProgress.save(LessonProgress(seconds: min(seconds, fresh.preview_seconds ?? seconds), duration: fresh.duration ?? 0, updatedAt: .now), key: key) }
                }
            }
            if active, !Task.isCancelled, AudioCoordinator.shared.ownsPlayback(audioOwner) { p.play() } else { stop() }
        } catch { message = "课程暂时无法加载，请联网刷新后重试。" }
    }
    private func stop() {
        player?.pause(); if let observer { player?.removeTimeObserver(observer); self.observer = nil }
        player = nil; AudioCoordinator.shared.endPlayback(owner: audioOwner)
    }
}

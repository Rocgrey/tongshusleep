import SwiftUI
import AVKit

struct SleepClassroomView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var routes: AppRoutes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appearance = "fresh"
    @State private var selection = "课程"
    @State private var target: ClassroomItem?
    @State private var playingItem: ClassroomItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("睡眠课堂").font(.title2.bold())
                            Text("了解睡眠，也练习好好休息").font(.caption).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer()
                        NavigationLink { AppSettingsView() } label: { Image(systemName: "gearshape").font(.title2) }
                            .accessibilityLabel("设置").accessibilityIdentifier("enhancedSettings")
                    }
                    Picker("课堂栏目", selection: $selection) { ForEach(["课程", "阅读", "助眠", "产品"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("classroomSections")
                    if let message = content.message { Label(message, systemImage: content.hasRemoteCatalog ? "wifi.exclamationmark" : "info.circle").font(.caption).foregroundStyle(.secondary) }
                    if !content.hasRemoteCatalog, content.message == nil { Text("随 App 提供的课堂内容").font(.caption).foregroundStyle(.secondary) }
                    if content.canOpenBundledLibrary {
                        Button { content.openBundledLibrary() } label: { Label("查看随 App 课堂", systemImage: "books.vertical") }
                            .buttonStyle(.borderedProminent)
                    }
                    if selection == "课程" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 145), spacing: 14, alignment: .top)], spacing: 18) {
                            ForEach(content.courses) { item in
                                Button { playFirstLesson(of: item) } label: { ContentTile(item: item) }
                                    .buttonStyle(.plain).accessibilityIdentifier("classroomItem-" + item.id)
                            }
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
                        ForEach(content.items.filter { $0.kind == "product" }) { item in ProductTile(item: item) }
                        if !content.items.contains(where: { $0.kind == "product" }) { empty("商品信息核实后会在这里展示") }
                    }
                }.padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .refreshable { await content.refresh(client: account.client, force: true) }
                .task { await content.refresh(client: account.client); resolveRoute() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await content.refresh(client: account.client) } }
                }
                .onChange(of: routes.target) { _, _ in resolveRoute() }
                .navigationDestination(item: $target) { ClassroomDetailView(item: $0) }
                .fullScreenCover(item: $playingItem) { lesson in
                    NavigationStack { ClassroomVideoView(item: lesson, progressKey: progressKey(lesson)) }
                }
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
    private func playFirstLesson(of course: ClassroomItem) {
        if let lesson = content.playableLessons(for: course).first {
            playingItem = lesson
        } else {
            target = course
        }
    }
    private func progressKey(_ lesson: ClassroomItem) -> String? {
        account.session.map { LearningProgress.key(service: account.client.serviceID, user: $0.user.id, item: lesson.id) }
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
    var ratio: CGFloat = 1.6
    var body: some View {
        Rectangle().fill(SleepPalette.mint.opacity(0.15)).aspectRatio(ratio, contentMode: .fit)
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
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == "course" {
                        Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(SleepPalette.teal)
                            .frame(width: 30, height: 30).background(SleepPalette.surface, in: Circle()).padding(8)
                    }
                }
            Text(item.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Label(item.category, systemImage: item.kind == "course" ? "play.circle" : "book").font(.caption).foregroundStyle(SleepPalette.teal)
        }.padding(10).background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(SleepPalette.line.opacity(0.5)) }
    }
}
struct ProductTile: View {
    let item: ClassroomItem
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnyLayout(typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                Button { if let url = item.purchaseURL { openURL(url) } } label: {
                    ContentCover(name: item.cover, ratio: 1).frame(width: typeSize.isAccessibilitySize ? 180 : 108)
                }.buttonStyle(.plain).accessibilityLabel("查看京东商品：" + item.title)
                    .accessibilityIdentifier("productImage-" + item.id).disabled(item.purchaseURL == nil)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(item.summary).font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("前往京东查看商品详情并完成购买").font(.caption).foregroundStyle(SleepPalette.muted)
            HStack {
                Button { if let url = item.purchaseURL { openURL(url) } } label: { Label("前往京东购买", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(item.purchaseURL == nil)
                Spacer(minLength: 8)
                Button { UIPasteboard.general.url = item.purchaseURL } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }
                    .accessibilityLabel("复制商品链接").disabled(item.purchaseURL == nil)
            }
        }.padding(12).background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(SleepPalette.line) }
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
                    if item.kind == "product" {
                        Button { if let url = item.purchaseURL { openURL(url) } } label: { ContentCover(name: item.cover) }.buttonStyle(.plain)
                    } else { ContentCover(name: item.cover) }
                    Text(item.title).font(.title2.bold())
                    Text(item.summary).foregroundStyle(.secondary)
                    Text(item.body).font(.body).lineSpacing(7).textSelection(.enabled)
                    ForEach(content.children(item.id)) { chapter in
                        Button { lesson = chapter } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.title2)
                                VStack(alignment: .leading, spacing: 5) { Text(chapter.title).font(.headline); Text("完整播放").font(.caption) }
                                Spacer()
                                if let key = progressKey(chapter), let progress = LearningProgress.read(key), progress.duration > 0 { ProgressView(value: min(1, progress.seconds / progress.duration)).frame(width: 45) }
                            }.padding(.vertical, 12)
                        }.buttonStyle(.plain).foregroundStyle(SleepPalette.teal)
                    }
                    if item.kind == "product", let url = item.purchaseURL {
                        Button { external = url } label: { Label("前往京东购买", systemImage: "arrow.up.right.square") }.buttonStyle(.borderedProminent)
                        Button { UIPasteboard.general.url = url } label: { Label("复制链接", systemImage: "doc.on.doc") }
                    }
                    if item.kind == "noise", item.mediaURL != nil {
                        Button { lesson = item } label: { Label("播放已发布音频", systemImage: "play.circle") }.buttonStyle(.borderedProminent)
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(SleepPalette.background).navigationTitle(item.category).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .fullScreenCover(item: $lesson) { chapter in NavigationStack { ClassroomVideoView(item: chapter, progressKey: progressKey(chapter)) } }
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
    @State private var loadedDuration: Double = 0
    @State private var lastSavedSeconds: Double = -10
    @State private var active = true
    @State private var audioOwner = UUID()
    @State private var isLandscape = false
    @State private var selectedLesson: ClassroomItem?
    @State private var operation = UUID()
    private var currentLesson: ClassroomItem { selectedLesson ?? item }
    private var currentProgressKey: String? {
        if currentLesson.id == item.id { return progressKey }
        return account.session.map { LearningProgress.key(service: account.client.serviceID, user: $0.user.id, item: currentLesson.id) }
    }
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                ZStack { Color.black; playerSurface }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("classroomLandscapeSurface")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        playerSurface.aspectRatio(16 / 9, contentMode: .fit)
                        Text(currentLesson.title).font(.title3.bold())
                        if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                        let chapters = content.playableLessons(for: currentLesson)
                        if chapters.count > 1 {
                            Text("课程选集").font(.headline)
                            ForEach(chapters) { chapter in
                                Button {
                                    guard chapter.id != currentLesson.id else { return }
                                    stop(); selectedLesson = chapter
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: chapter.id == currentLesson.id ? "play.circle.fill" : "play.circle").font(.title2)
                                        Text(chapter.title).frame(maxWidth: .infinity, alignment: .leading)
                                        if chapter.id == currentLesson.id { Text("当前播放").font(.caption) }
                                    }.padding(.vertical, 12)
                                }.buttonStyle(.plain).foregroundStyle(SleepPalette.teal)
                                    .accessibilityIdentifier("playLesson-" + chapter.id)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.background(SleepPalette.background)
            }
        }.navigationTitle("课程播放").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { toggleOrientation() } label: {
                        Image(systemName: isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(isLandscape ? "退出横屏" : "横屏播放")
                    .help(isLandscape ? "退出横屏" : "横屏播放")
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task(id: currentLesson.id) { active = true; await load() }
            .onDisappear { active = false; stop(); CourseOrientation.restorePortrait() }
    }
    @ViewBuilder private var playerSurface: some View {
        if let player {
            VideoPlayer(player: player).accessibilityIdentifier("classroomVideoPlayer")
                .onReceive(player.publisher(for: \.status)) { status in
                    if status == .failed { message = "视频暂时无法播放，请检查网络或稍后重试。" }
                }
        } else {
            ContentCover(name: currentLesson.cover)
                .overlay { if message == nil { ProgressView().tint(SleepPalette.teal) } }
        }
    }
    private func load() async {
        let generation = operation
        let lesson = currentLesson
        message = nil; lastSavedSeconds = -10; loadedDuration = 0
        do {
            let fresh = try await content.freshItem(lesson.id, client: account.client)
            guard active, !Task.isCancelled, operation == generation else { return }
            guard let url = fresh.mediaURL else { message = "暂未提供可播放地址"; return }
            guard AudioCoordinator.shared.beginPlayback(owner: audioOwner) else { message = "手机正在监测，请结束监测后播放课程。"; return }
            let p = AVPlayer(url: url); player = p
            AudioCoordinator.shared.stopPlayback = { stop() }
            // Play the supplied full resource. Transport authentication stays with the media server.
            let measured = (try? await p.currentItem?.asset.load(.duration).seconds) ?? 0
            guard active, !Task.isCancelled, operation == generation else { return }
            loadedDuration = measured.isFinite && measured > 0 ? measured : fresh.duration ?? 0
            guard AudioCoordinator.shared.ownsPlayback(audioOwner) else { stop(); return }
            if let key = currentProgressKey, let saved = LearningProgress.read(key), saved.seconds < max(0, loadedDuration - 2) {
                await p.seek(to: CMTime(seconds: saved.seconds, preferredTimescale: 600))
            }
            guard active, !Task.isCancelled, operation == generation else { return }
            guard AudioCoordinator.shared.ownsPlayback(audioOwner) else { stop(); return }
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { time in
                Task { @MainActor in
                guard active, player === p else { return }
                let seconds = time.seconds
                if seconds.isFinite, abs(seconds - lastSavedSeconds) >= 5 { saveProgress(seconds) }
                }
            }
            if active, !Task.isCancelled, AudioCoordinator.shared.ownsPlayback(audioOwner) { p.play() } else { stop() }
        } catch {
            guard active, !Task.isCancelled, operation == generation else { return }
            message = "课程暂时无法加载，请联网刷新后重试。"
        }
    }
    private func stop() {
        operation = UUID()
        if let seconds = player?.currentTime().seconds, seconds.isFinite { saveProgress(seconds) }
        player?.pause(); if let observer { player?.removeTimeObserver(observer); self.observer = nil }
        player = nil; AudioCoordinator.shared.endPlayback(owner: audioOwner)
    }
    private func saveProgress(_ seconds: Double) {
        guard let key = currentProgressKey else { return }
        lastSavedSeconds = seconds
        LearningProgress.save(LessonProgress(seconds: seconds, duration: loadedDuration, updatedAt: .now), key: key)
    }
    private func toggleOrientation() {
        let target: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscape
        isLandscape.toggle()
        CourseOrientation.request(target) {
            isLandscape = false
            message = "暂时无法切换方向，请稍后再试。"
        }
    }
}

/// The app stays portrait outside the player; only an explicit player command enables landscape.
@MainActor enum CourseOrientation {
    static var supported: UIInterfaceOrientationMask = .portrait
    static func restorePortrait() { request(.portrait) {} }
    static func request(_ target: UIInterfaceOrientationMask, onFailure: @escaping () -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { onFailure(); return }
        supported = target
        var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
            supported = .portrait; onFailure()
        }
    }
}

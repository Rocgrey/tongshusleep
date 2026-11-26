import SwiftUI
import AVKit

struct SleepClassroomView: View {
    var isSelected = true
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var routes: AppRoutes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appearance = "fresh"
    @State private var selection = "课程"
    @State private var target: ClassroomItem?
    @State private var playingItem: ClassroomItem?
    @State private var routeMessage: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("睡眠科普").font(.title.bold())
                            Text("了解睡眠，也练习好好休息").font(.caption).foregroundStyle(SleepPalette.muted)
                        }
                        Spacer()
                        Button { Task { await content.refresh(client: account.client, force: true) } } label: {
                            Image(systemName: "arrow.clockwise").font(.title2).frame(width: 44, height: 44)
                        }.disabled(content.isLoading).accessibilityLabel("刷新课堂内容")
                            .accessibilityIdentifier("refreshClassroom")
                        NavigationLink { AppSettingsView() } label: { Image(systemName: "gearshape").font(.title2) }
                            .accessibilityLabel("设置").accessibilityIdentifier("enhancedSettings")
                    }
                    Picker("课堂栏目", selection: $selection) { ForEach(["课程", "阅读", "自测"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("classroomSections")
                    if let message = content.message { Label(message, systemImage: content.hasRemoteCatalog ? "wifi.exclamationmark" : "info.circle").font(.caption).foregroundStyle(.secondary) }
                    if !content.hasRemoteCatalog, content.message == nil { Text("随 App 提供的课堂内容").font(.caption).foregroundStyle(.secondary) }
                    if content.isLoading { ProgressView("正在更新课堂").font(.caption) }
                    else if content.hasRemoteCatalog, let date = content.refreshedAt {
                        Text("平台内容 · 更新于 \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("classroomUpdatedAt")
                    }
                    if content.canOpenBundledLibrary {
                        Button { content.openBundledLibrary() } label: { Label("查看随 App 课堂", systemImage: "books.vertical") }
                            .buttonStyle(GroveButtonStyle(.primary))
                    }
                    if selection == "课程" {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(content.courses) { item in
                                Button { playFirstLesson(of: item) } label: { ContentTile(item: item) }
                                    .buttonStyle(GrovePressStyle()).accessibilityIdentifier("classroomItem-" + item.id)
                                ForEach(content.children(item.id)) { lesson in
                                    Button { playingItem = lesson } label: { CourseLessonRow(item: lesson, fallbackCover: item.cover) }
                                        .buttonStyle(GrovePressStyle())
                                        .disabled(lesson.mediaURL == nil)
                                        .accessibilityIdentifier("classroomLesson-" + lesson.id)
                                }
                            }
                        }
                        if content.courses.isEmpty { empty("课程正在准备中") }
                    } else if selection == "阅读" {
                        ForEach(content.articles) { item in NavigationLink { ClassroomDetailView(item: item) } label: { ContentTile(item: item) }.buttonStyle(GrovePressStyle()) }
                        if content.articles.isEmpty { empty("暂无已发布文章") }
                    } else {
                        GroveSectionBanner(title: "给睡眠一个回顾", subtitle: "从自己的感受出发，找到改善方向", symbol: "list.clipboard.fill", color: .lavender)
                        NavigationLink { PSQIView() } label: {
                            GroveFeatureRow(title: "PSQI 睡眠自测", subtitle: "18 项 · 回顾近 1 个月 · 0–21 分", icon: "moon.stars.fill", tint: GroveColor.lavender.tint)
                        }.buttonStyle(GrovePressStyle()).accessibilityIdentifier("grovePSQI")
                        Text("自评帮助记录自己的感受，不能替代设备记录，也不会自动生成分期。").font(.subheadline).foregroundStyle(SleepPalette.muted)
                    }
                }.padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(SleepPalette.background).toolbar(.hidden, for: .navigationBar)
                .refreshable { await content.refresh(client: account.client, force: true) }
                .task(id: isSelected && scenePhase == .active) {
                    guard isSelected, scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await content.refresh(client: account.client)
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    }
                }
                .task(id: "\(isSelected)|\(routes.deliveryID)|\(routes.target ?? "")") { if isSelected { await resolveRoute() } }
                .alert("内容提醒", isPresented: Binding(get: { routeMessage != nil }, set: { if !$0 { routeMessage = nil } })) {
                    Button("知道了", role: .cancel) { routeMessage = nil }
                } message: { Text(routeMessage ?? "") }
                .navigationDestination(item: $target) { ClassroomDetailView(item: $0) }
                .fullScreenCover(item: $playingItem) { lesson in
                    NavigationStack { ClassroomVideoView(item: lesson, progressKey: progressKey(lesson)) }
                }
                .sheet(isPresented: Binding(get: { isSelected && ["breathing", "noise", "goodnight"].contains(routes.target ?? "") }, set: { if !$0 { routes.target = nil } })) {
                    NavigationStack {
                        Group { if routes.target == "breathing" { BreathingView() } else if routes.target == "noise" { WhiteNoiseView() } else { GoodnightView() } }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { routes.target = nil } } }
                    }
                }
        }
    }
    private func resolveRoute() async {
        if let route = routes.target, route.hasPrefix("content/") {
            do {
                // Notification cold launch may precede catalog loading.
                let item = try await content.freshItem(String(route.dropFirst(8)), client: account.client, forceRemote: true)
                guard !Task.isCancelled, routes.target == route else { return }
                target = item
                routes.target = nil
            } catch {
                guard !Task.isCancelled, routes.target == route else { return }
                if case APIError.business(404, _) = error { routeMessage = "这条内容已下架，可以浏览其他睡眠内容。" }
                else { routeMessage = "内容暂时无法打开，请稍后重试。" }
                routes.target = nil
            }
        } else if routes.target == "classroom" {
            routes.target = nil
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
            ContentCover(name: item.resolvedCover())
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == "course" {
                        Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(SleepPalette.teal)
                            .frame(width: 30, height: 30).background(SleepPalette.surface, in: Circle()).padding(8)
                    }
                }
            Text(item.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Label(item.category, systemImage: item.kind == "course" ? "play.circle" : "book").font(.caption).foregroundStyle(SleepPalette.teal)
        }.padding(10).groveSurface()
    }
}

/// Published chapters stay visible even when their media has not yet been supplied.
struct CourseLessonRow: View {
    let item: ClassroomItem
    var fallbackCover = "course-cover"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        AnyLayout(typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
            ContentCover(name: item.resolvedCover(seriesCover: fallbackCover), ratio: 16 / 9).frame(width: typeSize.isAccessibilitySize ? 180 : 112)
                .overlay { Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 3) }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(SleepPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.mediaURL == nil ? "视频正在准备" : item.duration.flatMap { $0.isFinite && $0 > 0 ? "约 \(($0 / 60).rounded(.up).formatted(.number.precision(.fractionLength(0)))) 分钟 · 点击播放" : nil } ?? "点击播放")
                    .font(.caption).foregroundStyle(SleepPalette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(SleepPalette.teal)
        }.padding(12).groveSurface()
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
                }.buttonStyle(GrovePressStyle()).accessibilityLabel("查看京东商品：" + item.title)
                    .accessibilityIdentifier("productImage-" + item.id).disabled(item.purchaseURL == nil)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(item.summary).font(.caption).foregroundStyle(SleepPalette.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("前往京东查看商品详情并完成购买").font(.caption).foregroundStyle(SleepPalette.muted)
            HStack {
                Button { if let url = item.purchaseURL { openURL(url) } } label: { Label("前往京东购买", systemImage: "arrow.up.right.square") }
                    .buttonStyle(GroveButtonStyle(.primary)).foregroundStyle(SleepPalette.onAccent).disabled(item.purchaseURL == nil)
                Spacer(minLength: 8)
                Button { UIPasteboard.general.url = item.purchaseURL } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }
                    .accessibilityLabel("复制商品链接").disabled(item.purchaseURL == nil)
            }
        }.padding(12).groveSurface()
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
                        Button { if let url = item.purchaseURL { openURL(url) } } label: { ContentCover(name: item.cover) }.buttonStyle(GrovePressStyle())
                    } else { ContentCover(name: item.resolvedCover(seriesCover: content.items.first(where: { $0.id == item.parent_id })?.cover)) }
                    Text(item.title).font(.title2.bold())
                    Text(item.summary).foregroundStyle(.secondary)
                    Text(item.body).font(.body).lineSpacing(7).textSelection(.enabled)
                    ForEach(content.children(item.id)) { chapter in
                        Button { lesson = chapter } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CourseLessonRow(item: chapter, fallbackCover: item.cover)
                                if let key = progressKey(chapter), let progress = LearningProgress.read(key), progress.duration > 0 { ProgressView(value: min(1, progress.seconds / progress.duration)).frame(width: 45) }
                            }
                        }.buttonStyle(GrovePressStyle()).disabled(chapter.mediaURL == nil)
                    }
                    if item.kind == "product", let url = item.purchaseURL {
                        Button { external = url } label: { Label("前往京东购买", systemImage: "arrow.up.right.square") }.buttonStyle(GroveButtonStyle(.primary))
                        Button { UIPasteboard.general.url = url } label: { Label("复制链接", systemImage: "doc.on.doc") }
                    }
                    if item.kind == "noise", item.mediaURL != nil {
                        Button { lesson = item } label: { Label("播放已发布音频", systemImage: "play.circle") }.buttonStyle(GroveButtonStyle(.primary))
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
                                        ContentCover(name: chapter.resolvedCover(seriesCover: content.items.first(where: { $0.id == chapter.parent_id })?.cover), ratio: 16 / 9)
                                            .frame(width: 88)
                                        Text(chapter.title).frame(maxWidth: .infinity, alignment: .leading)
                                        if chapter.id == currentLesson.id { Text("当前播放").font(.caption) }
                                    }.padding(.vertical, 12)
                                }.buttonStyle(GrovePressStyle()).foregroundStyle(SleepPalette.teal)
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
            ContentCover(name: currentLesson.resolvedCover(seriesCover: content.items.first(where: { $0.id == currentLesson.parent_id })?.cover))
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

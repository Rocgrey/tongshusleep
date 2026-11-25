import XCTest
import AVFoundation
@testable import sleeptongshu

private final class ContentTransport: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class EnhancedContentTests: XCTestCase {
    func testThemeActionColorsMeetTextContrastInLightAndDark() {
        func luminance(_ color: UIColor, _ traits: UITraitCollection) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for theme in AppAppearance.allCases {
                let foreground = luminance(UIColor(SleepPalette.onAccent), traits)
                let background = luminance(theme.readableAccent, traits)
                XCTAssertGreaterThanOrEqual((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05), 4.5, theme.rawValue)
            }
        }
    }

    func testGroveRoutesKeepMonitoringSummaryAndRelaxationDestinations() {
        XCTAssertEqual(SleepTab.destination(for: "monitoring"), .sleep)
        XCTAssertEqual(SleepTab.destination(for: "sleep-summary"), .sleep)
        for route in ["goodnight", "noise", "breathing"] { XCTAssertEqual(SleepTab.destination(for: route), .relax) }
        XCTAssertEqual(SleepTab.destination(for: "content/new-course"), .classroom)
    }

    func testSynthesizedNoiseLibraryIsDistinctFiniteAndBounded() {
        XCTAssertEqual(GroveNoise.library.count, 24)
        XCTAssertEqual(Set(GroveNoise.library.map(\.id)).count, 24)
        let signals = GroveNoise.library.map { $0.samples(rate: 1000, seconds: 2) }
        for signal in signals {
            XCTAssertEqual(signal.count, 2000)
            XCTAssertTrue(signal.allSatisfy { $0.isFinite && abs($0) <= 0.8 })
            XCTAssertGreaterThan(signal.map { abs($0) }.max() ?? 0, 0.01)
            XCTAssertEqual(signal.first, signal.last)
        }
        XCTAssertEqual(Set(signals.map { Array($0.prefix(20)) }).count, 24)
    }

    func testNotificationRoutesSupportSummaryColdLoginAndRepeatedContent() {
        let routes = AppRoutes()
        routes.receive("content/test-article")
        let first = routes.deliveryID
        XCTAssertEqual(routes.target, "content/test-article")
        routes.receive("content/test-article")
        XCTAssertNotEqual(routes.deliveryID, first)
        routes.open(URL(string: "sleeptongshu://sleep-summary")!)
        XCTAssertEqual(routes.target, "sleep-summary")
        XCTAssertTrue(AppRoutes.valid("goodnight"))
        routes.receive("https://untrusted.example.test")
        XCTAssertEqual(routes.target, "goodnight")
    }
    private var directory: URL!
    private var transport: URLSession!
    private var client: APIClient!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ContentTransport.self]
        transport = URLSession(configuration: config)
        client = APIClient(configuration: APIConfiguration(baseURL: "https://content.example.test/api/v1"), session: transport)
    }
    override func tearDown() async throws {
        transport.invalidateAndCancel(); ContentTransport.handler = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func item(_ id: String = "test-article") -> ClassroomItem {
        ClassroomItem(id: id, title: "Synthetic test article", summary: "Test only", body: "Test content", kind: "article", category: "Test", cover: "kepu-01", sort_order: 0, route: "content/"+id, featured: false, updated_at: 1)
    }
    private func page(_ items: [ClassroomItem], total: Int? = nil) throws -> Data {
        let data = try JSONEncoder().encode(items)
        return try JSONSerialization.data(withJSONObject: ["items": JSONSerialization.jsonObject(with: data), "total": total ?? items.count])
    }
    func testPublishedCatalogReplacesBundleCachesAndRemovesUnpublishedItems() async throws {
        let store = ContentStore(directory: directory)
        let bytes = try page([item()])
        ContentTransport.handler = { _ in (200, bytes) }
        await store.refresh(client: client)
        XCTAssertEqual(store.items.count, 1); XCTAssertTrue(store.hasRemoteCatalog)
        let cached = ContentStore(directory: directory)
        ContentTransport.handler = { _ in throw URLError(.notConnectedToInternet) }
        await cached.refresh(client: client)
        XCTAssertEqual(cached.items.first?.id, "test-article"); XCTAssertNotNil(cached.message)
        ContentTransport.handler = { _ in (200, Data(#"{"items":[],"total":0}"#.utf8)) }
        await cached.refresh(client: client, force: true)
        XCTAssertTrue(cached.items.isEmpty)
    }
    func testRefreshThrottlesAndPaginationKeepsExactItems() async throws {
        let store = ContentStore(directory: directory)
        var calls = 0
        ContentTransport.handler = { [self] request in
            calls += 1
            let pageNumber = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value
            return (200, try page([item(pageNumber == "1" ? "one" : "two")], total: 2))
        }
        await store.refresh(client: client); await store.refresh(client: client)
        XCTAssertEqual(calls, 2); XCTAssertEqual(store.items.map(\.id), ["one", "two"])
        await store.refresh(client: client, force: true); XCTAssertEqual(calls, 4)
    }
    func testServer404DoesNotRestoreBundledOrInventContent() async throws {
        let store = ContentStore(directory: directory)
        ContentTransport.handler = { [self] _ in (200, try page([item()])) }
        await store.refresh(client: client)
        ContentTransport.handler = { _ in (404, Data(#"{"detail":"内容已下架"}"#.utf8)) }
        do { _ = try await store.freshItem("test-article", client: client); XCTFail() } catch { }
        XCTAssertTrue(store.items.isEmpty)
    }
    func testUnconfiguredCatalogIsDifferentFromAnUnpublishedCatalog() async {
        let store = ContentStore(directory: directory)
        ContentTransport.handler = { _ in (200, Data(#"{"items":[],"total":0,"catalog_initialized":false}"#.utf8)) }
        await store.refresh(client: client)
        XCTAssertFalse(store.courses.isEmpty)
        XCTAssertFalse(store.hasRemoteCatalog)
        ContentTransport.handler = { _ in (200, Data(#"{"items":[],"total":0,"catalog_initialized":true}"#.utf8)) }
        await store.refresh(client: client, force: true)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.hasRemoteCatalog)
    }
    func testLegacyEmptyCatalogOffersExplicitLibraryButNeverRestoresKnownTakedowns() async throws {
        let store = ContentStore(directory: directory)
        ContentTransport.handler = { _ in (200, Data(#"{"items":[],"total":0}"#.utf8)) }
        await store.refresh(client: client)
        XCTAssertTrue(store.items.isEmpty); XCTAssertTrue(store.canOpenBundledLibrary)
        store.openBundledLibrary()
        XCTAssertFalse(store.courses.isEmpty); XCTAssertFalse(store.hasRemoteCatalog)
        ContentTransport.handler = { [self] _ in (200, try page([item()])) }
        await store.refresh(client: client, force: true)
        ContentTransport.handler = { _ in (200, Data(#"{"items":[],"total":0}"#.utf8)) }
        await store.refresh(client: client, force: true)
        XCTAssertFalse(store.canOpenBundledLibrary)
        store.openBundledLibrary(); XCTAssertTrue(store.items.isEmpty)
        let relaunched = ContentStore(directory: directory)
        await relaunched.refresh(client: client)
        XCTAssertFalse(relaunched.canOpenBundledLibrary)
    }
    func testBundledContentIsActualSourceAndMediaUsesBusinessDomain() async throws {
        let store = ContentStore(directory: directory)
        XCTAssertEqual(store.articles.count, 5)
        let first = try await store.freshItem("course-l1", client: client)
        XCTAssertEqual(first.mediaURL?.host, "vid.sleep.phoenixtreeai.com")
        XCTAssertNil(first.preview_seconds)
        for id in ["course-l2", "course-l3", "course-l4", "course-l5", "cbti-video", "sleep-harm-video"] {
            let chapter = try await store.freshItem(id, client: client)
            XCTAssertNil(chapter.preview_seconds)
            XCTAssertEqual(chapter.mediaURL?.host, "vid.sleep.phoenixtreeai.com")
        }
        let product = try await store.freshItem("jd-sleep-device", client: client)
        XCTAssertEqual(product.purchaseURL?.absoluteString, "https://3.cn/3bngE-ty")
        XCTAssertNotNil(UIImage(named: product.cover))
        XCTAssertNil(ClassroomItem.https("http://insecure.test"))
        XCTAssertNil(ClassroomItem.https("https://name:password@example.test/video"))
    }
    func testProductLinksOnlyOpenKnownJDHosts() {
        var product = item("test-product")
        product.external_url = "https://item.m.jd.com/product/10229068197495.html"
        XCTAssertNotNil(product.purchaseURL)
        for url in ["https://jd.com.attacker.test/item", "javascript:alert(1)", "https://user:password@jd.com", "http://jd.com"] {
            product.external_url = url; XCTAssertNil(product.purchaseURL)
        }
    }
    func testPublishedNewCourseChaptersAndProductsRefreshWithoutAppRelease() async throws {
        let store = ContentStore(directory: directory)
        var course = item("new-course"); course.kind = "course"
        var later = item("new-lesson-2"); later.kind = "chapter"; later.parent_id = course.id
        later.sort_order = 2; later.media_url = "https://vid.sleep.phoenixtreeai.com/video/synthetic-new-2.mp4"
        var first = item("new-lesson-1"); first.kind = "chapter"; first.parent_id = course.id
        first.sort_order = 1; first.media_url = "https://vid.sleep.phoenixtreeai.com/video/synthetic-new-1.mp4"
        var product = item("new-product"); product.kind = "product"
        product.external_url = "https://item.m.jd.com/product/123.html"
        ContentTransport.handler = { [self] _ in (200, try page([course, later, first, product])) }
        await store.refresh(client: client)
        XCTAssertEqual(store.courses.map(\.id), [course.id])
        XCTAssertEqual(store.playableLessons(for: course).map(\.id), [first.id, later.id])
        XCTAssertEqual(store.playableLessons(for: later).map(\.id), [first.id, later.id])
        XCTAssertEqual(store.items.first(where: { $0.kind == "product" })?.purchaseURL?.absoluteString, product.external_url)
        later.media_url = "https://vid.sleep.phoenixtreeai.com/video/synthetic-replacement.mp4"
        product.external_url = "https://item.m.jd.com/product/456.html"
        ContentTransport.handler = { [self] request in
            if request.url!.path.hasSuffix("/" + later.id) { return (200, try JSONEncoder().encode(later)) }
            return (200, try page([course, later, product]))
        }
        let updated = try await store.freshItem(later.id, client: client)
        XCTAssertEqual(updated.mediaURL?.absoluteString, later.media_url)
        await store.refresh(client: client, force: true)
        XCTAssertEqual(store.playableLessons(for: course).map(\.id), [later.id])
        XCTAssertEqual(store.items.first(where: { $0.kind == "product" })?.purchaseURL?.absoluteString, product.external_url)
    }
    func testStandaloneVideoStartsWithoutInventingMissingChapters() async throws {
        let store = ContentStore(directory: directory)
        var direct = item("standalone"); direct.kind = "course"
        direct.media_url = "https://vid.sleep.phoenixtreeai.com/video/synthetic-standalone.mp4"
        ContentTransport.handler = { [self] _ in (200, try page([direct])) }
        await store.refresh(client: client)
        XCTAssertEqual(store.playableLessons(for: direct).map(\.id), [direct.id])
        direct.media_url = nil
        XCTAssertTrue(store.playableLessons(for: direct).isEmpty)
    }
    func testLearningProgressIsScopedToServiceAndStableUserID() {
        let a = LearningProgress.key(service: "one", user: 1, item: "lesson")
        let b = LearningProgress.key(service: "one", user: 2, item: "lesson")
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, LearningProgress.key(service: "two", user: 1, item: "lesson"))
        defer { UserDefaults.standard.removeObject(forKey: a) }
        LearningProgress.save(LessonProgress(seconds: 13, duration: 100, updatedAt: .now), key: a)
        XCTAssertEqual(LearningProgress.read(a)?.seconds, 13); XCTAssertNil(LearningProgress.read(b))
    }
    func testSyncInventoryUsesAuthenticatedExistingEndpointAndReadsEveryPage() async throws {
        var pages: [Int] = []
        ContentTransport.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/health/device-records")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "start_date" }?.value, "2026-11-17")
            let page = Int(query.first { $0.name == "page" }!.value!)!; pages.append(page)
            let keys = page == 1 ? Array(0..<100) : [100]
            let items = keys.map { ["user_id": 7, "payload": ["record_key": "synthetic-\($0)", "kind": "steps", "revision_at": 1794355200]] as [String: Any] }
            return (200, try JSONSerialization.data(withJSONObject: ["total": 101, "items": items]))
        }
        let rows = try await AutomaticSyncAPI(client: client).inventory(start: "2026-11-17", end: "2026-11-18", userID: 7, token: "synthetic-token")
        XCTAssertEqual(rows.count, 101); XCTAssertEqual(pages, [1, 2])
    }
    func testSyncInventoryRejectsAnotherAccountAndPropagates401() async throws {
        ContentTransport.handler = { _ in
            (200, Data(#"{"total":1,"items":[{"user_id":8,"payload":{"record_key":"test","revision_at":1794355200,"kind":"steps"}}]}"#.utf8))
        }
        let api = AutomaticSyncAPI(client: client)
        do { _ = try await api.inventory(start: "2026-11-17", end: "2026-11-18", userID: 7, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        var expired: String?
        client.onUnauthorized = { token, _ in expired = token }
        ContentTransport.handler = { _ in (401, Data(#"{"detail":"Synthetic expired token"}"#.utf8)) }
        do { _ = try await api.inventory(start: "2026-11-17", end: "2026-11-18", userID: 7, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertTrue((error as? APIError)?.isUnauthorized == true) }
        XCTAssertEqual(expired, "synthetic-token")
    }
    func testNotificationRoutesAndBreathingTiming() {
        let routes = AppRoutes()
        routes.open(URL(string: "sleeptongshu://content/article-1")!)
        XCTAssertEqual(routes.target, "content/article-1")
        routes.open(URL(string: "sleeptongshu://not-allowed")!)
        XCTAssertEqual(routes.target, "goodnight")
        XCTAssertFalse(AppRoutes.valid("content/../../private"))
        XCTAssertEqual(BreathingCycle.phase(elapsed: 0).title, "吸气")
        XCTAssertEqual(BreathingCycle.phase(elapsed: 4).remaining, 7)
        XCTAssertEqual(BreathingCycle.phase(elapsed: 11).title, "呼气")
        XCTAssertEqual(BreathingCycle.phase(elapsed: 19).remaining, 4)
    }
    func testSpeechSegmentsAreLocalPlayableAndNonSpeechIsDiscarded() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        buffer.frameLength = 16000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 16000)
        let start = Date.now
        let writer = try NightVoiceWriter(directory: directory)
        writer.accept(buffer, start: start); writer.speech(start: start, end: start.addingTimeInterval(1), confidence: 0.9); writer.finish()
        let clips = NightAudioStorage.clips(at: directory)
        XCTAssertEqual(clips.count, 1); XCTAssertEqual(clips.first?.duration, 1)
        let player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(clips[0].file))
        XCTAssertGreaterThan(player.duration, 0.9)
        let silent = try NightVoiceWriter(directory: directory); silent.accept(buffer, start: start); silent.finish()
        XCTAssertEqual(NightAudioStorage.clips(at: directory).count, 1)
        try NightAudioStorage.clean(now: start.addingTimeInterval(8 * 86400), at: directory)
        XCTAssertTrue(NightAudioStorage.clips(at: directory).isEmpty)
    }
    func testAudioDeletionRejectsPathTraversal() throws {
        let clip = NightVoiceClip(id: UUID(), start: .now, duration: 1, confidence: 0.9, file: "../other.caf")
        XCTAssertThrowsError(try NightAudioStorage.delete(clip, at: directory))
    }
    func testAudioTimerFadesToZeroWithoutExtendingDeadline() {
        XCTAssertEqual(AudioCountdown.gain(remaining: 1800), 1)
        XCTAssertEqual(AudioCountdown.gain(remaining: 5), 0.5)
        XCTAssertEqual(AudioCountdown.gain(remaining: 0), 0)
        XCTAssertEqual(AudioCountdown.gain(remaining: -10), 0)
    }
    func testPlaybackCannotInterruptRecording() {
        let coordinator = AudioCoordinator()
        let owner = UUID()
        coordinator.beginRecording()
        XCTAssertFalse(coordinator.beginPlayback(owner: owner))
        XCTAssertFalse(coordinator.ownsPlayback(owner))
        coordinator.endPlayback(owner: owner)
        XCTAssertTrue(coordinator.recording)
        coordinator.endRecording()
    }
}

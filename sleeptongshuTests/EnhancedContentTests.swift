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
    func testLearningProgressIsScopedToServiceAndStableUserID() {
        let a = LearningProgress.key(service: "one", user: 1, item: "lesson")
        let b = LearningProgress.key(service: "one", user: 2, item: "lesson")
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, LearningProgress.key(service: "two", user: 1, item: "lesson"))
        defer { UserDefaults.standard.removeObject(forKey: a) }
        LearningProgress.save(LessonProgress(seconds: 13, duration: 100, updatedAt: .now), key: a)
        XCTAssertEqual(LearningProgress.read(a)?.seconds, 13); XCTAssertNil(LearningProgress.read(b))
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

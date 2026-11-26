import XCTest
@testable import sleeptongshu

private final class TemperatureTransport: URLProtocol {
    static var supportsTemperature = false
    static var posted = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let text: String
        if path == "sync-capabilities" {
            text = Self.supportsTemperature
                ? #"{"device_sync_version":1,"idempotent":true,"supported_vital_kinds":["temperature"]}"#
                : #"{"device_sync_version":1,"idempotent":true}"#
        } else {
            Self.posted = true
            text = #"{"id":1,"user_id":1,"applied":true}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class TemperatureSyncTests: XCTestCase {
    func testOldServerKeepsFullTemperatureSnapshotPendingAndNewServerAcceptsIt() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TemperatureTransport.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let api = AutomaticSyncAPI(client: APIClient(configuration: APIConfiguration(baseURL: "https://synthetic.example/api/v1"), session: session))
        let sample = WearableVital(device: "synthetic", deviceLabel: "测试手环", date: StepDates.date("2026-11-11")!, kind: .temperature, value: 36.5, origin: "测试")
        let request = try XCTUnwrap(DeviceSyncRequest.vitalDays([sample]).first)
        TemperatureTransport.supportsTemperature = false; TemperatureTransport.posted = false
        do { _ = try await api.upload(request, token: "synthetic-token"); XCTFail("Old server must not confirm incomplete upload") }
        catch let error as APIError { if case .business(422, _) = error {} else { XCTFail("\(error)") } }
        XCTAssertFalse(TemperatureTransport.posted)
        TemperatureTransport.supportsTemperature = true
        let receipt = try await api.upload(request, token: "synthetic-token")
        XCTAssertTrue(receipt.applied); XCTAssertTrue(TemperatureTransport.posted)
    }
    func testTemperaturePersistsAlongsideExistingMetricsAndDeduplicates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let date = StepDates.date("2026-11-11")!
        let temperature = WearableVital(device: "synthetic", deviceLabel: "测试", date: date, kind: .temperature, value: 36.5, origin: "测试")
        let heart = WearableVital(device: "synthetic", deviceLabel: "测试", date: date, kind: .heart, value: 65, origin: "测试")
        let store = WearableVitalsStore(url: url)
        XCTAssertEqual(try store.merge([heart, temperature]), 2)
        XCTAssertEqual(try store.merge([temperature]), 0)
        XCTAssertEqual(Set(WearableVitalsStore(url: url).visibleSamples.map(\.kind)), [.heart, .temperature])
        XCTAssertFalse(VitalKind.temperature.accepts(.nan)); XCTAssertFalse(VitalKind.temperature.accepts(.infinity))
        XCTAssertNil(VitalKind.temperature.chartReference)
    }
}

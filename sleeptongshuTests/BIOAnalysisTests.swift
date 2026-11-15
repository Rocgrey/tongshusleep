import XCTest
import SwiftData
import SwiftProtobuf
@testable import sleeptongshu

private final class BIOAnalysisTransport: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class BIOAnalysisSessionStorage: AccountSessionStorage {
    func load() throws -> SavedAccountSession? { nil }
    func save(_ value: SavedAccountSession) throws {}
    func clear() throws {}
}

@MainActor final class BIOAnalysisTests: XCTestCase {
    private var directory: URL!
    private var transport: URLSession!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BIOAnalysisTransport.self]
        transport = URLSession(configuration: config)
    }
    override func tearDown() async throws {
        transport.invalidateAndCancel(); BIOAnalysisTransport.handler = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func date(_ day: String, hour: Int) -> Date {
        StepDates.date(day)!.addingTimeInterval(Double(hour) * 3600)
    }
    private func report(day: String, previous: String, seq: UInt32 = 0) throws -> WearableProbeReport {
        var report = WearableProbeReport(deviceName: "BIO synthetic", deviceKey: "test-bio")
        report.observedModel = "BIO9"; report.observedFirmware = "103.0.0.11"
        report.algorithmDeviceID = "AABBCCDDEEFF"
        report.startedAt = date(day, hour: 9); report.finishedAt = date(day, hour: 10)
        for (index, time) in [date(previous, hour: 23), date(day, hour: 7)].enumerated() {
            var record = IW_HisData(); record.seq = seq + UInt32(index)
            record.health.timeStamp.dateTime.seconds = UInt32(time.timeIntervalSince1970 + 28800)
            record.health.timeStamp.timeZone = 80; record.health.sleepData.sleepData = [1,2,3,4,5]
            record.health.sleepData.shutDown = false; record.health.sleepData.charge = false
            record.health.hrData.avgBpm = 65; record.health.hrData.minBpm = 60; record.health.hrData.maxBpm = 70
            record.health.bxoyData.agvOxy = 98; record.health.bxoyData.minOxy = 97; record.health.bxoyData.maxOxy = 99
            report.records.append(try WearableProbeProtocol.record(record, type: 0))
        }
        return report
    }
    private func save(_ report: WearableProbeReport, suffix: String) throws {
        try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("probe-\(suffix).json"))
    }
    private func container() throws -> ModelContainer {
        try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func account(_ result: @escaping (URLRequest) -> (Int, Data)) async -> AccountStore {
        let client = APIClient(configuration: APIConfiguration(baseURL: "https://bio.example.test/api/v1"), session: transport)
        BIOAnalysisTransport.handler = { request in
            if request.url!.path.hasSuffix("/login") {
                return (200, Data(#"{"access_token":"test-bio-token","token_type":"bearer","expire_at":4070908800}"#.utf8))
            }
            if request.url!.path.hasSuffix("/me") {
                return (200, Data(#"{"id":1,"username":"synthetic","phone":"13800001234","created_at":"2026-11-01T00:00:00Z"}"#.utf8))
            }
            return result(request)
        }
        let account = AccountStore(api: AccountAPI(client: client), storage: BIOAnalysisSessionStorage())
        await account.login(identifier: "13800001234", password: "test-pass", remember: false)
        return account
    }
    func testEmptyLatestReadReusesBothHistoricalNightsWithoutDuplicatingOrMixingDevices() async throws {
        let old = try report(day: "2026-11-05", previous: "2026-11-04")
        let next = try report(day: "2026-11-11", previous: "2026-11-10", seq: 2)
        var current = next; current.startedAt = date("2026-11-12", hour: 9)
        current.finishedAt = date("2026-11-12", hour: 10); current.records = []
        try save(old, suffix: "1"); try save(old, suffix: "2"); try save(next, suffix: "3")
        var other = old; other.deviceKey = "other"; try save(other, suffix: "4")
        var wrongAddress = old; wrongAddress.algorithmDeviceID = "112233445566"; try save(wrongAddress, suffix: "5")
        let worker = WearableProbeWorker()
        let prepared = try await worker.prepareSleep(current, owner: "server|1", base: directory)
        XCTAssertEqual(prepared.report.records.count, 4)
        XCTAssertEqual(prepared.requests.map(\.recordDate), [20261105,20261111])
        XCTAssertEqual(prepared.observations.map { $0.metadata?.bioNight?.endDay }, ["2026-11-05", "2026-11-11"])
        XCTAssertTrue(prepared.observations.allSatisfy { $0.segments.isEmpty })
        do {
            _ = try await worker.prepareSleep(current, owner: "server|2", base: directory)
            XCTFail("Other account must not analyze this capture")
        } catch let error as APIError { XCTAssertTrue(error.localizedDescription.contains("其他账号")) }
    }
    func testAnotherAccountsArchiveCannotCompleteMissingDays() async throws {
        let old = try report(day: "2026-11-11", previous: "2026-11-10")
        try save(old, suffix: "1")
        _ = try RawSensorPendingStorage.claim(capture: RawSensorBatchRequest.captureID(old), scope: "server|other", base: directory)
        var current = old; current.startedAt = date("2026-11-12", hour: 9)
        current.finishedAt = date("2026-11-12", hour: 10); current.records = []
        let prepared = try await WearableProbeWorker().prepareSleep(current, owner: "server|1", base: directory)
        XCTAssertTrue(prepared.requests.isEmpty); XCTAssertTrue(prepared.observations.isEmpty)
    }
    func testValidResponseUpdatesExistingSleepRecordWithFourStagesAndStopsRepeatingFinalInput() async throws {
        let report = try report(day: "2026-11-11", previous: "2026-11-10")
        var calls = 0
        let account = await account { request in
            XCTAssertEqual(request.url!.path, "/api/v1/health/bio-sleep-analysis")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-bio-token")
            calls += 1
            return (200, Data(#"{"return_code":0,"message":"synthetic fixture","result":{"completed":1,"start_time":"2026-11-10 23:00","end_time":"2026-11-11 07:01","sections":[{"start":"2026-11-10 23:00","end":"2026-11-11 01:00","type":3},{"start":"2026-11-11 01:00","end":"2026-11-11 03:00","type":4},{"start":"2026-11-11 03:00","end":"2026-11-11 03:10","type":6},{"start":"2026-11-11 03:10","end":"2026-11-11 07:01","type":7}]}}"#.utf8))
        }
        XCTAssertNotNil(account.session)
        let db = try container(), context = db.mainContext
        let store = BIOAlgorithmStore(worker: WearableProbeWorker(), directory: directory)
        await store.analyze(report, account: account, context: context)
        let records = try context.fetch(FetchDescriptor<SleepRecord>())
        let saved = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1); XCTAssertEqual(saved.minutes(.deep), 120)
        XCTAssertEqual(saved.minutes(.light), 120); XCTAssertEqual(saved.minutes(.rem), 231)
        XCTAssertEqual(saved.awakenings, 1); XCTAssertEqual(saved.averageSpO2, 98)
        XCTAssertNil(saved.score)
        await store.analyze(report, account: account, context: context)
        XCTAssertEqual(calls, 1)
        let diagnostic = try JSONDecoder().decode(BIOAnalysisDiagnostic.self, from: Data(contentsOf: directory.appendingPathComponent("bio-sleep-status.json")))
        XCTAssertEqual(diagnostic.stageCount, 4); XCTAssertEqual(diagnostic.returnCode, 0)
    }
    func testUnconfiguredServiceAndUnboundDeviceKeepObservationWithoutInventingStages() async throws {
        for status in [503, 200] {
            let report = try report(day: "2026-11-11", previous: "2026-11-10")
            var calls = 0
            let account = await account { _ in
                calls += 1
                return status == 503 ? (503, Data(#"{"detail":"厂家睡眠算法尚未在平台配置"}"#.utf8)) :
                    (200, Data(#"{"return_code":10403,"message":"设备尚未开通算法服务","result":null}"#.utf8))
            }
            let db = try container(), context = db.mainContext
            let store = BIOAlgorithmStore(worker: WearableProbeWorker(), directory: directory)
            await store.analyze(report, account: account, context: context)
            await store.analyze(report, account: account, context: context)
            XCTAssertEqual(calls, 1)
            let saved = try XCTUnwrap(context.fetch(FetchDescriptor<SleepRecord>()).first)
            XCTAssertFalse(saved.hasSleepDuration); XCTAssertTrue(saved.segments.isEmpty)
            XCTAssertNil(saved.awakenings); XCTAssertNil(saved.averageSpO2)
            XCTAssertTrue(store.status(for: try XCTUnwrap(saved.metadata?.bioNight))?.contains(status == 503 ? "尚未在平台配置" : "尚未开通") == true)
            store.reset(); XCTAssertTrue(store.statusByNight.isEmpty)
        }
    }

    func testPrivatePhoneArchivePreparesNovemberFifthAndEleventhWithoutUploading() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("work/bio-sleep-review-20261115")
        let oldURL = root.appendingPathComponent("probe-1794397222951-4c59a8fc.json")
        guard FileManager.default.fileExists(atPath: oldURL.path) else { throw XCTSkip("Optional private phone archive not available") }
        let old = try JSONDecoder().decode(WearableProbeReport.self, from: Data(contentsOf: oldURL))
        var empty = old; empty.records = []; empty.startedAt = empty.startedAt.addingTimeInterval(86400)
        empty.finishedAt = empty.finishedAt!.addingTimeInterval(86400)
        try save(old, suffix: "1")
        let prepared = try await WearableProbeWorker().prepareSleep(empty, owner: "private-local-replay|1", base: directory)
        XCTAssertTrue(prepared.requests.contains { $0.recordDate == 20261105 })
        XCTAssertTrue(prepared.requests.contains { $0.recordDate == 20261111 })
        XCTAssertEqual(prepared.report.records.count, 3004) // 2870 health + 134 RRI; ECG is not sleep input.
        XCTAssertTrue(prepared.observations.allSatisfy { $0.segments.isEmpty })
        print("Private local replay: \(prepared.report.records.count) input records; November 5 and 11 ready; no vendor request made")
    }

    func testLocalCalculationReusesChartsPersistsOriginAndNeverCallsCloudAnalysis() async throws {
        let report = try report(day: "2026-11-11", previous: "2026-11-10")
        let account = await account { _ in XCTFail("Local calculation must not call the analysis service"); return (503, Data()) }
        let db = try container(), context = db.mainContext
        var calls = 0
        let store = BIOAlgorithmStore(worker: WearableProbeWorker(), directory: directory, localCalculation: { request in
            calls += 1
            XCTAssertEqual(request.recordDate, 20261111)
            return BIOSleepAlgorithmResult(completed: 0, start_time: "2026-11-10 23:00", end_time: "2026-11-11 07:01", sections: [
                .init(start: "2026-11-10 23:00", end: "2026-11-11 01:00", type: 3),
                .init(start: "2026-11-11 01:00", end: "2026-11-11 03:00", type: 4),
                .init(start: "2026-11-11 03:00", end: "2026-11-11 03:10", type: 6),
                .init(start: "2026-11-11 03:10", end: "2026-11-11 07:01", type: 7)])
        })
        await store.analyze(report, account: account, context: context)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<SleepRecord>()).first)
        XCTAssertEqual(saved.metadata?.bioNight?.algorithm, BIOLocalSleep.version)
        XCTAssertEqual(saved.minutes(.deep), 120); XCTAssertEqual(saved.minutes(.rem), 231)
        XCTAssertEqual(saved.averageSpO2, 98); XCTAssertEqual(saved.awakenings, 1)
        let sync = try DeviceSyncRequest.sleep(saved)
        XCTAssertEqual(sync.kind, "sleep"); XCTAssertEqual(sync.sleep?.deep_sleep_minutes, 120)
        XCTAssertEqual(sync.sleep?.rem_minutes, 231); XCTAssertEqual(sync.details.average_spo2, 98)
        XCTAssertEqual(sync.details.stages.count, 4); XCTAssertEqual(sync.record_date, "2026-11-11")
        saved.note = "保留笔记"; try context.save()
        await store.analyze(report, account: account, context: context)
        XCTAssertEqual(calls, 1)
        try BIONight.save(BIONight.payloads(report: report, history: WearableHistoryDecoder.decode(report)), in: context)
        XCTAssertEqual(saved.metadata?.bioNight?.algorithm, BIOLocalSleep.version)
        XCTAssertEqual(saved.note, "保留笔记"); XCTAssertEqual(saved.minutes(.rem), 231)
        let status = try JSONDecoder().decode(BIOAnalysisDiagnostic.self, from: Data(contentsOf: directory.appendingPathComponent("bio-sleep-status.json")))
        XCTAssertEqual(status.engine, BIOLocalSleep.version); XCTAssertNil(status.httpStatus)
    }

    func testLocalFailureForOneDateDoesNotBlockLaterDatesOrGenerateStages() async throws {
        var report = try report(day: "2026-11-11", previous: "2026-11-10")
        report.records += try self.report(day: "2026-11-05", previous: "2026-11-04").records
        let account = await account { _ in XCTFail("No network needed"); return (503, Data()) }
        let db = try container()
        var dates: [Int] = []
        let store = BIOAlgorithmStore(worker: WearableProbeWorker(), directory: directory, localCalculation: { request in
            dates.append(request.recordDate)
            if request.recordDate == 20261105 { throw SleepDataError.invalidRecord }
            return BIOSleepAlgorithmResult(completed: 0, start_time: "", end_time: "", sections: [])
        })
        await store.analyze(report, account: account, context: db.mainContext)
        await store.analyze(report, account: account, context: db.mainContext)
        XCTAssertEqual(dates, [20261105,20261111])
        XCTAssertTrue(try db.mainContext.fetch(FetchDescriptor<SleepRecord>()).allSatisfy { !$0.hasSleepDuration && $0.segments.isEmpty })
    }

    func testLocalRRIKeepsDayOrderAndSignedControlsWithoutFillingGaps() {
        let input = BIOSleepAlgorithmRequest(recordDate: 20261111, device_id: "", prevDay: "[]", nextDay: "[]",
            prevDayRri: [-3,2300,-1,-1,800], nextDayRri: [-3,5,900,-2])
        XCTAssertEqual(BIOLocalSleep.rri(input).map(\.intValue), [-3,2300,-1,800,-1000,-3,5,900,-2])
    }
}

import XCTest
@testable import sleeptongshu

@MainActor
final class SleepUploadTests: XCTestCase {
    func testRequestHasOnlyContractFieldsAndNeverInventsMissingStagesOrQuestionnaireScores() throws {
        let start = Date(timeIntervalSince1970: 1_793_878_200)
        let record = SleepRecord(SleepPayload(id: UUID(), start: start, end: start.addingTimeInterval(3600), source: .manual,
                                               segments: [], heartSamples: [], note: "测试笔记"))
        let request = try SleepUploadRequest(record: record, timeZone: TimeZone(secondsFromGMT: 0)!)
        let json = try JSONSerialization.jsonObject(with: request.encoded()) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["record_date", "sleep_start_time", "sleep_end_time", "total_duration_minutes", "notes"])
        XCTAssertEqual(json["total_duration_minutes"] as? Int, 60)
        XCTAssertEqual(request.sleep_start_time.count, 19)
        XCTAssertNil(request.isi_score)
        XCTAssertNil(request.rem_minutes)
        let result = try SleepUploadRequest(record: record, isi: 6, ais: 4)
        XCTAssertEqual(result.isi_score, 6)
        XCTAssertEqual(result.ais_score, 4)
        XCTAssertThrowsError(try SleepUploadRequest(record: record, isi: 29))
        record.sourceRawValue = SleepDataSource.sample.rawValue
        XCTAssertThrowsError(try SleepUploadRequest(record: record))
    }
    func testReceiptIsScopedByServerUserAndLocalRecord() {
        let suite = "upload-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipts = SleepUploadReceipts(defaults: defaults)
        let id = UUID()
        receipts.save(service: "server1", userID: 1, recordID: id, remoteID: 123)
        XCTAssertTrue(receipts.contains(service: "server1", userID: 1, recordID: id))
        XCTAssertFalse(receipts.contains(service: "server1", userID: 2, recordID: id))
        XCTAssertFalse(receipts.contains(service: "server2", userID: 1, recordID: id))
    }
}

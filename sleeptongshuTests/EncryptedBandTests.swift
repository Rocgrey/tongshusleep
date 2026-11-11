import XCTest
import SwiftData
@testable import sleeptongshu

/// Synthetic protocol/interval inputs; these tests do not claim hardware compatibility.
final class EncryptedBandTests: XCTestCase {
    private let device = UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!
    private let start = Date(timeIntervalSince1970: 1_793_635_200)
    private var file: STBandActivityFileID {
        STBandActivityFileID(timestamp: UInt32(start.timeIntervalSince1970), tzQuarterHours: 32,
                             version: 6, type: 0, subtype: 8, detailType: 0)
    }
    private func point(_ minute: Int, _ stage: STBandSleepStage, duration: Int? = 10) -> STBandSleepStageSample {
        STBandSleepStageSample(ts: start.addingTimeInterval(Double(minute) * 60), stage: stage, raw: 0, durationMinutes: duration)
    }
    private func payload(_ points: [STBandSleepStageSample], minutes: Int = 60, deviceID: UUID? = nil) throws -> SleepPayload? {
        let session = STBandSleepSession(bedTime: start, wakeTime: start.addingTimeInterval(Double(minutes) * 60),
                                        deepMinutes: nil, lightMinutes: nil, remMinutes: nil, awakeMinutes: nil, stages: points)
        return try EncryptedBandSleepAdapter.payload(session: session, file: file, device: deviceID ?? device, name: "测试设备")
    }
    func testCredentialValidationRejectsPasswordsUnicodeAndWrongLengths() throws {
        XCTAssertEqual(try EncryptedBandCredentialStore.parse("00112233445566778899aAbBcCdDeEfF").count, 16)
        for bad in ["", "password", String(repeating: "z", count: 32), String(repeating: "Ａ", count: 32), String(repeating: "0", count: 31)] {
            XCTAssertThrowsError(try EncryptedBandCredentialStore.parse(bad))
        }
    }
    func testBindingCacheParserReadsRealFieldsWithoutInventingKeys() throws {
        let raw = Data(#"{"devices":[{"name":"test device","encryptKey":"00112233445566778899aabbccddeeff"},{"encryptKey":"bad"}]}"#.utf8)
        let keys = STBandKeyLoader.parseRegisterList(raw)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?.name, "test device")
        XCTAssertEqual(keys.first?.data.count, 16)
        XCTAssertTrue(STBandKeyLoader.parseRegisterList(Data("invalid".utf8)).isEmpty)
    }
    func testFrameReassemblyCRCAndGarbage() {
        let payload = Data([1, 2, 3, 4, 5])
        let frame = STBandMiFrame.encode(kind: 3, seq: 255, payload: payload)
        var buffer = [UInt8]([0x11, 0x22]) + Array(frame.prefix(9))
        XCTAssertTrue(STBandMiFrame.drain(&buffer).isEmpty)
        buffer.append(contentsOf: frame.dropFirst(9))
        let parsed = STBandMiFrame.drain(&buffer)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.payload, payload)
        XCTAssertEqual(parsed.first?.seq, 255)
        var bad = Array(frame); bad[bad.count - 1] ^= 1
        XCTAssertTrue(STBandMiFrame.drain(&bad).isEmpty)
    }
    func testAuthenticationRejectsWrongKeyAndMalformedNonce() {
        let key = Data(repeating: 1, count: 16), phone = Data(repeating: 2, count: 16), watch = Data(repeating: 3, count: 16)
        let material = STBandMiCrypto.sessionKeyMaterial(authKey: key, phoneNonce: phone, watchNonce: watch)
        let hmac = STBandMiCrypto.hmacSHA256(key: material.prefix(16), watch + phone)
        XCTAssertNotNil(STBandMiAuth.confirmCommand(authKey: key, phoneNonce: phone, watchNonce: watch, watchHmac: hmac, deviceName: "test"))
        XCTAssertNil(STBandMiAuth.confirmCommand(authKey: Data(repeating: 9, count: 16), phoneNonce: phone, watchNonce: watch, watchHmac: hmac, deviceName: "test"))
        XCTAssertNil(STBandMiAuth.confirmCommand(authKey: key, phoneNonce: phone, watchNonce: Data(), watchHmac: hmac, deviceName: "test"))
    }
    func testCCMDetectsTamperingAndCTREncryptsSymmetrically() {
        let key = Data(repeating: 1, count: 16), nonce = Data(repeating: 2, count: 12), text = Data("test payload".utf8)
        let encrypted = STBandMiCrypto.ccmEncrypt(key: key, nonce: nonce, plaintext: text)
        XCTAssertEqual(STBandMiCrypto.ccmDecrypt(key: key, nonce: nonce, ciphertextAndTag: encrypted), text)
        var altered = encrypted; altered[0] ^= 1
        XCTAssertNil(STBandMiCrypto.ccmDecrypt(key: key, nonce: nonce, ciphertextAndTag: altered))
        XCTAssertEqual(STBandMiCrypto.ctr(key: key, STBandMiCrypto.ctr(key: key, text)), text)
    }
    func testCTRMatchesIndependentOpenSSLVector() {
        let key = Data(0..<16), text = Data("sleeptongshu protocol fixture".utf8)
        let hex = STBandMiCrypto.ctr(key: key, text).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "79f86ed0311a9f2b96b0fc2de6239835760c8ffb0a3814ffe2ae887d2e")
    }
    func testSyntheticV6SleepFileParsesAllStagesAndRejectsCRCMutation() throws {
        func little(_ number: UInt64, _ count: Int) -> [UInt8] {
            (0..<count).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) }
        }
        let timestamp = UInt64(start.timeIntervalSince1970)
        // No optional sample blocks. Four explicit fifteen-minute type-17 stages.
        var body: [UInt8] = [0, 0, 0, 0]
        body += little(timestamp, 4) + little(timestamp + 3600, 4)
        body += Array(repeating: 0, count: 9) + little(timestamp, 4) + little(timestamp + 3600, 4)
        body += Array(repeating: 0, count: 24)
        body += [0xFB, 0xFA, 0xFC, 0xFF, 17] + little(timestamp, 8) + [0, 17, 0, 8]
        body += [0x10, 15, 0x20, 15, 0x30, 15, 0x00, 15]
        var bytes = file.data + Data([0]) + Data(body)
        bytes += Data(little(UInt64(STBandActivityCRC32.checksum(bytes)), 4))
        let result = STBandActivityParser.parse(bytes)
        XCTAssertTrue(result.crc?.ok == true)
        guard case .sleepDetails(let parsed) = result.payload else { return XCTFail("Synthetic v6 sleep did not parse: \(result)") }
        let session = try XCTUnwrap(parsed.session)
        let payload = try XCTUnwrap(EncryptedBandSleepAdapter.payload(session: session, file: file, device: device, name: "测试设备"))
        let record = SleepRecord(payload)
        XCTAssertEqual(record.minutes(.light), 15)
        XCTAssertEqual(record.minutes(.deep), 15)
        XCTAssertEqual(record.minutes(.rem), 15)
        XCTAssertEqual(record.minutes(.awake), 15)
        XCTAssertEqual(record.asleepMinutes, 45)
        bytes[bytes.count - 5] ^= 1
        XCTAssertNotNil(STBandActivityParser.parse(bytes).error)
    }
    func testCRC32KnownVectorAndCorruptFile() {
        XCTAssertEqual(STBandActivityCRC32.checksum(Data("123456789".utf8)), 0xcbf43926)
        let data = Data(repeating: 0, count: 30)
        XCTAssertNotNil(STBandActivityParser.parse(data).error)
    }
    func testFileAssemblerRejectsMissingChunksAndEnforcesSizeLimit() {
        var assembler = STBandActivityAssembler(maxFileSize: 12)
        if case .failure = assembler.feed(Data([2, 0, 2, 0, 1])) {} else { XCTFail("Out-of-order chunk accepted") }
        if case .failure = assembler.feed(Data([1, 0, 1, 0]) + Data(repeating: 0, count: 13)) {} else { XCTFail("Oversized file accepted") }
    }
    func testMissingLiveStepsDifferFromTrueZero() throws {
        func command(_ value: UInt64?) -> STBandPBMessage {
            var stats = STBandPBWriter(); if let value { stats.varint(1, value) }
            var health = STBandPBWriter(); health.message(39, stats)
            var message = STBandPBWriter(); message.message(10, health)
            return STBandPBMessage(message.data)!
        }
        XCTAssertNil(STBandMiAuth.liveStats(command(nil))?.steps)
        XCTAssertEqual(STBandMiAuth.liveStats(command(0))?.steps, 0)
    }
    func testUnknownStagesAndGapsNeverBecomeSleep() throws {
        let record = try SleepRecord(XCTUnwrap(payload([point(10, .light), point(30, .unknown), point(40, .deep)])))
        XCTAssertEqual(record.asleepMinutes, 20)
        XCTAssertEqual(record.minutes(.unobserved), 40)
        XCTAssertNil(record.efficiency)
        XCTAssertNil(record.averageHeartRate)
        XCTAssertNil(record.averageSpO2)
        XCTAssertNil(record.awakeMinutes)
        XCTAssertNil(record.awakenings)
        XCTAssertNil(record.score)
    }
    func testSummaryWithoutStagesDoesNotGenerateSleep() throws {
        XCTAssertNil(try payload([]))
        XCTAssertNil(try payload([point(0, .unknown)]))
    }
    func testOverlappingAndOutOfRangeStagesAreRejected() {
        XCTAssertThrowsError(try payload([point(0, .deep, duration: 20), point(10, .light)]))
        XCTAssertThrowsError(try payload([point(55, .rem, duration: 10)]))
        XCTAssertThrowsError(try payload([point(-5, .light)]))
    }
    func testStableRecordIDsAreIndependentOfFileVersionAndDeviceSeparated() throws {
        let points = [point(0, .light, duration: 60)]
        let a = try XCTUnwrap(payload(points)), b = try XCTUnwrap(payload(points))
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(a.id, try payload(points, deviceID: UUID())?.id)
        XCTAssertEqual(a.metadata?.encryptedBand?.fileID, file.hex)
        XCTAssertEqual(SleepRecord(a).source, .band)
        XCTAssertEqual(SleepRecord(a).displayTimeZone.secondsFromGMT(), 8 * 3600)
    }
    func testEndDayUsesDeviceOffsetAcrossMidnight() throws {
        let session = STBandSleepSession(bedTime: start.addingTimeInterval(-1800), wakeTime: start.addingTimeInterval(1800),
                                        deepMinutes: nil, lightMinutes: nil, remMinutes: nil, awakeMinutes: nil,
                                        stages: [point(-30, .light, duration: 60)])
        let payload = try XCTUnwrap(EncryptedBandSleepAdapter.payload(session: session, file: file, device: device, name: "测试设备"))
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let expected = String(formatter.string(from: payload.end).prefix(10))
        XCTAssertEqual(payload.metadata?.encryptedBand?.endDay, expected)
        XCTAssertEqual(SleepRecord(payload).displayClock(payload.start), "23:30")
        XCTAssertEqual(SleepRecord(payload).displayClock(payload.end), "00:30")
    }
    @MainActor
    func testRepeatedImportPreservesUserNotesAndOtherRecords() throws {
        let container = try ModelContainer(for: SleepRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let first = try XCTUnwrap(payload([point(0, .light, duration: 60)]))
        try EncryptedBandSleepAdapter.save([first], in: context)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SleepRecord>()).first)
        record.note = "用户的独立备注"
        var manual = first; manual.id = UUID(); manual.source = .manual; manual.metadata = nil
        context.insert(SleepRecord(manual)); try context.save()
        try EncryptedBandSleepAdapter.save([first], in: context)
        let all = try context.fetch(FetchDescriptor<SleepRecord>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == first.id }?.note, "用户的独立备注")
        XCTAssertEqual(all.filter { $0.source == .manual }.count, 1)
    }
    func testDailyActivityUsesLatestTotalAndKeepsZero() {
        let day = EncryptedBandActivityDay(deviceID: device, day: "2026-11-09", steps: 100, updatedAt: start)
        var updated = day; updated.steps = 150; updated.updatedAt += 60
        var zero = day; zero.day = "2026-11-10"; zero.steps = 0
        let result = EncryptedBandActivityDay.merge([updated, updated, zero], into: [day])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.steps).reduce(0, +), 150)
        XCTAssertEqual(result.first?.steps, 0)
    }
    func testTruncatedAndUnknownFilesDoNotCrash() {
        for size in 0..<100 {
            var generator: UInt64 = UInt64(size + 1)
            let data = Data((0..<size).map { _ in generator = generator &* 6364136223846793005 &+ 1; return UInt8(truncatingIfNeeded: generator >> 32) })
            XCTAssertFalse(STBandActivityParser.parse(data).isParsed)
            _ = STBandPBMessage(data)
        }
    }
}

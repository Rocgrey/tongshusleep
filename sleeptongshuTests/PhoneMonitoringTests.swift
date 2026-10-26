import AVFoundation
import XCTest
@testable import sleeptongshu

@MainActor
final class PhoneMonitoringTests: XCTestCase {
    func testOwnAudioActivationAndOutputChangesDoNotEndCapture() {
        for reason in [AVAudioSession.RouteChangeReason.categoryChange, .newDeviceAvailable, .oldDeviceUnavailable] {
            XCTAssertFalse(PhoneMonitoringPolicy.shouldStopForRouteChange(
                reason: reason.rawValue, inputChanged: false, engineRunning: true))
        }
        XCTAssertTrue(PhoneMonitoringPolicy.shouldStopForRouteChange(
            reason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, inputChanged: true, engineRunning: true))
        XCTAssertTrue(PhoneMonitoringPolicy.shouldStopForRouteChange(
            reason: AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue, inputChanged: false, engineRunning: true))
        XCTAssertTrue(PhoneMonitoringPolicy.shouldStopForRouteChange(
            reason: nil, inputChanged: false, engineRunning: false))
    }

    func testElapsedTimeAdvancesWithoutDependingOnSignalWindows() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(PhoneMonitoringPolicy.elapsed(from: start, to: start), 0)
        XCTAssertEqual(PhoneMonitoringPolicy.elapsed(from: start, to: start.addingTimeInterval(1)), 1)
        XCTAssertEqual(PhoneMonitoringPolicy.elapsed(from: start, to: start.addingTimeInterval(61)), 61)
        XCTAssertEqual(PhoneMonitoringPolicy.elapsed(from: start, to: start.addingTimeInterval(8 * 3600)), 8 * 3600)
        // Silence with continuing audio is valid capture, not a signal timeout or waking detection.
        let morning = start.addingTimeInterval(8 * 3600)
        XCTAssertNil(PhoneMonitoringPolicy.stopReason(start: start, lastSignal: morning, now: morning))
        XCTAssertEqual(PhoneMonitoringPolicy.stopReason(start: start, lastSignal: start, now: start.addingTimeInterval(31)), .signalLost)
        let limit = start.addingTimeInterval(23 * 3600)
        XCTAssertEqual(PhoneMonitoringPolicy.stopReason(start: start, lastSignal: limit, now: limit), .timeLimit)
    }

    func testRecoveredSessionKeepsStoppedElapsedTimeAndAcceptsOldDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("active.json")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var checkpoint = PhoneCheckpoint(start: start, end: start.addingTimeInterval(30),
            epochs: [PhoneEpoch(date: start, audioSeconds: 30)], classifierAvailable: false)
        checkpoint.stoppedAt = start.addingTimeInterval(40)
        try JSONEncoder().encode(checkpoint).write(to: url)
        let recovered = PhoneSleepMonitor(draftURL: url)
        XCTAssertFalse(recovered.isRecording)
        XCTAssertEqual(recovered.elapsedSeconds, 40)
        recovered.stop()
        XCTAssertEqual(recovered.elapsedSeconds, 40)
        XCTAssertEqual(recovered.checkpoint?.end, start.addingTimeInterval(30))
        checkpoint.stoppedAt = nil
        let oldDraft = try JSONEncoder().encode(checkpoint)
        XCTAssertFalse(String(decoding: oldDraft, as: UTF8.self).contains("stoppedAt"))
        try oldDraft.write(to: url)
        let legacy = PhoneSleepMonitor(draftURL: url)
        XCTAssertEqual(legacy.elapsedSeconds, 30)
        XCTAssertFalse(legacy.isRecording)
    }
}

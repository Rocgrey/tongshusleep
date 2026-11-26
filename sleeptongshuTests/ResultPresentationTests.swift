import XCTest
import AVFoundation
@testable import sleeptongshu

@MainActor final class ResultPresentationTests: XCTestCase {
    private func entry(_ score: Int, day: Double, algorithm: String = PSQI.version) -> PSQIEntry {
        PSQIEntry(date: Date(timeIntervalSince1970: day * 86400), algorithm: algorithm, answers: [:],
                  result: PSQIResult(components: [score, 0, 0, 0, 0, 0, 0], efficiency: 100, hours: 8, concerns: []))
    }
    func testComparisonExcludesFutureAndIncompatibleResults() {
        let first = entry(3, day: 1), second = entry(1, day: 2), future = entry(2, day: 3)
        let comparison = PSQIComparison(entry: second, history: [future, entry(0, day: 1.5, algorithm: "other"), first, second])
        XCTAssertEqual(comparison.previous?.id, first.id)
        XCTAssertEqual(comparison.delta, -2)
        XCTAssertEqual(comparison.timeline.map(\.id), [first.id, second.id])
    }
    func testFirstRecordZeroBaselineAndUnchangedScores() {
        let zero = entry(0, day: 1), next = entry(2, day: 2), same = entry(2, day: 3)
        XCTAssertNil(PSQIComparison(entry: zero, history: [zero, next]).previous)
        XCTAssertEqual(PSQIComparison(entry: next, history: [zero]).delta, 2)
        XCTAssertEqual(PSQIComparison(entry: same, history: [zero, next]).delta, 0)
        // Comparison is in points, so a previous zero never creates an invalid percentage.
        XCTAssertEqual(PSQIComparison(entry: zero, history: []).timeline.count, 1)
    }
    func testHistoryChartRemainsBoundedAndChronological() {
        let records = (1...20).map { entry($0 % 4, day: Double($0)) }
        let result = PSQIComparison(entry: records.last!, history: records.reversed())
        XCTAssertEqual(result.timeline.count, 8)
        XCTAssertEqual(result.timeline.map(\.date), Array(records.suffix(8)).map(\.date))
        XCTAssertEqual(result.previous?.id, records[18].id)
    }
    func testFemaleMandarinVoicePrefersQualityWithinLocale() {
        let options: [BreathingVoiceSelection.Candidate] = [
            .init(identifier: "male", language: "zh-CN", female: false, quality: 3),
            .init(identifier: "default", language: "zh-CN", female: true, quality: 1),
            .init(identifier: "enhanced", language: "zh-CN", female: true, quality: 2),
            .init(identifier: "premium", language: "zh-CN", female: true, quality: 3),
            .init(identifier: "english", language: "en-US", female: true, quality: 3)
        ]
        XCTAssertEqual(BreathingVoiceSelection.preferred(options)?.identifier, "premium")
        XCTAssertEqual(BreathingVoiceSelection.preferred(Array(options.reversed()))?.identifier, "premium")
        XCTAssertNil(BreathingVoiceSelection.preferred([options[0], options[4]]))
        XCTAssertNil(BreathingVoiceSelection.preferred([]))
    }
    func testMandarinLocalePriorityAndFemaleFallback() {
        let mainland = BreathingVoiceSelection.Candidate(identifier: "mainland", language: "zh-CN", female: true, quality: 1)
        let taiwan = BreathingVoiceSelection.Candidate(identifier: "taiwan", language: "zh-TW", female: true, quality: 3)
        XCTAssertEqual(BreathingVoiceSelection.preferred([taiwan, mainland])?.identifier, mainland.identifier)
        XCTAssertEqual(BreathingVoiceSelection.preferred([taiwan])?.identifier, taiwan.identifier)
    }
    func testProductPlaybackCannotInterruptRecordingOrCreateMediaRequest() {
        let coordinator = AudioCoordinator.shared
        coordinator.beginRecording()
        defer { coordinator.endRecording() }
        var created = false
        let playback = ProductVideoPlayback(makePlayer: { created = true; return AVPlayer() })
        playback.play()
        XCTAssertFalse(created); XCTAssertNil(playback.player); XCTAssertNotNil(playback.message)
    }
    func testRecordingPreemptsVideoAndRepeatedPlayKeepsSinglePlayer() throws {
        var created = 0
        let playback = ProductVideoPlayback(makePlayer: { created += 1; return AVPlayer() })
        playback.play()
        guard playback.player != nil else { throw XCTSkip("Simulator audio session unavailable") }
        let first = playback.player
        playback.play()
        XCTAssertTrue(first === playback.player); XCTAssertEqual(created, 1)
        AudioCoordinator.shared.beginRecording()
        defer { AudioCoordinator.shared.endRecording(); playback.stop() }
        XCTAssertNil(playback.player)
    }
}

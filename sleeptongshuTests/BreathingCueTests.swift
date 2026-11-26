import XCTest
import AVFoundation
@testable import sleeptongshu

final class BreathingCueTests: XCTestCase {
    func testGentleToneHasFiniteAudibleSamplesSoftEndsAndDistinctPhases() throws {
        let tones = (0..<3).map { BreathingCueTone.samples(phase: $0) }
        for samples in tones {
            XCTAssertEqual(samples.count, 19845)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 0.6 })
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.2)
            XCTAssertEqual(samples.first, 0); XCTAssertEqual(samples.last, 0)
        }
        XCTAssertNotEqual(tones[0], tones[1]); XCTAssertNotEqual(tones[1], tones[2])
        let data = BreathingCueTone.waveData(phase: 0)
        XCTAssertEqual(data.count, 44 + 19845 * 2)
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.9, accuracy: 0.001)
        XCTAssertEqual(player.numberOfChannels, 1)
    }
    @MainActor func testCueDoesNotInterruptNightRecording() {
        AudioCoordinator.shared.beginRecording()
        defer { AudioCoordinator.shared.endRecording() }
        let cue = BreathingCuePlayer(); cue.play(phase: 0)
        XCTAssertTrue(cue.message?.contains("正在录音") == true)
        XCTAssertTrue(AudioCoordinator.shared.recording)
    }
}

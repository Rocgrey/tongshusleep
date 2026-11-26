import XCTest
@testable import sleeptongshu

@MainActor final class PSQITests: XCTestCase {
    private func answers() -> [String: Double] {
        var value = Dictionary(uniqueKeysWithValues: PSQI.questions.map { ($0.id, 0.0) })
        value["q1"] = 23 * 60; value["q3"] = 7 * 60; value["q2"] = 10; value["q4"] = 8
        return value
    }
    func testEighteenItemsSevenComponentsAndBestResult() throws {
        XCTAssertEqual(PSQI.questions.count, 18)
        XCTAssertEqual(Set(PSQI.questions.map(\.id)).count, 18)
        let result = try PSQI.score(answers())
        XCTAssertEqual(result.components, [0,0,0,0,0,0,0])
        XCTAssertEqual(result.total, 0); XCTAssertEqual(result.efficiency, 100)
        XCTAssertTrue(result.concerns.isEmpty)
    }
    func testWorstResultIsTwentyOneAndDoesNotInventDiagnosis() throws {
        var a = answers()
        for q in PSQI.questions where !q.options.isEmpty { a[q.id] = 3 }
        a["q2"] = 90; a["q4"] = 4
        let result = try PSQI.score(a)
        XCTAssertEqual(result.components, [3,3,3,3,3,3,3])
        XCTAssertEqual(result.total, 21)
        XCTAssertEqual(result.concerns, [.onset, .waking, .short])
        XCTAssertEqual(result.direction, "多个方面共同影响")
    }
    func testSleepDurationAndEfficiencyBoundaries() throws {
        for (hours, duration, efficiency) in [(8.0,0,0), (7,1,0), (6,1,1), (5.2,2,2), (5,2,3), (4.9,3,3), (0,3,3)] {
            var a = answers(); a["q4"] = hours
            let result = try PSQI.score(a)
            XCTAssertEqual(result.components[2], duration, "hours \(hours)")
            XCTAssertEqual(result.components[3], efficiency, "hours \(hours)")
        }
    }
    func testLatencyAndDaytimeCombinedScores() throws {
        for (minutes, frequency, component) in [(15.0,0.0,0), (30,1,1), (60,2,2), (61,3,3)] {
            var a = answers(); a["q2"] = minutes; a["q5a"] = frequency
            XCTAssertEqual(try PSQI.score(a).components[1], component)
        }
        for (sum, expected) in [(0,0),(1,1),(2,1),(3,2),(4,2),(5,3),(6,3)] {
            var a = answers(); a["q8"] = Double(min(3, sum)); a["q9"] = Double(max(0, sum - 3))
            XCTAssertEqual(try PSQI.score(a).components[6], expected)
        }
    }
    func testMissingAndImpossibleAnswersCannotBecomeZero() throws {
        var a = answers(); a.removeValue(forKey: "q5j"); XCTAssertThrowsError(try PSQI.score(a))
        a = answers(); a["q4"] = 9; XCTAssertThrowsError(try PSQI.score(a))
        a = answers(); a["q3"] = a["q1"]; XCTAssertThrowsError(try PSQI.score(a))
        a = answers(); a["q6"] = 0.5; XCTAssertThrowsError(try PSQI.score(a))
        a = answers(); a["q2"] = .nan; XCTAssertThrowsError(try PSQI.score(a))
        a = answers(); a["q1"] = 8 * 60; a["q3"] = 16 * 60
        XCTAssertEqual(try PSQI.score(a).efficiency, 100) // Shift workers' daytime main sleep.
    }
    func testHistoryRoundTripDeletionAndAccountServiceIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PSQIHistory(directory: directory)
        store.load(service: "https://one.test", userID: 1)
        let saved = try store.save(answers())
        store.load(service: "https://one.test", userID: 2); XCTAssertTrue(store.entries.isEmpty)
        store.load(service: "https://two.test", userID: 1); XCTAssertTrue(store.entries.isEmpty)
        store.load(service: "https://one.test", userID: 1)
        XCTAssertEqual(store.entries.first?.id, saved.id); XCTAssertEqual(store.entries.first?.result.total, 0)
        try store.delete(saved.id)
        store.load(service: "https://one.test", userID: 1); XCTAssertTrue(store.entries.isEmpty)
    }
    func testAllPresetsAudibleAtComparablePCMLevelsAndLoopJoined() {
        for sound in GroveNoise.library {
            let samples = sound.samples(rate: 22050, seconds: 2)
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
            XCTAssertGreaterThan(rms, 0.10, sound.title)
            XCTAssertLessThanOrEqual(rms, 0.171, sound.title)
            XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.800001)
            XCTAssertEqual(samples.first, samples.last)
        }
    }
    func testStopDuringNoiseSynthesisCannotResurrectPlayback() async {
        let audio = WhiteNoisePlayer.shared
        let start = Task { await audio.start(minutes: 5, sound: GroveNoise.library[23]) }
        await Task.yield()
        audio.stop()
        await start.value
        XCTAssertFalse(audio.playing); XCTAssertFalse(audio.loading); XCTAssertNil(audio.deadline)
    }
    func testBreathingBoundaryCountsMatchAllThreeGuidanceStages() {
        for (elapsed, title, remaining) in [(0.0,"吸气",4),(3.99,"吸气",1),(4,"屏息",7),(10.99,"屏息",1),(11,"呼气",8),(18.99,"呼气",1),(19,"吸气",4)] {
            let phase = BreathingCycle.phase(elapsed: elapsed)
            XCTAssertEqual(phase.title, title); XCTAssertEqual(phase.remaining, remaining)
        }
    }
    func testBreathingSpeechDoesNotTakeRecordingSession() {
        let coordinator = AudioCoordinator.shared
        coordinator.beginRecording()
        defer { coordinator.endRecording() }
        let cue = BreathingCuePlayer()
        var completed = false
        cue.introduction { completed = true }
        XCTAssertTrue(completed) // Visual exercise is still usable without sound.
        XCTAssertNotNil(cue.message)
        cue.play(phase: 0, tone: true, voice: true)
        cue.stop()
        XCTAssertTrue(coordinator.recording)
    }
}

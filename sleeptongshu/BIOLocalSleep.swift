import Foundation

enum BIOLocalSleep {
    static var available: Bool { STBIOLocalSleepBridge.available }
    static let version = "vendor-local-IVSleep-9c932284-rri1"

    /// Keep signed control values and day order. Do not interpolate absent RRI.
    static func rri(_ request: BIOSleepAlgorithmRequest) -> [NSNumber] {
        // The manufacturer JNI adapter inserts -1000 BETWEEN the two days before
        // calling the same readSleepFile::SetRRi API used by IVSleep. The iOS
        // bundled one-day example likewise starts with -1000 (empty prior day).
        let values = request.prevDayRri + [-1000] + request.nextDayRri
        return values.enumerated().compactMap { index, value in
            index > 0 && value == -1 && values[index - 1] == -1 ? nil : NSNumber(value: value)
        }
    }
}

extension WearableProbeWorker {
    /// Native computation and temporary files stay off the main actor. The bridge
    /// also serializes the vendor engine across independent worker instances.
    func localSleep(_ request: BIOSleepAlgorithmRequest) throws -> BIOSleepAlgorithmResult {
        try Task.checkCancellation()
        let date = String(request.recordDate)
        guard date.count == 8, request.prevDay.utf8.count <= 4_000_000,
              request.nextDay.utf8.count <= 4_000_000,
              request.prevDayRri.count + request.nextDayRri.count <= 400_000 else { throw SleepDataError.invalidRecord }
        for text in [request.prevDay, request.nextDay] {
            guard let rows = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]],
                  !rows.isEmpty, rows.count <= 1440 else { throw SleepDataError.invalidRecord }
            for row in rows {
                guard let t = row["T"] as? [Int], t.count == 2,
                      (0..<24).contains(t[0]), (0..<60).contains(t[1]) else { throw SleepDataError.invalidRecord }
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bio-sleep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let yesterday = directory.appendingPathComponent("previous.json"), today = directory.appendingPathComponent("today.json")
        try Data(request.prevDay.utf8).write(to: yesterday, options: [.atomic, .completeFileProtectionUnlessOpen])
        try Data(request.nextDay.utf8).write(to: today, options: [.atomic, .completeFileProtectionUnlessOpen])
        let data = try STBIOLocalSleepBridge.calculate(previousPath: yesterday.path, todayPath: today.path,
                                                      date: date, rri: BIOLocalSleep.rri(request))
        try Task.checkCancellation()
        return try JSONDecoder().decode(BIOSleepAlgorithmResult.self, from: data)
    }
}

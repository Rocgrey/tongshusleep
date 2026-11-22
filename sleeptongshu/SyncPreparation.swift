import Foundation

/// Copy persisted bytes on the model's executor, never pass live SwiftData objects to a worker.
struct SleepSyncSnapshot: Equatable {
    var id: UUID
    var start: Date
    var end: Date
    var source: String
    var segments: Data
    var hearts: Data
    var heart: Double?
    var oxygen: Double?
    var respiration: Double?
    var note: String
    var metadata: Data?
    init(_ record: SleepRecord) {
        id = record.id; start = record.start; end = record.end; source = record.sourceRawValue
        segments = record.segmentsData; hearts = record.heartSamplesData
        heart = record.averageHeartRate; oxygen = record.averageSpO2; respiration = record.averageRespiratoryRate
        note = record.note; metadata = record.metadataData
    }
    func makeRecord() -> SleepRecord {
        let record = SleepRecord(SleepPayload(id: id, start: start, end: end, source: SleepDataSource(rawValue: source) ?? .manual,
            segments: [], heartSamples: [], averageHeartRate: heart, averageSpO2: oxygen, averageRespiratoryRate: respiration, note: note))
        record.segmentsData = segments; record.heartSamplesData = hearts; record.metadataData = metadata
        return record
    }
}
struct SyncPreparationInput: Equatable {
    var sleep: [SleepSyncSnapshot]
    var steps: [DeviceStepDay]
    var healthSteps: [LocalStepDay]
    var vitals: [WearableVital]
}
struct PreparedSyncBatch {
    var requests: [DeviceSyncRequest]
    var fingerprints: [String: String]
}
actor SyncPreparationWorker {
    static let shared = SyncPreparationWorker()
    private var previous: SyncPreparationInput?
    private var cached = PreparedSyncBatch(requests: [], fingerprints: [:])
    private(set) var buildCount = 0
    func prepare(_ input: SyncPreparationInput) -> PreparedSyncBatch {
        guard previous != input else { return cached }
        let sleep = input.sleep.compactMap { snapshot -> DeviceSyncRequest? in
            let record = snapshot.makeRecord()
            guard record.isVisible, record.source != .sample else { return nil }
            return try? DeviceSyncRequest.sleep(record)
        }
        let requests = (sleep + input.steps.map(DeviceSyncRequest.step)
            + input.healthSteps.map(DeviceSyncRequest.healthStep)
            + DeviceSyncRequest.vitalDays(input.vitals.filter { $0.date <= Date.now.addingTimeInterval(300) })).sorted { $0.record_key < $1.record_key }
        cached = PreparedSyncBatch(requests: requests, fingerprints: Dictionary(requests.map { ($0.record_key, $0.fingerprint) }, uniquingKeysWith: { _, last in last }))
        previous = input; buildCount += 1
        return cached
    }
    func encode(_ request: DeviceSyncRequest) throws -> Data { try request.encoded() }
    func decodeInventory(_ data: Data) throws -> SyncRemotePage { try APIJSON.decode(SyncRemotePage.self, from: data) }
    func clear() { previous = nil; cached = PreparedSyncBatch(requests: [], fingerprints: [:]) }
}

struct DeviceReportMilestone: Equatable {
    var finished: Date?
    var rawFinished: Date?
    init(_ report: WearableProbeReport?) { finished = report?.finishedAt; rawFinished = report?.rawSensorFinishedAt }
}

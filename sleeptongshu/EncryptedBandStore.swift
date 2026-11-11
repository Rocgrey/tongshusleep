import Foundation
import Combine
import CryptoKit
import Security
import SwiftData

/// Device credentials are independent of account login and never enter backups or diagnostics.
struct EncryptedBandCredentialStore {
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.rocgrey.sleeptongshu.band-auth-v1",
         kSecAttrAccount as String: id.uuidString]
    }
    func load(_ id: UUID) throws -> Data? {
        var item = query(id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 16 else { throw APIError.secureStorage }
        return data
    }
    func save(_ data: Data, for id: UUID) throws {
        guard data.count == 16 else { throw APIError.validation("绑定凭证必须是 32 位十六进制字符。") }
        let fields: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(id) as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(id).merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw APIError.secureStorage }
        } else if status != errSecSuccess { throw APIError.secureStorage }
    }
    func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.secureStorage }
    }
    static func parse(_ text: String) throws -> Data {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count == 32, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw APIError.validation("请输入 32 位十六进制绑定凭证，不是账号密码。")
        }
        let bytes = Array(value.utf8)
        return Data(stride(from: 0, to: 32, by: 2).map { UInt8(String(bytes: bytes[$0..<$0 + 2], encoding: .utf8)!, radix: 16)! })
    }
}

struct EncryptedBandSleepOrigin: Codable {
    var deviceID: UUID
    var fileID: String
    var utcOffsetMinutes: Int
    var endDay: String
    var parserVersion = "freeband-adapter-v1"
}

struct EncryptedBandActivityDay: Codable, Identifiable {
    var deviceID: UUID
    var day: String
    var steps: Int
    var updatedAt: Date
    var id: String { "\(deviceID.uuidString)|\(day)" }
    static func merge(_ incoming: [Self], into existing: [Self]) -> [Self] {
        var byID: [String: Self] = [:]
        for record in existing + incoming where (0...200_000).contains(record.steps) {
            if let old = byID[record.id], old.updatedAt > record.updatedAt { continue }
            byID[record.id] = record // Same-day values replace, never add to a previous total.
        }
        return byID.values.sorted { $0.day > $1.day }
    }
}

/// Convert only explicit stage intervals. Gaps and unknown codes stay unrecorded.
enum EncryptedBandSleepAdapter {
    @MainActor
    static func save(_ payloads: [SleepPayload], in context: ModelContext) throws {
        do {
            let existing = try context.fetch(FetchDescriptor<SleepRecord>())
            for payload in payloads {
                try payload.validate()
                if let old = existing.first(where: { $0.id == payload.id }) {
                    guard old.source == .band, old.metadata?.externalID == payload.metadata?.externalID else { throw SleepDataError.invalidRecord }
                    guard old.end <= payload.end else { continue }
                    if old.end == payload.end,
                       old.segments.filter({ $0.stage != .unobserved }).reduce(0, { $0 + $1.minutes }) > payload.segments.filter({ $0.stage != .unobserved }).reduce(0, { $0 + $1.minutes }) { continue }
                    var next = payload; next.note = old.note; old.replace(with: next)
                } else { context.insert(SleepRecord(payload)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    static func payload(session: STBandSleepSession, file: STBandActivityFileID, device: UUID, name: String) throws -> SleepPayload? {
        guard !session.stages.isEmpty else { return nil }
        let start = session.bedTime, end = session.wakeTime
        guard end > start, end.timeIntervalSince(start) <= 86400, end <= .now.addingTimeInterval(300) else { throw SleepDataError.invalidRecord }
        let points = session.stages.sorted { $0.ts < $1.ts }
        var segments: [SleepSegment] = []
        var cursor = start
        for (index, point) in points.enumerated() {
            let next = index + 1 < points.count ? points[index + 1].ts : end
            let until = point.durationMinutes.map { point.ts.addingTimeInterval(Double($0) * 60) } ?? next
            guard point.ts >= start, point.ts >= cursor, until > point.ts, until <= end, until <= next else { throw SleepDataError.invalidRecord }
            if point.ts > cursor { segments.append(SleepSegment(stage: .unobserved, start: cursor, end: point.ts)) }
            let stage: SleepStage
            switch point.stage {
            case .light: stage = .light
            case .deep: stage = .deep
            case .rem: stage = .rem
            case .awake: stage = .awake
            case .notSleep, .unknown: stage = .unobserved
            }
            segments.append(SleepSegment(stage: stage, start: point.ts, end: until))
            cursor = until
        }
        if cursor < end { segments.append(SleepSegment(stage: .unobserved, start: cursor, end: end)) }
        guard segments.contains(where: { $0.stage.isAsleep }) else { return nil }
        let external = "encrypted-band|\(device.uuidString)|\(Int(start.timeIntervalSince1970))"
        let hash = Array(SHA256.hash(data: Data(external.utf8)).prefix(16))
        let id = UUID(uuid: (hash[0],hash[1],hash[2],hash[3],hash[4],hash[5],hash[6],hash[7],hash[8],hash[9],hash[10],hash[11],hash[12],hash[13],hash[14],hash[15]))
        let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = file.timeZone ?? .current; format.dateFormat = "yyyy-MM-dd"
        let origin = EncryptedBandSleepOrigin(deviceID: device, fileID: file.hex, utcOffsetMinutes: file.utcOffsetMinutes, endDay: format.string(from: end))
        let result = SleepPayload(id: id, start: start, end: end, source: .band, segments: segments, heartSamples: [],
                                  averageHeartRate: nil, averageSpO2: nil, averageRespiratoryRate: nil, note: "",
                                  metadata: SleepMetadata(externalSource: name, externalID: external, encryptedBand: origin))
        try result.validate()
        return result
    }
}

/// Session/file transport is adapted from Freeband; persistence and UI belong to this App.
@MainActor
final class EncryptedBandStore: ObservableObject {
    @Published private(set) var deviceID: UUID?
    @Published private(set) var deviceName: String?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "连接设备后可导入已有绑定凭证"
    @Published private(set) var summary: String?
    @Published private(set) var batchID = UUID()
    @Published private(set) var lastReadAt: Date?
    @Published private(set) var savedSleepCount = 0
    @Published private(set) var steps: Int?
    @Published private(set) var activityDays: [EncryptedBandActivityDay] = []
    var currentActivityDays: [EncryptedBandActivityDay] { activityDays.filter { $0.deviceID == deviceID } }
    private(set) var link: STBandBandLink?
    private var observation: AnyCancellable?
    private let credentials = EncryptedBandCredentialStore()
    private var pending: [UUID: SleepPayload] = [:]
    private var pendingVitals: [String: WearableVital] = [:]
    private var fileNotes: [String] = []
    private var storageFailed = false
    private var fileCount = 0
    private var pendingActivity: [EncryptedBandActivityDay] = []
    private var activityURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("encrypted-band-activity-v1.json")
    }
    init() {
        if let url = activityURL, let data = try? Data(contentsOf: url), let records = try? JSONDecoder().decode([EncryptedBandActivityDay].self, from: data) {
            activityDays = records
        }
    }
    var battery: Int? { link?.battery }
    var progress: Double? {
        guard let value = link?.fileProgress, value.total > 0 else { return nil }
        return Double(value.done) / Double(value.total)
    }
    var phaseText: String { isBusy ? link?.phase.label ?? status : status }
    var diagnostic: String {
        (["加密设备接入 · 实测适配", "状态：\(phaseText)", "本次文件：\(fileCount)", summary ?? "尚未保存本次结果"] + fileNotes + (link?.log ?? [])).joined(separator: "\n")
    }
    func hasCredential(_ id: UUID) -> Bool { (try? credentials.load(id)) != nil }
    func bind(_ text: String, id: UUID, name: String) throws {
        guard !isBusy else { return }
        try credentials.save(EncryptedBandCredentialStore.parse(text), for: id)
        if deviceID != id { link = nil; lastReadAt = nil; steps = nil; summary = nil }
        deviceID = id; deviceName = name
        status = "绑定凭证已安全保存在本机，等待自动读取"
    }
    func forget(_ id: UUID) throws {
        guard !isBusy else { return }
        try credentials.remove(id)
        if deviceID == id { deviceID = nil; deviceName = nil; summary = nil; status = "绑定凭证已移除，历史记录保留" }
    }
    func stop() { link?.stop() }
    func fail(_ message: String) { isBusy = false; status = message }

    func sync(id: UUID, name: String) {
        guard !isBusy else { return }
        do {
            guard let key = try credentials.load(id) else { throw APIError.validation("请先导入这台设备的绑定凭证。") }
            deviceID = id; deviceName = name; pending = [:]; pendingVitals = [:]
            pendingActivity = []
            fileNotes = []; fileCount = 0; storageFailed = false; summary = nil; steps = nil; lastReadAt = nil
            let link = STBandBandLink()
            self.link = link
            observation = link.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            link.hasActivityFile = { _, _ in false } // Re-read for device-side corrections; local imports are idempotent.
            link.onSample = { [weak self] _, sample in
                if case .live(let live) = sample, let count = live.steps, count <= 200_000 { self?.steps = Int(count) }
            }
            link.onActivityFile = { [weak self] _, file, bytes, _ in self?.receive(file, bytes: bytes) }
            link.onFinish = { [weak self] _, outcome in
                guard let self else { return }
                self.isBusy = false; self.lastReadAt = .now
                switch outcome {
                case .complete: self.status = self.storageFailed ? "部分文件未能保存，请重连后重试" : "本次文件读取结束"
                case .partial(let message): self.status = message
                case .failed(let error): self.status = error.message
                }
                self.batchID = UUID()
            }
            isBusy = true; status = "正在连接已选设备"
            link.start(STBandBandTarget(id: id, name: name, mac: nil, macSuffix: nil, keys: [key]), purpose: .sync)
        } catch { fail(error.localizedDescription) }
    }

    private func receive(_ file: STBandActivityFileID, bytes: Data) {
        guard let deviceID, let deviceName else { return }
        let result = STBandActivityParser.parse(bytes)
        guard result.crc?.ok == true, result.fileID == file else { fileNotes.append("文件校验未通过，已跳过"); return }
        fileCount += 1
        do {
            // Keep CRC-checked originals for protocol verification. No authentication keys are stored here.
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("EncryptedBand/\(deviceID.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var fileURL = folder.appendingPathComponent(file.hex + ".bin")
            try bytes.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            var session: STBandSleepSession?
            switch result.payload {
            case .sleepDetails(let sleep):
                guard sleep.streamError == nil else { fileNotes.append("睡眠文件存在不完整区段，原文件已保留，未导入"); return }
                session = sleep.session
            case .sleepStages(let sleep): session = sleep.session
            case .dailyDetails(let daily):
                for row in daily.records {
                    addVital(row.heartRate, .heart, date: row.ts)
                    addVital(row.spo2, .oxygen, date: row.ts)
                    addVital(row.stress, .stress, date: row.ts)
                }
            case .manualSamples(let manual):
                for row in manual.samples {
                    switch row.kind {
                    case .heartRate: addVital(row.value, .heart, date: row.ts)
                    case .spo2: addVital(row.value, .oxygen, date: row.ts)
                    case .stress: addVital(row.value, .stress, date: row.ts)
                    case .temperature: break
                    }
                }
            case .dailySummary(let daily):
                fileNotes.append("活动日 \(daily.day.formatted(date: .abbreviated, time: .omitted))：\(daily.steps.map { "\($0) 步" } ?? "未提供步数")")
                if let steps = daily.steps, (0...200_000).contains(steps) {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = file.timeZone ?? .current
                    formatter.dateFormat = "yyyy-MM-dd"
                    pendingActivity.append(EncryptedBandActivityDay(deviceID: deviceID, day: formatter.string(from: daily.day), steps: steps, updatedAt: .now))
                }
            case .unsupported: fileNotes.append("有文件格式尚未支持，原文件已保留")
            case .error: fileNotes.append("有文件未能可靠解析，原文件已保留")
            case .empty: break
            }
            if let session {
                if let payload = try EncryptedBandSleepAdapter.payload(session: session, file: file, device: deviceID, name: deviceName) {
                    // Same bedtime is a growing record. Prefer the later end, then greater observed coverage.
                    if let old = pending[payload.id], old.end > payload.end { return }
                    if let old = pending[payload.id], old.end == payload.end,
                       old.segments.filter({ $0.stage != .unobserved }).reduce(0, { $0 + $1.minutes }) > payload.segments.filter({ $0.stage != .unobserved }).reduce(0, { $0 + $1.minutes }) { return }
                    pending[payload.id] = payload
                } else { fileNotes.append("睡眠文件没有可确认的分期区间，未生成睡眠图") }
            }
        } catch {
            storageFailed = true
            fileNotes.append("文件保存或睡眠整理未完成：\(error.localizedDescription)")
        }
        if fileNotes.count > 100 { fileNotes.removeFirst(fileNotes.count - 100) }
    }
    private func addVital(_ value: Int?, _ kind: VitalKind, date: Date) {
        guard let value, kind.accepts(Double(value)), date > Date(timeIntervalSince1970: 946684800), date <= .now.addingTimeInterval(300), let deviceID else { return }
        let vital = WearableVital(device: WearableVital.deviceKey(deviceID.uuidString), deviceLabel: deviceName ?? "设备",
                                  date: date, kind: kind, value: Double(value), origin: "蓝牙设备历史")
        pendingVitals[vital.id] = vital
    }
    /// Shared local database, stable device/bedtime IDs, and independent user notes are preserved.
    func save(in context: ModelContext, vitals: WearableVitalsStore) {
        do {
            try EncryptedBandSleepAdapter.save(Array(pending.values), in: context)
            let count = try vitals.merge(Array(pendingVitals.values))
            if !pendingActivity.isEmpty {
                let next = EncryptedBandActivityDay.merge(pendingActivity, into: activityDays)
                guard let url = activityURL else { throw CocoaError(.fileWriteUnknown) }
                try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                activityDays = next
            }
            savedSleepCount = pending.count
            summary = "本次保存或更新 \(pending.count) 段睡眠、\(count) 条体征、\(pendingActivity.count) 份活动日记录。" + (pending.isEmpty ? "未取得可导入的睡眠分期；请查看读取详情。" : "睡眠页与体征记录已更新。")
            pending = [:]; pendingVitals = [:]
        } catch {
            context.rollback()
            summary = "本地保存未完成，请重连后重试：\(error.localizedDescription)"
        }
    }
}

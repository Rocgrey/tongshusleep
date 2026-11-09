import HealthKit
import CryptoKit
import SwiftData

struct HealthSleepInterval: Codable, Equatable, Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
    var timeZoneIdentifier: String? = nil
}

enum HealthSleepNormalizer {
    /// Sweep boundaries; bed intervals are context, never additional sleep.
    static func segments(_ intervals: [HealthSleepInterval]) -> [SleepSegment] {
        var events: [Date: [(SleepStage, Int)]] = [:]
        for value in intervals where value.end > value.start {
            events[value.start, default: []].append((value.stage, 1))
            events[value.end, default: []].append((value.stage, -1))
        }
        let dates = events.keys.sorted()
        var counts: [SleepStage: Int] = [:], result: [SleepSegment] = []
        for (start, end) in zip(dates, dates.dropFirst()) {
            for (stage, delta) in events[start] ?? [] { counts[stage, default: 0] += delta }
            let active = Set(counts.filter { $0.value > 0 }.map(\.key))
            let known = active.subtracting([.unspecified, .unobserved, .inBed])
            let stage: SleepStage
            if known.count == 1 { stage = known.first! }
            else if known.count > 1 { stage = .unobserved }
            else if active.contains(.unspecified) { stage = .unspecified }
            else if active.contains(.inBed) { stage = .inBed }
            else { stage = .unobserved }
            if result.last?.stage == stage { result[result.count - 1].end = end }
            else { result.append(SleepSegment(stage: stage, start: start, end: end)) }
        }
        return result.map { value in
            var value = value
            value.id = stableID("segment|\(value.stage.rawValue)|\(value.start.timeIntervalSince1970)|\(value.end.timeIntervalSince1970)")
            return value
        }
    }
    static func covers(_ range: ClosedRange<Date>, with intervals: [HealthSleepInterval]) -> Bool {
        var cursor = range.lowerBound
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.end > cursor {
            if interval.start > cursor { return false }
            cursor = max(cursor, interval.end)
            if cursor >= range.upperBound { return true }
        }
        return false
    }
    static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct HealthSleepCandidate {
    let sourceID: String
    let intervals: [HealthSleepInterval]
    var origin: HealthSleepOrigin? = nil
}

enum HealthSleepImporter {
    static var enabled: Bool { (Bundle.main.object(forInfoDictionaryKey: "SleepHealthKitEnabled") as? String)?.uppercased() == "YES" }
    static func night(_ end: Date, calendar: Calendar = .current) -> Date { calendar.startOfDay(for: end) }

    private struct Episode {
        let candidate: HealthSleepCandidate
        let raw: [HealthSleepInterval]
        let segments: [SleepSegment]
        let bedRangeIsComplete: Bool
        var start: Date { segments.first!.start }
        var end: Date { segments.last!.end }
        var attributionEnd: Date { segments.last(where: { $0.stage.isAsleep })?.end ?? end }
        var observedStart: Date { segments.first(where: { $0.stage.isAsleep || $0.stage == .awake })?.start ?? start }
        var observedEnd: Date { segments.last(where: { $0.stage.isAsleep || $0.stage == .awake })?.end ?? end }
        func overlaps(_ other: Episode) -> Bool { observedStart < other.observedEnd && observedEnd > other.observedStart }
        var detailed: Double { seconds { [.deep, .light, .rem].contains($0) } }
        var asleep: Double { seconds { $0.isAsleep } }
        func seconds(_ match: (SleepStage) -> Bool) -> Double {
            segments.filter { match($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }
    }
    private static func clusters(_ intervals: [HealthSleepInterval]) -> [[HealthSleepInterval]] {
        var result: [[HealthSleepInterval]] = [], end = Date.distantPast
        for interval in intervals.sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }) {
            // Only groups observations; a gap remains unknown, never sleep/awake.
            if result.isEmpty || interval.start.timeIntervalSince(end) > 30 * 60 { result.append([interval]) }
            else { result[result.count - 1].append(interval) }
            end = max(end, interval.end)
        }
        return result
    }
    private static func episodes(_ candidate: HealthSleepCandidate) -> [Episode] {
        let valid = candidate.intervals.filter { $0.end > $0.start && $0.end.timeIntervalSince($0.start) <= 24 * 3600 }
        var groups = clusters(valid.filter { $0.stage != .inBed })
        let bounds = groups.map { values in (values.map(\.start).min()!, values.map(\.end).max()!) }
        var raw = groups, bedOnly: [HealthSleepInterval] = []
        var splitBed = Set<Int>()
        for bed in valid.filter({ $0.stage == .inBed }) {
            let matches = bounds.indices.filter { bed.start < bounds[$0].1 && bed.end > bounds[$0].0 }
            if matches.isEmpty { bedOnly.append(bed) }
            for index in matches {
                raw[index].append(bed)
                if matches.count > 1 { splitBed.insert(index) }
                // A long bed export spanning separate sleeps must not join night and nap.
                groups[index].append(matches.count == 1 ? bed : HealthSleepInterval(id: bed.id,
                    start: max(bed.start, bounds[index].0), end: min(bed.end, bounds[index].1), stage: .inBed,
                    timeZoneIdentifier: bed.timeZoneIdentifier))
            }
        }
        for group in clusters(bedOnly) { groups.append(group); raw.append(group) }
        return groups.indices.compactMap { index in
            let segments = HealthSleepNormalizer.segments(groups[index])
            guard let start = segments.first?.start, let end = segments.last?.end,
                  end.timeIntervalSince(start) <= 24 * 3600,
                  segments.contains(where: { $0.stage.isAsleep || $0.stage == .inBed }) else { return nil }
            return Episode(candidate: candidate, raw: raw[index], segments: segments, bedRangeIsComplete: !splitBed.contains(index))
        }
    }

    static func automaticRecords(_ candidates: [HealthSleepCandidate], observations: [HealthObservation],
                                 sources: [HealthDataSource], calendar: Calendar = .current,
                                 window: HealthSleepWindow? = nil) throws -> [SleepPayload] {
        let all = candidates.flatMap(episodes).filter { window?.contains($0.attributionEnd) ?? true }
        let ranked = all.sorted { a, b in
            if a.detailed != b.detailed { return a.detailed > b.detailed }
            if a.asleep != b.asleep { return a.asleep > b.asleep }
            if a.candidate.sourceID != b.candidate.sourceID { return a.candidate.sourceID < b.candidate.sourceID }
            return a.start < b.start
        }
        var chosen: [Episode] = []
        for episode in ranked where !chosen.contains(where: { $0.overlaps(episode) }) { chosen.append(episode) }
        return try chosen.sorted { $0.start < $1.start }.map { episode in
            func values(_ metric: HealthMetric) -> [HealthObservation] {
                let valid = observations.filter { sample in
                    sample.metric == metric && sample.sourceID == episode.candidate.sourceID && metric.accepts(sample.value) &&
                    episode.segments.contains { $0.stage.isAsleep && sample.start >= $0.start && sample.end <= $0.end }
                }
                return Array(Dictionary(valid.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { $0.start < $1.start }
            }
            func average(_ metric: HealthMetric) -> Double? {
                let samples = values(metric)
                return samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
            }
            let raw = Array(Dictionary(episode.raw.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { $0.id.uuidString < $1.id.uuidString }
            let key = "health-sleep-v2|" + episode.candidate.sourceID + "|" + raw.map { $0.id.uuidString }.joined(separator: ",")
            let origin = episode.candidate.origin ?? HealthSleepOrigin(sourceID: episode.candidate.sourceID,
                appName: sources.first { $0.id == episode.candidate.sourceID }?.appName ?? "系统健康")
            let zoneSamples = raw.filter { $0.stage.isAsleep }.sorted { $0.end > $1.end } + raw.filter { !$0.stage.isAsleep }.sorted { $0.end > $1.end }
            let zone = zoneSamples.compactMap(\.timeZoneIdentifier).first.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
            let details = HealthSleepDetails(origin: origin, samples: raw,
                otherSourceIDs: Array(Set(all.filter { $0.overlaps(episode) && $0.candidate.sourceID != origin.sourceID }.map { $0.candidate.sourceID })).sorted(),
                timeZoneIdentifier: zone.identifier, endDay: formatter.string(from: episode.attributionEnd), bedRangeIsComplete: episode.bedRangeIsComplete)
            let payload = SleepPayload(id: HealthSleepNormalizer.stableID(key), start: episode.start, end: episode.end, source: .healthKit,
                segments: episode.segments, heartSamples: values(.heart).map { HeartSample(id: HealthSleepNormalizer.stableID($0.id), date: $0.start, bpm: $0.value) },
                averageHeartRate: average(.heart), averageSpO2: average(.oxygen), averageRespiratoryRate: average(.respiration), note: "",
                metadata: SleepMetadata(externalSource: "系统健康", externalID: key, healthSleep: details))
            try payload.validate()
            return payload
        }
    }

    /// Removed/hidden HealthKit records are archived in the queried range, retaining notes.
    /// Read access changes and deletion both appear as absent samples to HealthKit clients.
    @MainActor static func save(_ payloads: [SleepPayload], in context: ModelContext,
                               calendar: Calendar = .current, window: HealthSleepWindow? = nil, saveChanges: Bool = true) throws {
        try payloads.forEach { try $0.validate() }
        let records = try context.fetch(FetchDescriptor<SleepRecord>()).filter {
            $0.source == .healthKit && ($0.metadata?.healthSleep != nil || $0.metadata?.externalID?.hasPrefix("health-") == true)
        }
        var matched = Set<UUID>()
        func sampleIDs(_ samples: [HealthSleepInterval]) -> Set<UUID> {
            let phases = samples.filter { $0.stage != .inBed }
            return Set((phases.isEmpty ? samples : phases).map(\.id))
        }
        for payload in payloads {
            try payload.validate()
            let ids = sampleIDs(payload.metadata?.healthSleep?.samples ?? [])
            var previous: SleepRecord?
            var bestRank = 0.0
            for old in records where !matched.contains(old.id) {
                let rank: Double
                if old.id == payload.id || old.metadata?.externalID == payload.metadata?.externalID { rank = .greatestFiniteMagnitude }
                else if !ids.isDisjoint(with: sampleIDs(old.metadata?.healthSleep?.samples ?? [])) { rank = 1e12 }
                else { rank = max(0, min(old.end, payload.end).timeIntervalSince(max(old.start, payload.start))) }
                if rank > bestRank || (rank > 0 && rank == bestRank && old.id.uuidString < (previous?.id.uuidString ?? "")) {
                    previous = old; bestRank = rank
                }
            }
            if let previous {
                var next = payload; next.note = previous.note
                previous.replace(with: next); matched.insert(previous.id)
            } else { context.insert(SleepRecord(payload)) }
        }
        if let window {
            for old in records where !matched.contains(old.id) && window.contains(old.sleepEnd ?? old.end) {
                var metadata = old.metadata ?? SleepMetadata()
                if metadata.healthSleep == nil {
                    metadata.healthSleep = HealthSleepDetails(origin: HealthSleepOrigin(sourceID: "legacy", appName: metadata.externalSource ?? "系统健康"),
                        samples: [], otherSourceIDs: [], timeZoneIdentifier: calendar.timeZone.identifier,
                        endDay: old.end.formatted(.iso8601.year().month().day().dateSeparator(.dash)))
                }
                metadata.healthSleep?.isRemoved = true
                old.metadataData = try JSONEncoder().encode(metadata)
            }
        }
        if saveChanges { try context.save() }
    }
}

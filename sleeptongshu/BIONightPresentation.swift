import Foundation

/// Derived display values only. Original measurements and upload data stay intact.
final class BIONightPresentation {
    struct Series {
        let samples: [WearableVital]
        let mean: Double
        var count: Int { samples.count }
        var unit: String { samples.first?.displayUnit ?? "" }
    }
    let series: [VitalKind: Series]
    let available: [VitalKind]

    init(samples: [WearableVital], segments: [SleepSegment]) {
        let ranges = segments.filter { $0.stage.isAsleep }.sorted { $0.start < $1.start }
        let observation = ranges.isEmpty
        var cursor = 0
        var groups: [VitalKind: [WearableVital]] = [:]
        // Walk sorted measurements and sleep intervals once, rather than scanning
        // every interval again for every metric, count, mean and chart redraw.
        for sample in samples.sorted(by: { $0.date < $1.date }) where sample.kind.isVisible {
            if !observation {
                while cursor < ranges.count && ranges[cursor].end <= sample.date { cursor += 1 }
                guard cursor < ranges.count, ranges[cursor].start <= sample.date else { continue }
            }
            groups[sample.kind, default: []].append(sample)
        }
        series = groups.mapValues { values in
            Series(samples: values, mean: values.reduce(0) { $0 + $1.value } / Double(values.count))
        }
        available = VitalKind.allCases.filter { groups[$0] != nil }
    }
}

#if DEBUG
/// Explicit UI-test input, never loaded in ordinary app launches.
enum BIONightPerformanceFixture {
    static func make() -> [SleepPayload] {
        let stages: [SleepStage] = [.deep,.light,.rem,.awake]
        let kinds: [VitalKind] = [.heart,.oxygen,.hrv,.stress]
        return SampleSleepRecords.makeMonth().prefix(7).map { sample in
            var payload = sample.payload
            payload.source = .band
            let duration = payload.end.timeIntervalSince(payload.start)
            let width = duration / 96
            payload.segments = (0..<96).map { index in
                let start = payload.start.addingTimeInterval(Double(index) * width)
                let end = index == 95 ? payload.end : payload.start.addingTimeInterval(Double(index + 1) * width)
                return SleepSegment(stage: stages[index % 4], start: start, end: end)
            }
            var samples: [WearableVital] = []
            for index in 0..<1000 {
                let date = payload.start.addingTimeInterval(Double(index) * duration / 1000)
                samples.append(WearableVital(device: "ui-dense-bio", deviceLabel: "BIO · 界面性能测试示例", date: date,
                    kind: kinds[index % 4], value: Double(60 + index % 20), origin: "界面测试示例 · 非真实数据"))
            }
            payload.metadata = SleepMetadata(externalSource: "BIO · 界面性能测试示例 · 非真实数据",
                bioNight: BIONight(device: "ui-dense-bio", endDay: StepDates.format(payload.end), readAt: .now, samples: samples, sleepInputMinutes: 480))
            return payload
        }
    }
}
#endif

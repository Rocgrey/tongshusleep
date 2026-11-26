import Foundation

/// Compare only this account's earlier, compatible assessments; never include future entries.
struct PSQIComparison {
    let timeline: [PSQIEntry]
    let previous: PSQIEntry?
    let delta: Int?

    init(entry: PSQIEntry, history: [PSQIEntry]) {
        let earlier = history.filter { $0.id != entry.id && $0.algorithm == entry.algorithm && $0.date < entry.date }
            .sorted { $0.date < $1.date }
        timeline = Array((earlier + [entry]).suffix(8))
        previous = earlier.last
        delta = earlier.last.map { entry.result.total - $0.result.total }
    }
}

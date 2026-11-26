import Foundation
import Combine
import CryptoKit

struct PSQIQuestion: Identifiable {
    enum Input { case clock, minutes, hours, frequency, quality, energy }
    let id: String
    let title: String
    let text: String
    let input: Input
    var options: [String] {
        switch input {
        case .frequency: ["没有", "每周不到 1 次", "每周 1–2 次", "每周 3 次或更多"]
        case .quality: ["非常好", "尚好", "较差", "很差"]
        case .energy: ["没有困难", "略有困难", "较困难", "很困难"]
        default: []
        }
    }
}

enum PSQI {
    static let version = "psqi-seven-components-v1"
    static let componentNames = ["主观质量", "入睡耗时", "睡眠时长", "睡眠效率", "睡眠干扰", "助眠药物", "白天状态"]
    static let questions: [PSQIQuestion] = [
        .init(id: "q1", title: "上床时间", text: "近 1 个月，通常几点上床准备睡觉？", input: .clock),
        .init(id: "q2", title: "入睡耗时", text: "从上床到实际睡着，通常需要多少分钟？", input: .minutes),
        .init(id: "q3", title: "起床时间", text: "近 1 个月，通常几点起床？", input: .clock),
        .init(id: "q4", title: "实际睡眠", text: "每晚实际睡着多少小时？不包括躺着没睡着的时间。", input: .hours)
    ] + zip(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"], [
        "无法在 30 分钟内入睡", "半夜或凌晨醒来", "起床上厕所", "呼吸不畅", "咳嗽或大声打鼾",
        "感觉太冷", "感觉太热", "做噩梦", "疼痛不适", "其他原因"
    ]).map { key, reason in
        .init(id: "q5" + key, title: "睡眠干扰", text: "近 1 个月，因为「\(reason)」而睡不好，有多频繁？", input: .frequency)
    } + [
        .init(id: "q6", title: "整体感受", text: "近 1 个月，你觉得自己的整体睡眠质量怎么样？", input: .quality),
        .init(id: "q7", title: "助眠药物", text: "使用药物帮助入睡的频率是多少？不要因为自测结果自行增减药物。", input: .frequency),
        .init(id: "q8", title: "白天困倦", text: "开车、用餐、社交或日常活动时，因困倦难以保持清醒有多频繁？", input: .frequency),
        .init(id: "q9", title: "精力状态", text: "保持足够精力完成事情，有多大困难？", input: .energy)
    ]

    /// Habitual local clock times, not timestamps: overnight bed intervals wrap once.
    /// Chinese wording follows the supplied export; scoring uses seven components.
    static func score(_ answers: [String: Double]) throws -> PSQIResult {
        guard questions.allSatisfy({ answers[$0.id]?.isFinite == true }) else {
            throw APIError.validation("请完成全部 18 项，再查看结果。")
        }
        for question in questions {
            let v = answers[question.id]!
            let valid: Bool
            switch question.input {
            case .clock: valid = (0..<1440).contains(v) && v.rounded() == v
            case .minutes: valid = (0...1440).contains(v)
            case .hours: valid = (0...24).contains(v)
            default: valid = (0...3).contains(v) && v.rounded() == v
            }
            guard valid else { throw APIError.validation("请检查「\(question.title)」的填写内容。") }
        }
        let bed = (Int(answers["q3"]!) - Int(answers["q1"]!) + 1440) % 1440
        let hours = answers["q4"]!
        guard bed > 0, hours * 60 <= Double(bed) + 0.01 else {
            throw APIError.validation("实际睡眠不能长于卧床时间。请核对上床、起床时间和实际睡眠时长；上床和起床不能相同。")
        }
        func combined(_ sum: Int) -> Int { sum == 0 ? 0 : sum <= 2 ? 1 : sum <= 4 ? 2 : 3 }
        let latency = answers["q2"]!
        let latencyPoints = latency <= 15 ? 0 : latency <= 30 ? 1 : latency <= 60 ? 2 : 3
        let efficiency = hours * 60 / Double(bed) * 100
        let disturbances = ["b", "c", "d", "e", "f", "g", "h", "i", "j"].reduce(0) { $0 + Int(answers["q5" + $1]!) }
        let components = [Int(answers["q6"]!), combined(latencyPoints + Int(answers["q5a"]!)),
            hours > 7 ? 0 : hours >= 6 ? 1 : hours >= 5 ? 2 : 3,
            efficiency >= 85 ? 0 : efficiency >= 75 ? 1 : efficiency >= 65 ? 2 : 3,
            disturbances == 0 ? 0 : disturbances <= 9 ? 1 : disturbances <= 18 ? 2 : 3,
            Int(answers["q7"]!), combined(Int(answers["q8"]! + answers["q9"]!))]
        var concerns: [PSQIConcern] = []
        if latency > 30 || answers["q5a"]! >= 2 { concerns.append(.onset) }
        if answers["q5b"]! >= 2 { concerns.append(.waking) }
        if hours < 6 { concerns.append(.short) }
        return PSQIResult(components: components, efficiency: efficiency, hours: hours, concerns: concerns)
    }
}

enum PSQIConcern: String, Codable, CaseIterable {
    case onset, waking, short
    var title: String { switch self { case .onset: "入睡困难倾向"; case .waking: "夜间易醒倾向"; case .short: "睡眠时间偏短" } }
    var suggestion: String {
        switch self {
        case .onset: "固定起床时间；睡前留出安静的放松时间。长时间清醒时，可以离开床做些安静的事，困了再回床。"
        case .waking: "观察咖啡因、酒精、卧室噪声和温度的影响。醒后尽量不看时间、不刷手机，记录容易醒来的情境。"
        case .short: "为睡眠留出充足时间，观察是否因作息、工作或过早醒来而睡得少；不要自行大幅压缩卧床时间。"
        }
    }
}
struct PSQIResult: Codable, Equatable {
    var components: [Int]
    var efficiency: Double
    var hours: Double
    var concerns: [PSQIConcern]
    var total: Int { components.reduce(0, +) }
    var quality: String { total <= 5 ? "整体睡眠质量较好" : "有些睡眠困扰值得关注" }
    var direction: String { concerns.count > 1 ? "多个方面共同影响" : concerns.first?.title ?? "未提示突出的困扰方向" }
}
struct PSQIEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date.now
    var algorithm = PSQI.version
    var answers: [String: Double]
    var result: PSQIResult
}

@MainActor final class PSQIHistory: ObservableObject {
    @Published private(set) var entries: [PSQIEntry] = []
    @Published private(set) var message: String?
    private var scope = ""
    private let directory: URL
    init(directory: URL = .applicationSupportDirectory.appendingPathComponent("PSQIHistory")) { self.directory = directory }
    private var url: URL { directory.appendingPathComponent(scope + ".json") }
    func load(service: String, userID: Int?) {
        entries = []; message = nil
        scope = SHA256.hash(data: Data("\(service)|\(userID.map(String.init) ?? "local")".utf8)).map { String(format: "%02x", $0) }.joined()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let stored = try JSONDecoder().decode([PSQIEntry].self, from: Data(contentsOf: url))
            entries = stored.filter { (try? PSQI.score($0.answers)) == $0.result }.sorted { $0.date > $1.date }
        } catch { message = "本机自测历史暂时无法读取，原文件已保留。" }
    }
    func save(_ answers: [String: Double]) throws -> PSQIEntry {
        guard !scope.isEmpty, message == nil else { throw APIError.validation("自测历史尚未就绪，请重新进入页面。") }
        let entry = PSQIEntry(answers: answers, result: try PSQI.score(answers))
        let next = Array(([entry] + entries).prefix(24))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries = next
        return entry
    }
    func delete(_ id: UUID) throws {
        let next = entries.filter { $0.id != id }
        try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries = next
    }
}

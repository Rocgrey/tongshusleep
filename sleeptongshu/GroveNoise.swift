import Foundation

/// Original procedural textures, explicitly labelled as synthesis rather than field recordings.
struct GroveNoise: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let family: Int
    let softness: Float
    let pulse: Double
    static let library: [Self] = {
        let groups = [
            ["轻柔白噪", "细密沙声", "微风沙沙", "绵绵雨幕", "远处风声", "轻盈气流", "安静风扇", "细雨轻响"],
            ["柔粉噪声", "柔和雨幕", "缓缓海潮", "林间风息", "溪流低语", "夜雨轻落", "柔风拂面", "平静水声"],
            ["低沉棕噪", "深沉风声", "遥远潮汐", "低声雨幕", "沉静水流", "深夜风息", "温和低鸣", "缓慢潮声"]
        ]
        return groups.enumerated().flatMap { family, names in
            names.enumerated().map { index, title in
                Self(id: family * 8 + index, title: title, family: family,
                     softness: Float(index) / 10, pulse: index == 0 ? 0 : Double(index) / 12)
            }
        }
    }()

    // Stable, bounded synthesis runs off the UI thread. Sampling and units are audio only.
    func samples(rate: Int = 22050, seconds: Int = 12) -> [Float] {
        let count = rate * seconds
        guard count > 0, rate > 0 else { return [] }
        var values = [Float](repeating: 0, count: count)
        var seed = UInt64(id + 1) &* 0x123456789
        var slow: Float = 0, medium: Float = 0
        let alpha: Float = family == 2 ? 0.015 + softness * 0.01 : 0.09 + softness * 0.05
        for i in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1
            let white = Float(seed >> 40) / Float(1 << 24) * 2 - 1
            slow += alpha * (white - slow)
            medium += 0.25 * (white - medium)
            let texture = family == 0 ? white * (0.3 - softness * 0.15) : family == 1 ? slow * 0.8 + medium * 0.15 : slow * 1.8
            // Whole cycles keep the envelope seamless at the loop boundary.
            let envelope = 1 - Float(pulse) * Float((1 - cos(2 * .pi * Double(i) / Double(count) * Double(id % 3 + 1))) / 2)
            values[i] = max(-0.8, min(0.8, texture * envelope))
        }
        // Join the tail to the beginning to avoid a click when AVAudioPlayer loops.
        let fade = min(rate / 20, count / 2)
        if fade > 0 {
            for i in 0..<fade {
                let mix = Float(i) / Float(max(1, fade - 1))
                values[count - fade + i] = values[count - fade + i] * (1 - mix) + values[0] * mix
            }
        }
        // Equal perceived starting level across families, while retaining headroom.
        // Brown/pink filtering previously made some presets much quieter than white.
        let rms = sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(count))
        let peak = values.map { abs($0) }.max() ?? 0
        if rms > 0, peak > 0 {
            let gain = Float(min(0.17 / rms, 0.8 / Double(peak)))
            for i in values.indices { values[i] *= gain }
        }
        return values
    }
}

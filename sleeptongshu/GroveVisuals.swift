import SwiftUI

/// Shared decorative surfaces; charts and numbers keep their original semantics.
enum GroveColor: Int, CaseIterable {
    case coral, lavender, mint, honey, sky
    var tint: Color {
        let light: [UInt32] = [0xB84636, 0x7051B2, 0x187566, 0x916010, 0x316EA2]
        let dark: [UInt32] = [0xFFAD9D, 0xCEB6FF, 0x94DBC4, 0xF4D18E, 0x9ACDF8]
        return Color(uiColor: AppAppearance.adaptive(light[rawValue], dark[rawValue]))
    }
    var wash: Color {
        let light: [UInt32] = [0xFBE8E2, 0xEFE8FA, 0xE1F3EB, 0xFCF0CF, 0xE5EFFB]
        let dark: [UInt32] = [0x372729, 0x302A40, 0x21382F, 0x383320, 0x223441]
        return Color(uiColor: AppAppearance.adaptive(light[rawValue], dark[rawValue]))
    }
}

struct GroveSectionBanner: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: GroveColor = .coral
    var body: some View {
        HStack(spacing: SleepPalette.Layout.inset) {
            Image(systemName: symbol).font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical).foregroundStyle(color.tint)
                .frame(width: 66, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(SleepPalette.TypeStyle.heading).foregroundStyle(SleepPalette.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(SleepPalette.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(SleepPalette.Layout.inset)
            .background(color.wash.opacity(0.65), in: RoundedRectangle(cornerRadius: SleepPalette.Layout.radius))
    }
}

struct GroveProgressRings: View {
    let values: [Double]
    var symbol = "leaf.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private let colors: [GroveColor] = [.coral, .lavender, .mint]
    var body: some View {
        ZStack {
            ForEach(0..<min(3, values.count), id: \.self) { index in
                Circle().stroke(colors[index].tint.opacity(0.12), lineWidth: 9)
                    .padding(CGFloat(index) * 15)
                Circle().trim(from: 0, to: appeared ? min(1, max(0, values[index])) : 0)
                    .stroke(colors[index].tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(CGFloat(index) * 15)
            }
            Image(systemName: symbol).font(.title2).foregroundStyle(GroveColor.mint.tint)
        }.frame(width: 116, height: 116).accessibilityHidden(true)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { appeared = true } }
    }
}

extension View {
    func groveWash(_ color: GroveColor) -> some View {
        padding(SleepPalette.Layout.inset).background(color.wash.opacity(0.65), in: RoundedRectangle(cornerRadius: SleepPalette.Layout.radius))
            .overlay { RoundedRectangle(cornerRadius: SleepPalette.Layout.radius).strokeBorder(SleepPalette.line, lineWidth: 0.5).allowsHitTesting(false) }
    }
}

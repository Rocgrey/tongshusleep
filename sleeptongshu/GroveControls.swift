import SwiftUI

// finesse: native product UI; shared 8pt surfaces, tonal depth, interaction-only motion.
struct GroveButtonStyle: ButtonStyle {
    enum Emphasis { case primary, secondary }
    let emphasis: Emphasis
    var color: Color = SleepPalette.teal
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false
    init(_ emphasis: Emphasis, color: Color = SleepPalette.teal) { self.emphasis = emphasis; self.color = color }
    func makeBody(configuration: Configuration) -> some View {
        let accent = configuration.role == .destructive ? GroveColor.coral.tint : color
        let primary = emphasis == .primary
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primary ? SleepPalette.onAccent : accent)
            .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(
                    LinearGradient(colors: primary ? [accent, accent.opacity(scheme == .dark ? 0.94 : 0.96)] : [SleepPalette.surface, accent.opacity(0.08)],
                                   startPoint: hovering ? .top : .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    LinearGradient(colors: [primary ? Color.white.opacity(0.4) : accent.opacity(0.3), accent.opacity(contrast == .increased ? 0.7 : 0.16)], startPoint: .top, endPoint: .bottom),
                    lineWidth: contrast == .increased ? 1.5 : 1 / scale)
            }
            .shadow(color: accent.opacity(enabled ? 0.10 : 0), radius: configuration.isPressed ? 1 : 2, y: 1)
            .shadow(color: accent.opacity(enabled ? 0.12 : 0), radius: configuration.isPressed ? 2 : hovering ? 7 : 4, y: configuration.isPressed ? 1 : 3)
            .opacity(enabled ? 1 : 0.48)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : 1)
            .offset(y: reduceMotion ? 0 : hovering && enabled && !configuration.isPressed ? -2 : 0)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
    }
}

/// Image and row buttons keep their existing layout and color semantics.
struct GrovePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if configuration.role == .destructive { configuration.label.foregroundStyle(GroveColor.coral.tint) }
            else { configuration.label }
        }.contentShape(Rectangle())
            .opacity(enabled ? configuration.isPressed ? 0.84 : 1 : 0.48)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct GroveInputStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(.horizontal, 12).padding(.vertical, 10).groveSurface()
    }
}

private struct GroveSurface: ViewModifier {
    @Environment(\.displayScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(SleepPalette.line, lineWidth: contrast == .increased ? 1.5 : 1 / scale) }
            .shadow(color: SleepPalette.ink.opacity(0.035), radius: 2, y: 1)
            .shadow(color: SleepPalette.ink.opacity(0.025), radius: 6, y: 3)
    }
}
extension View {
    func groveSurface() -> some View { modifier(GroveSurface()) }
}

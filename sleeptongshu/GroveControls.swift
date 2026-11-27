import SwiftUI

// Native Swiss-style controls share the existing palette and retain system focus behavior.
struct GroveButtonStyle: ButtonStyle {
    enum Emphasis { case primary, secondary }
    let emphasis: Emphasis
    var color: Color = SleepPalette.teal
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    init(_ emphasis: Emphasis, color: Color = SleepPalette.teal) { self.emphasis = emphasis; self.color = color }
    func makeBody(configuration: Configuration) -> some View {
        let accent = configuration.role == .destructive ? GroveColor.coral.tint : color
        let primary = emphasis == .primary
        configuration.label
            .font(SleepPalette.TypeStyle.action)
            .foregroundStyle(primary ? SleepPalette.onAccent : accent)
            .padding(.horizontal, SleepPalette.Layout.inset).padding(.vertical, 10).frame(minHeight: SleepPalette.Layout.touch)
            .background {
                RoundedRectangle(cornerRadius: SleepPalette.Layout.radius)
                    .fill(primary ? accent : SleepPalette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SleepPalette.Layout.radius).strokeBorder(
                    focused ? SleepPalette.ink : primary ? accent : SleepPalette.controlLine,
                    lineWidth: focused ? 2 : contrast == .increased ? 1.5 : 1 / scale)
            }
            .shadow(color: SleepPalette.ink.opacity(primary && enabled ? SleepPalette.Interaction.shadowOpacity : 0),
                    radius: configuration.isPressed ? 0 : SleepPalette.Interaction.shadowRadius, y: 1)
            .opacity(enabled ? configuration.isPressed ? SleepPalette.Interaction.pressedOpacity : 1 : SleepPalette.Interaction.disabledOpacity)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? SleepPalette.Interaction.pressedScale : 1)
            .brightness(hovering && enabled ? (scheme == .dark ? 0.04 : -0.025) : 0)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SleepPalette.Interaction.duration), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: SleepPalette.Interaction.duration), value: hovering)
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
            .opacity(enabled ? configuration.isPressed ? SleepPalette.Interaction.pressedOpacity : 1 : SleepPalette.Interaction.disabledOpacity)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? SleepPalette.Interaction.pressedScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: SleepPalette.Interaction.duration), value: configuration.isPressed)
    }
}

struct GroveInputStyle: TextFieldStyle {
    @Environment(\.isFocused) private var focused
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(.horizontal, SleepPalette.Layout.item).padding(.vertical, 10)
            .frame(minHeight: SleepPalette.Layout.touch)
            .background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: SleepPalette.Layout.radius))
            .overlay {
                RoundedRectangle(cornerRadius: SleepPalette.Layout.radius)
                    .strokeBorder(focused ? SleepPalette.teal : SleepPalette.controlLine, lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct GroveSurface: ViewModifier {
    @Environment(\.displayScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(SleepPalette.surface, in: RoundedRectangle(cornerRadius: SleepPalette.Layout.radius))
            .overlay { RoundedRectangle(cornerRadius: SleepPalette.Layout.radius).strokeBorder(SleepPalette.line, lineWidth: contrast == .increased ? 1.5 : 1 / scale).allowsHitTesting(false) }
            .shadow(color: SleepPalette.ink.opacity(SleepPalette.Interaction.shadowOpacity / 2), radius: SleepPalette.Interaction.shadowRadius, y: 1)
    }
}
extension View {
    func groveSurface() -> some View { modifier(GroveSurface()) }
}

import SwiftUI

/// Original, local artwork: a pillow companion and a different scene for each item.
/// Illustrations describe the question, never a preferred answer or estimated score.
struct PSQIQuestionScene {
    let color: GroveColor
    let symbol: String
    let companion: String
    let daylight: Bool

    static func forQuestion(_ id: String) -> Self {
        switch id {
        case "q1": .init(color: .lavender, symbol: "bed.double.fill", companion: "moon.stars.fill", daylight: false)
        case "q2": .init(color: .honey, symbol: "hourglass", companion: "clock.fill", daylight: false)
        case "q3": .init(color: .coral, symbol: "alarm.fill", companion: "sun.max.fill", daylight: true)
        case "q4": .init(color: .sky, symbol: "clock.fill", companion: "moon.fill", daylight: false)
        case "q5a": .init(color: .lavender, symbol: "clock.badge.questionmark", companion: "moon.fill", daylight: false)
        case "q5b": .init(color: .sky, symbol: "moon.zzz.fill", companion: "clock.fill", daylight: false)
        case "q5c": .init(color: .mint, symbol: "door.left.hand.open", companion: "drop.fill", daylight: false)
        case "q5d": .init(color: .sky, symbol: "wind", companion: "leaf.fill", daylight: false)
        case "q5e": .init(color: .honey, symbol: "waveform", companion: "moon.fill", daylight: false)
        case "q5f": .init(color: .sky, symbol: "snowflake", companion: "thermometer.low", daylight: false)
        case "q5g": .init(color: .coral, symbol: "thermometer.high", companion: "fan.fill", daylight: false)
        case "q5h": .init(color: .lavender, symbol: "cloud.moon.fill", companion: "sparkles", daylight: false)
        case "q5i": .init(color: .coral, symbol: "heart.fill", companion: "bandage.fill", daylight: false)
        case "q5j": .init(color: .mint, symbol: "text.bubble.fill", companion: "pencil", daylight: false)
        case "q6": .init(color: .lavender, symbol: "moon.stars.fill", companion: "heart.fill", daylight: false)
        case "q7": .init(color: .mint, symbol: "pills.fill", companion: "list.clipboard.fill", daylight: false)
        case "q8": .init(color: .honey, symbol: "cup.and.saucer.fill", companion: "sun.max.fill", daylight: true)
        default: .init(color: .coral, symbol: "sun.horizon.fill", companion: "leaf.fill", daylight: true)
        }
    }
}

struct PSQIQuestionArtwork: View {
    let questionID: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let scene = PSQIQuestionScene.forQuestion(questionID)
        Canvas { context, size in
            let scale = min(size.width / 320, size.height / 156)
            context.translateBy(x: (size.width - 320 * scale) / 2, y: (size.height - 156 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            drawScene(&context, scene: scene)
        }.frame(maxWidth: .infinity).frame(height: 156)
            .background(scene.color.wash, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("卡通小枕头：" + (PSQI.questions.first { $0.id == questionID }?.title ?? "精力状态"))
            .accessibilityIdentifier("psqiArtwork-" + questionID)
    }

    private func drawScene(_ context: inout GraphicsContext, scene: PSQIQuestionScene) {
        let ink = Color(red: 0.29, green: 0.24, blue: 0.33)
        let pillow = colorScheme == .dark ? Color(red: 0.84, green: 0.83, blue: 0.90) : Color(red: 1, green: 0.98, blue: 0.94)
        let lilac = Color(red: 0.65, green: 0.54, blue: 0.83)
        let blush = Color(red: 0.94, green: 0.62, blue: 0.57)
        func fill(_ rect: CGRect, _ color: Color, radius: CGFloat) {
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
        }
        // A small bedroom window gives the clock and daytime items visual context.
        fill(CGRect(x: 244, y: 20, width: 49, height: 62), scene.color.tint.opacity(0.12), radius: 24)
        context.draw(Text(Image(systemName: scene.daylight ? "sun.max.fill" : "moon.fill"))
            .foregroundColor(scene.daylight ? GroveColor.honey.tint : scene.color.tint).font(.system(size: 20)), at: CGPoint(x: 269, y: 44))
        var sill = Path(); sill.move(to: CGPoint(x: 241, y: 84)); sill.addLine(to: CGPoint(x: 296, y: 84))
        context.stroke(sill, with: .color(scene.color.tint.opacity(0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        // Ground and feet anchor the companion, rather than floating decorative shapes.
        context.fill(Path(ellipseIn: CGRect(x: 79, y: 134, width: 152, height: 9)), with: .color(scene.color.tint.opacity(0.1)))
        fill(CGRect(x: 115, y: 120, width: 20, height: 19), blush, radius: 9)
        fill(CGRect(x: 174, y: 120, width: 20, height: 19), blush, radius: 9)
        var leftArm = Path(); leftArm.move(to: CGPoint(x: 103, y: 83)); leftArm.addQuadCurve(to: CGPoint(x: 80, y: 100), control: CGPoint(x: 82, y: 78))
        context.stroke(leftArm, with: .color(pillow), style: StrokeStyle(lineWidth: 13, lineCap: .round))
        var rightArm = Path(); rightArm.move(to: CGPoint(x: 207, y: 82)); rightArm.addQuadCurve(to: CGPoint(x: 224, y: 68), control: CGPoint(x: 225, y: 88))
        context.stroke(rightArm, with: .color(pillow), style: StrokeStyle(lineWidth: 13, lineCap: .round))
        let body = Path(roundedRect: CGRect(x: 99, y: 42, width: 113, height: 88), cornerRadius: 28)
        context.fill(body, with: .color(pillow))
        context.stroke(body, with: .color(lilac.opacity(0.38)), lineWidth: 2)
        let seam = Path(roundedRect: CGRect(x: 106, y: 49, width: 99, height: 74), cornerRadius: 23)
        context.stroke(seam, with: .color(lilac.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        // Friendly, constant expression avoids suggesting which response to choose.
        for x in [CGFloat(134), CGFloat(177)] {
            var eye = Path(); eye.move(to: CGPoint(x: x - 5, y: 78)); eye.addQuadCurve(to: CGPoint(x: x + 5, y: 78), control: CGPoint(x: x, y: 84))
            context.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        context.fill(Path(ellipseIn: CGRect(x: 118, y: 86, width: 17, height: 9)), with: .color(blush.opacity(0.65)))
        context.fill(Path(ellipseIn: CGRect(x: 177, y: 86, width: 17, height: 9)), with: .color(blush.opacity(0.65)))
        var smile = Path(); smile.move(to: CGPoint(x: 148, y: 91)); smile.addQuadCurve(to: CGPoint(x: 162, y: 91), control: CGPoint(x: 155, y: 101))
        context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        // Soft sleeping cap, with a stitched brim and pompom.
        var hat = Path(); hat.move(to: CGPoint(x: 112, y: 45)); hat.addQuadCurve(to: CGPoint(x: 173, y: 36), control: CGPoint(x: 132, y: -4))
        hat.addQuadCurve(to: CGPoint(x: 182, y: 21), control: CGPoint(x: 182, y: 41)); hat.addQuadCurve(to: CGPoint(x: 155, y: 53), control: CGPoint(x: 165, y: 12)); hat.closeSubpath()
        context.fill(hat, with: .color(lilac))
        fill(CGRect(x: 108, y: 42, width: 53, height: 12), Color(red: 0.86, green: 0.81, blue: 0.95), radius: 6)
        context.fill(Path(ellipseIn: CGRect(x: 175, y: 14, width: 14, height: 14)), with: .color(pillow))
        // Unique question prop, drawn using system artwork within the custom scene.
        let propRect = CGRect(x: 29, y: 57, width: 58, height: 61)
        fill(propRect, scene.color.tint.opacity(0.1), radius: 16)
        context.draw(Text(Image(systemName: scene.symbol)).font(.system(size: 29, weight: .medium)).foregroundColor(scene.color.tint), at: CGPoint(x: 58, y: 87))
        context.draw(Text(Image(systemName: scene.companion)).font(.system(size: 19, weight: .medium)).foregroundColor(GroveColor.coral.tint), at: CGPoint(x: 225, y: 113))
    }
}

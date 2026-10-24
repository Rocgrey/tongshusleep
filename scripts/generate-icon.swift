import AppKit
import Foundation

// Render at a fixed pixel resolution; AppKit point sizes depend on the display.
let side = 1024
let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current?.imageInterpolation = .high

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func gradient(_ colors: [NSColor], in path: NSBezierPath, angle: CGFloat) {
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}

let canvas = NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side))
gradient([color(0xD8E8F9), color(0xF2F7FD), color(0xEAF6F9)], in: canvas, angle: 65)

// A broad crescent silhouette stays readable at the smallest home-screen sizes.
let moon = NSBezierPath()
moon.move(to: NSPoint(x: 582, y: 823))
moon.curve(to: NSPoint(x: 285, y: 717),
           controlPoint1: NSPoint(x: 472, y: 858), controlPoint2: NSPoint(x: 344, y: 806))
moon.curve(to: NSPoint(x: 300, y: 410),
           controlPoint1: NSPoint(x: 216, y: 614), controlPoint2: NSPoint(x: 220, y: 493))
moon.curve(to: NSPoint(x: 605, y: 347),
           controlPoint1: NSPoint(x: 376, y: 331), controlPoint2: NSPoint(x: 508, y: 307))
moon.curve(to: NSPoint(x: 763, y: 532),
           controlPoint1: NSPoint(x: 689, y: 382), controlPoint2: NSPoint(x: 747, y: 449))
moon.curve(to: NSPoint(x: 714, y: 542),
           controlPoint1: NSPoint(x: 767, y: 554), controlPoint2: NSPoint(x: 735, y: 553))
moon.curve(to: NSPoint(x: 474, y: 585),
           controlPoint1: NSPoint(x: 627, y: 495), controlPoint2: NSPoint(x: 534, y: 514))
moon.curve(to: NSPoint(x: 469, y: 752),
           controlPoint1: NSPoint(x: 430, y: 636), controlPoint2: NSPoint(x: 432, y: 706))
moon.curve(to: NSPoint(x: 582, y: 793),
           controlPoint1: NSPoint(x: 493, y: 785), controlPoint2: NSPoint(x: 538, y: 804))
moon.curve(to: NSPoint(x: 582, y: 823),
           controlPoint1: NSPoint(x: 609, y: 787), controlPoint2: NSPoint(x: 608, y: 813))
moon.close()

NSGraphicsContext.saveGraphicsState()
let moonShadow = NSShadow()
moonShadow.shadowColor = color(0xA77942, alpha: 0.16)
moonShadow.shadowBlurRadius = 24
moonShadow.shadowOffset = NSSize(width: 0, height: -16)
moonShadow.set()
gradient([color(0xECA74F), color(0xFFD17D), color(0xFFE8B0)], in: moon, angle: 68)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
moon.addClip()
let moonHighlight = NSBezierPath()
moonHighlight.move(to: NSPoint(x: 568, y: 805))
moonHighlight.curve(to: NSPoint(x: 286, y: 570),
                    controlPoint1: NSPoint(x: 404, y: 831), controlPoint2: NSPoint(x: 266, y: 723))
moonHighlight.lineWidth = 7
moonHighlight.lineCapStyle = .round
color(0xFFF5D9, alpha: 0.7).setStroke()
moonHighlight.stroke()
NSGraphicsContext.restoreGraphicsState()

func sparkle(center: NSPoint, radius: CGFloat, fill: NSColor) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: center.x, y: center.y + radius))
    p.curve(to: NSPoint(x: center.x + radius * 0.8, y: center.y),
            controlPoint1: NSPoint(x: center.x + radius * 0.17, y: center.y + radius * 0.24),
            controlPoint2: NSPoint(x: center.x + radius * 0.24, y: center.y + radius * 0.15))
    p.curve(to: NSPoint(x: center.x, y: center.y - radius),
            controlPoint1: NSPoint(x: center.x + radius * 0.24, y: center.y - radius * 0.15),
            controlPoint2: NSPoint(x: center.x + radius * 0.17, y: center.y - radius * 0.24))
    p.curve(to: NSPoint(x: center.x - radius * 0.8, y: center.y),
            controlPoint1: NSPoint(x: center.x - radius * 0.17, y: center.y - radius * 0.24),
            controlPoint2: NSPoint(x: center.x - radius * 0.24, y: center.y - radius * 0.15))
    p.curve(to: NSPoint(x: center.x, y: center.y + radius),
            controlPoint1: NSPoint(x: center.x - radius * 0.24, y: center.y + radius * 0.15),
            controlPoint2: NSPoint(x: center.x - radius * 0.17, y: center.y + radius * 0.24))
    p.close()
    fill.setFill()
    p.fill()
}

sparkle(center: NSPoint(x: 735, y: 751), radius: 49, fill: color(0x6C82BD))
sparkle(center: NSPoint(x: 810, y: 647), radius: 23, fill: color(0xA4B6D8))

// Two simple flowing ribbons suggest sleep cycles without a medical waveform.
let backWave = NSBezierPath()
backWave.move(to: NSPoint(x: 190, y: 355))
backWave.curve(to: NSPoint(x: 498, y: 334),
               controlPoint1: NSPoint(x: 309, y: 413), controlPoint2: NSPoint(x: 367, y: 320))
backWave.curve(to: NSPoint(x: 837, y: 376),
               controlPoint1: NSPoint(x: 630, y: 348), controlPoint2: NSPoint(x: 720, y: 431))
backWave.curve(to: NSPoint(x: 834, y: 327),
               controlPoint1: NSPoint(x: 863, y: 365), controlPoint2: NSPoint(x: 856, y: 341))
backWave.curve(to: NSPoint(x: 499, y: 277),
               controlPoint1: NSPoint(x: 695, y: 359), controlPoint2: NSPoint(x: 620, y: 272))
backWave.curve(to: NSPoint(x: 190, y: 307),
               controlPoint1: NSPoint(x: 354, y: 274), controlPoint2: NSPoint(x: 279, y: 363))
backWave.curve(to: NSPoint(x: 190, y: 355),
               controlPoint1: NSPoint(x: 163, y: 293), controlPoint2: NSPoint(x: 161, y: 341))
backWave.close()
gradient([color(0x8CCBC6), color(0xC1E2DD)], in: backWave, angle: 12)

let frontWave = NSBezierPath()
frontWave.move(to: NSPoint(x: 190, y: 293))
frontWave.curve(to: NSPoint(x: 487, y: 263),
                controlPoint1: NSPoint(x: 286, y: 330), controlPoint2: NSPoint(x: 363, y: 245))
frontWave.curve(to: NSPoint(x: 820, y: 306),
                controlPoint1: NSPoint(x: 619, y: 279), controlPoint2: NSPoint(x: 715, y: 353))
frontWave.curve(to: NSPoint(x: 827, y: 247),
                controlPoint1: NSPoint(x: 850, y: 293), controlPoint2: NSPoint(x: 854, y: 263))
frontWave.curve(to: NSPoint(x: 487, y: 206),
                controlPoint1: NSPoint(x: 700, y: 291), controlPoint2: NSPoint(x: 615, y: 197))
frontWave.curve(to: NSPoint(x: 193, y: 238),
                controlPoint1: NSPoint(x: 353, y: 191), controlPoint2: NSPoint(x: 289, y: 285))
frontWave.curve(to: NSPoint(x: 190, y: 293),
                controlPoint1: NSPoint(x: 162, y: 222), controlPoint2: NSPoint(x: 159, y: 277))
frontWave.close()

NSGraphicsContext.saveGraphicsState()
let waveShadow = NSShadow()
waveShadow.shadowColor = color(0x397F89, alpha: 0.12)
waveShadow.shadowBlurRadius = 14
waveShadow.shadowOffset = NSSize(width: 0, height: -10)
waveShadow.set()
gradient([color(0x409B9E), color(0x69C5BC), color(0xA6DFCD)], in: frontWave, angle: 20)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

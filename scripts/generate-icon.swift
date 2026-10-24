import AppKit
import Foundation

let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.34, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.88, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 240, y: 295, width: 520, height: 520)).fill()
NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.34, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 375, y: 440, width: 420, height: 420)).fill()
let line = NSBezierPath()
line.move(to: NSPoint(x: 225, y: 235))
line.curve(to: NSPoint(x: 810, y: 255), controlPoint1: NSPoint(x: 430, y: 145), controlPoint2: NSPoint(x: 580, y: 350))
line.lineWidth = 32
line.lineCapStyle = .round
NSColor(calibratedRed: 0.53, green: 0.81, blue: 0.69, alpha: 1).setStroke()
line.stroke()
NSColor(calibratedRed: 0.95, green: 0.76, blue: 0.45, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 705, y: 660, width: 60, height: 60)).fill()
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

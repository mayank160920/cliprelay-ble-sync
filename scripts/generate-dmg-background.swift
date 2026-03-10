#!/usr/bin/env swift
// Generates the DMG background images for ClipRelay's drag-to-install layout.
// Usage: swift scripts/generate-dmg-background.swift
// Output: design/dmg-background.png, design/dmg-background@2x.png

import AppKit

let brandDark  = NSColor(red: 0x08/255.0, green: 0x2A/255.0, blue: 0x26/255.0, alpha: 1)
let accentCyan = NSColor(red: 0x00/255.0, green: 0xFF/255.0, blue: 0xD5/255.0, alpha: 1)

func generateBackground(width: Int, height: Int, scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    let w = CGFloat(width) / scale
    let h = CGFloat(height) / scale

    // Background fill
    brandDark.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: w, height: h))

    // Icon positions (matching create-dmg --icon and --app-drop-link coords)
    // App icon at x=165, Applications at x=495, both at y=175 (from top)
    // In flipped coords: y from bottom = 400 - 175 = 225
    let leftX: CGFloat = 165
    let rightX: CGFloat = 495
    let iconY: CGFloat = h - 175  // flip y

    // Draw curved arrow from left icon area to right icon area
    let arrowPath = NSBezierPath()
    let startX = leftX + 50   // right edge of left icon area
    let endX = rightX - 50     // left edge of right icon area
    let startY = iconY + 20
    let endY = iconY + 20

    // Control points for a gentle upward arc
    let cp1 = NSPoint(x: startX + 60, y: startY + 55)
    let cp2 = NSPoint(x: endX - 60, y: endY + 55)

    arrowPath.move(to: NSPoint(x: startX, y: startY))
    arrowPath.curve(to: NSPoint(x: endX, y: endY), controlPoint1: cp1, controlPoint2: cp2)

    accentCyan.withAlphaComponent(0.35).setStroke()
    arrowPath.lineWidth = 3.0 * scale
    arrowPath.lineCapStyle = .round
    arrowPath.stroke()

    // Arrowhead
    let arrowSize: CGFloat = 14
    let arrowHead = NSBezierPath()
    // Tangent at end of curve points roughly right and slightly down
    let tx: CGFloat = 1.0
    let ty: CGFloat = -0.3
    let len = sqrt(tx * tx + ty * ty)
    let nx = tx / len
    let ny = ty / len
    // Perpendicular
    let px = -ny
    let py = nx

    let tip = NSPoint(x: endX + 4, y: endY)
    let back1 = NSPoint(x: tip.x - arrowSize * nx + arrowSize * 0.5 * px,
                         y: tip.y - arrowSize * ny + arrowSize * 0.5 * py)
    let back2 = NSPoint(x: tip.x - arrowSize * nx - arrowSize * 0.5 * px,
                         y: tip.y - arrowSize * ny - arrowSize * 0.5 * py)

    arrowHead.move(to: tip)
    arrowHead.line(to: back1)
    arrowHead.line(to: back2)
    arrowHead.close()
    accentCyan.withAlphaComponent(0.35).setFill()
    arrowHead.fill()

    // "Drag to install" text
    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.6)
    ]
    let text = "Drag to install" as NSString
    let textSize = text.size(withAttributes: textAttrs)
    let textX = (w - textSize.width) / 2
    let textY = iconY - 60  // below arrow
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Determine output directory
let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0])
let rootDir = scriptPath.deletingLastPathComponent().deletingLastPathComponent()
let designDir = rootDir.appendingPathComponent("design")

// Generate 1x (660x400) and 2x (1320x800)
let rep1x = generateBackground(width: 660, height: 400, scale: 1)
let rep2x = generateBackground(width: 1320, height: 800, scale: 2)

let png1x = rep1x.representation(using: .png, properties: [:])!
let png2x = rep2x.representation(using: .png, properties: [:])!

try png1x.write(to: designDir.appendingPathComponent("dmg-background.png"))
try png2x.write(to: designDir.appendingPathComponent("dmg-background@2x.png"))

print("Generated design/dmg-background.png (660x400)")
print("Generated design/dmg-background@2x.png (1320x800)")

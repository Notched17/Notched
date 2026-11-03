// SPDX-License-Identifier: GPL-3.0-or-later
// Renders the app icon into App/Assets.xcassets/AppIcon.appiconset.
//
// The idea: the screen's top edge with the island hanging from it, as on a
// notched MacBook, playing something. The island is the black shape that
// flares into the top edge (the notch's concave shoulders), with album art on
// one side and a waveform on the other, and the cover's colour glowing out of
// it, as it does on the Now Playing page.
//
// The artwork is full-bleed: macOS 26 applies the rounded-square mask itself
// (artwork with its own corners and padding gets a grey "legacy" frame).
// Run from the repo root: swift scripts/make-app-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// A soft glow: a radial gradient from `inner` at the centre to clear at the edge, squashed to an ellipse.
func glow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, squash: CGFloat = 1, _ colors: [(CGFloat, CGColor)]) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: squash)
    ctx.drawRadialGradient(gradient(colors), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
    // Night: near-black navy at the top into deep indigo.
    ctx.drawLinearGradient(gradient([(0, color(0x0A0A1C)), (0.55, color(0x14103A)), (1, color(0x241552))]),
                           start: CGPoint(x: 0, y: canvas), end: CGPoint(x: 0, y: 0), options: [])

    // The cover's colour, spilling out of the island: pink, violet, and a warm edge.
    glow(ctx, center: CGPoint(x: 512, y: 470), radius: 720, squash: 0.80, [
        (0, color(0xFF3D7F, 0.62)), (0.35, color(0xB43CFF, 0.34)), (0.7, color(0x4B3CFF, 0.14)), (1, color(0x4B3CFF, 0))])
    glow(ctx, center: CGPoint(x: 730, y: 420), radius: 440, squash: 0.8, [
        (0, color(0xFFA24A, 0.42)), (0.5, color(0xFF5E7A, 0.16)), (1, color(0xFF5E7A, 0))])
    glow(ctx, center: CGPoint(x: 290, y: 400), radius: 380, squash: 0.8, [
        (0, color(0x3CD9FF, 0.22)), (1, color(0x3CD9FF, 0))])

    // The island: a black shape hanging from the top edge, its top corners flaring into it.
    let left: CGFloat = 132, right: CGFloat = 892, bottom: CGFloat = 612, radius: CGFloat = 160, shoulder: CGFloat = 72
    let island = CGMutablePath()
    island.move(to: CGPoint(x: left, y: canvas))
    island.addLine(to: CGPoint(x: left, y: bottom + radius))
    island.addArc(center: CGPoint(x: left + radius, y: bottom + radius), radius: radius, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
    island.addLine(to: CGPoint(x: right - radius, y: bottom))
    island.addArc(center: CGPoint(x: right - radius, y: bottom + radius), radius: radius, startAngle: 1.5 * .pi, endAngle: 0, clockwise: false)
    island.addLine(to: CGPoint(x: right, y: canvas))
    island.closeSubpath()
    // Concave shoulders where it meets the top edge.
    for (edge, sign) in [(left, CGFloat(-1)), (right, CGFloat(1))] {
        let shoulderPath = CGMutablePath()
        let centre = CGPoint(x: edge + sign * shoulder, y: canvas - shoulder)
        shoulderPath.move(to: CGPoint(x: edge, y: canvas - shoulder))
        shoulderPath.addLine(to: CGPoint(x: edge, y: canvas))
        shoulderPath.addLine(to: CGPoint(x: edge + sign * shoulder, y: canvas))
        shoulderPath.addArc(center: centre, radius: shoulder, startAngle: .pi / 2, endAngle: sign < 0 ? 0 : .pi, clockwise: sign < 0)
        shoulderPath.closeSubpath()
        island.addPath(shoulderPath)
    }

    // A deep shadow under the island lifts it off the glow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: color(0x000000, 0.65))
    ctx.setFillColor(color(0x000000))
    ctx.addPath(island)
    ctx.fillPath()
    ctx.restoreGState()
    // The island itself: black with a faint sheen, so it is not a flat hole.
    ctx.saveGState()
    ctx.addPath(island)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0x000000)), (0.6, color(0x050508)), (1, color(0x14141C))]),
                           start: CGPoint(x: 0, y: canvas), end: CGPoint(x: 0, y: bottom), options: [])
    // A thin light along the bottom edge, as on glass.
    ctx.setStrokeColor(color(0xFFFFFF, 0.20))
    ctx.setLineWidth(5)
    ctx.addPath(island)
    ctx.strokePath()
    ctx.restoreGState()

    // Content: album art on the left, a waveform on the right, the camera housing's room between.
    let midY: CGFloat = 808
    let art = CGRect(x: left + 70, y: midY - 92, width: 184, height: 184)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xFFB347)), (0.5, color(0xFF4F8B)), (1, color(0x7B3CFF))]),
                           start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
    // A little disc on the cover, so it reads as a record sleeve.
    ctx.setFillColor(color(0x000000, 0.30))
    ctx.fillEllipse(in: CGRect(x: art.midX - 50, y: art.midY - 50, width: 100, height: 100))
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.fillEllipse(in: CGRect(x: art.midX - 14, y: art.midY - 14, width: 28, height: 28))
    ctx.restoreGState()

    let heights: [CGFloat] = [92, 168, 120, 196, 108]
    let barWidth: CGFloat = 36, gap: CGFloat = 22
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = right - 70 - total
    for height in heights {
        let bar = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF)), (1, color(0xFFC2DA))]),
                               start: CGPoint(x: 0, y: bar.maxY), end: CGPoint(x: 0, y: bar.minY), options: [])
        ctx.restoreGState()
        x += barWidth + gap
    }

    // A small floating bubble under the island, the way a second activity sits beside it.
    let bubble = CGRect(x: 650, y: 330, width: 200, height: 200)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x000000, 0.5))
    ctx.setFillColor(color(0x000000))
    ctx.fillEllipse(in: bubble)
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.16))
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: bubble.insetBy(dx: 2, dy: 2))
    // Its content: a small ring, like a timer.
    ctx.setStrokeColor(color(0x5CE0A0))
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: bubble.midX, y: bubble.midY), radius: 52, startAngle: .pi / 2, endAngle: -.pi * 0.35, clockwise: true)
    ctx.strokePath()
}

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    draw(NSGraphicsContext.current!.cgContext)
    return true
}

let dir = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icon sizes")

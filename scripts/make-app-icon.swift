// SPDX-License-Identifier: GPL-3.0-or-later
// Writes App/AppIcon.icon, the macOS 26 layered icon (an Icon Composer document).
//
// The idea, as small as it gets: the black island hangs from the top edge of
// the screen (the notch's concave shoulders), with one white symbol in it, on
// one flat warm-white field. Black, white and one off-white: no gradients, no
// colour, no second shape.
//
// Following Apple's icon guidance (HIG "App icons", WWDC25 "Create icons with
// Icon Composer"): the layers are flat, opaque and unmasked, 1024 pt, with no
// baked-in glass, shadow, glow or sheen. The system draws the squircle, the
// Liquid Glass highlights and the dark / clear / tinted looks from these layers.
//
// Run from the repo root: swift scripts/make-app-icon.swift
// Preview:  ictool App/AppIcon.icon --export-image --output-file /tmp/icon.png \
//             --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// A transparent 1024 x 1024 bitmap; `draw` paints one layer into it.
func writeLayer(_ name: String, to dir: URL, _ draw: (CGContext) -> Void) throws {
    let pixels = Int(canvas)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
}

// Geometry, in 1024 pt (origin bottom-left, like Core Graphics).
let left: CGFloat = 156, right: CGFloat = 868, bottom: CGFloat = 400, radius: CGFloat = 214, shoulder: CGFloat = 72
let midY: CGFloat = 706

func islandPath() -> CGPath {
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
    return island
}

let package = URL(fileURLWithPath: "App/AppIcon.icon")
let assets = package.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: package)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// Layer 1: the island. Pure black, nothing else.
try writeLayer("island.png", to: assets) { ctx in
    ctx.setFillColor(color(0x000000))
    ctx.addPath(islandPath())
    ctx.fillPath()
}

// Layer 2: the one symbol, three white level bars, centred in the island.
try writeLayer("symbol.png", to: assets) { ctx in
    let heights: [CGFloat] = [124, 224, 168]
    let barWidth: CGFloat = 60, gap: CGFloat = 40
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (left + right) / 2 - total / 2
    ctx.setFillColor(color(0xFFFFFF))
    for height in heights {
        let bar = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }
}

// The document. One flat warm-white fill; the symbol group sits above the
// island group (groups are listed top first).
let document: [String: Any] = [
    "fill": ["solid": "srgb:0.96863,0.96471,0.95294,1.00000"],
    "groups": [
        [
            "layers": [["image-name": "symbol.png", "name": "symbol", "glass": false]],
            "shadow": ["kind": "none", "opacity": 0.0],
            "translucency": ["enabled": false, "value": 0.0],
        ],
        [
            "layers": [["image-name": "island.png", "name": "island", "glass": true]],
            "shadow": ["kind": "neutral", "opacity": 0.35],
            "translucency": ["enabled": false, "value": 0.0],
        ],
    ],
    "supported-platforms": ["squares": "shared"],
]
try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    .write(to: package.appendingPathComponent("icon.json"))
print("wrote \(package.path) with 2 layers")

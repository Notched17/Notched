// SPDX-License-Identifier: GPL-3.0-or-later
// Renders the placeholder app icon into App/Assets.xcassets/AppIcon.appiconset.
// The artwork is full-bleed: macOS 26 applies the rounded-square mask itself
// (artwork with its own corners and padding gets a grey "legacy" frame).
// Run: swift scripts/make-placeholder-icon.swift
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    let body = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    NSGradient(colors: [NSColor(white: 0.32, alpha: 1), NSColor(white: 0.10, alpha: 1)])!
        .draw(in: body, angle: -90)
    // The island: a black capsule near the top, like the notch on a screen.
    let island = NSRect(x: canvas / 2 - 260, y: canvas - 190 - 170, width: 520, height: 170)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 85, yRadius: 85).fill()
    // A small white dot and bar suggest live content.
    NSColor(white: 1, alpha: 0.92).setFill()
    NSBezierPath(ovalIn: NSRect(x: island.minX + 52, y: island.midY - 34, width: 68, height: 68)).fill()
    NSBezierPath(roundedRect: NSRect(x: island.maxX - 200, y: island.midY - 16, width: 148, height: 32), xRadius: 16, yRadius: 16).fill()
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

// SPDX-License-Identifier: GPL-3.0-or-later
// Renders the placeholder app icon (a dark squircle with a black island) into
// App/Assets.xcassets/AppIcon.appiconset. Run: swift scripts/make-placeholder-icon.swift
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    let inset: CGFloat = 100
    let body = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(white: 0.30, alpha: 1), NSColor(white: 0.10, alpha: 1)])!
        .draw(in: squircle, angle: 90)
    // The island: a black capsule hanging from the top edge of the "screen".
    let island = NSRect(x: canvas / 2 - 230, y: body.maxY - 70 - 150, width: 460, height: 150)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 75, yRadius: 75).fill()
    // A small white dot and bar suggest live content.
    NSColor(white: 1, alpha: 0.92).setFill()
    NSBezierPath(ovalIn: NSRect(x: island.minX + 45, y: island.midY - 30, width: 60, height: 60)).fill()
    NSBezierPath(roundedRect: NSRect(x: island.maxX - 175, y: island.midY - 14, width: 130, height: 28), xRadius: 14, yRadius: 14).fill()
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

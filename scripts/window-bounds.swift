// SPDX-License-Identifier: GPL-3.0-or-later
// Prints the on-screen windows owned by DynamicNotch with their bounds in
// AppKit (bottom-left origin) coordinates. Window bounds need no Screen
// Recording permission. Run: swift scripts/window-bounds.swift
import AppKit

let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var found = 0
for window in info where (window[kCGWindowOwnerName as String] as? String) == "DynamicNotch" {
    guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
          let cg = CGRect(dictionaryRepresentation: dict) else { continue }
    // Convert from Core Graphics (top-left origin) to AppKit (bottom-left origin).
    let appKit = CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    print("window \(window[kCGWindowNumber as String] ?? "?") layer \(layer): \(NSStringFromRect(appKit))")
    found += 1
}
if found == 0 { print("no DynamicNotch windows on screen") }

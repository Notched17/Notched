// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An 8-bit sRGB colour and the text forms the colour picker copies (#55).
///
/// The system eyedropper returns the screen's colour space (usually Display
/// P3). The web and design tools want sRGB, so the shell converts first and
/// this type only ever holds sRGB.
struct ColorValue: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From unit-range sRGB components. Components outside 0...1 (a P3 colour
    /// that sRGB can't hold) are clamped, and `outsideGamut` says so.
    static func fromUnit(red: Double, green: Double, blue: Double) -> (value: ColorValue, outsideGamut: Bool) {
        let tolerance = 0.002
        let outside = [red, green, blue].contains { $0 < -tolerance || $0 > 1 + tolerance }
        func byte(_ component: Double) -> UInt8 {
            guard component.isFinite else { return 0 }
            return UInt8((min(max(component, 0), 1) * 255).rounded())
        }
        return (ColorValue(red: byte(red), green: byte(green), blue: byte(blue)), outside)
    }

    /// Reads `#RRGGBB`, `RRGGBB` or the short `#RGB`, in either case.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let number = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(number >> 16 & 0xFF), green: UInt8(number >> 8 & 0xFF), blue: UInt8(number & 0xFF))
    }

    // MARK: Text forms

    /// `#3A7BFF`
    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// `rgb(58, 123, 255)`
    var rgbText: String {
        "rgb(\(red), \(green), \(blue))"
    }

    /// Hue in degrees (0..<360), saturation and lightness in percent.
    var hsl: (hue: Int, saturation: Int, lightness: Int) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let delta = high - low
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch high {
        case r: hue = (g - b) / delta + (g < b ? 6 : 0)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        return (Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }

    /// `hsl(219, 100%, 61%)`
    var hslText: String {
        let (h, s, l) = hsl
        return "hsl(\(h), \(s)%, \(l)%)"
    }

    /// The same colour with white or black text readable on it.
    var prefersDarkText: Bool {
        let luminance = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        return luminance > 150
    }
}

/// The text forms the panel offers to copy.
enum ColorFormat: String, CaseIterable, Sendable {
    case hex = "HEX"
    case rgb = "RGB"
    case hsl = "HSL"

    func text(for color: ColorValue) -> String {
        switch self {
        case .hex: color.hex
        case .rgb: color.rgbText
        case .hsl: color.hslText
        }
    }
}

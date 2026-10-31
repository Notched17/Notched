// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The colour picker's text forms (#55).
@Suite("ColorValue")
struct ColorValueTests {
    @Test("HEX is upper case, zero padded and has a hash")
    func hexForm() {
        #expect(ColorValue(red: 58, green: 123, blue: 255).hex == "#3A7BFF")
        #expect(ColorValue(red: 0, green: 5, blue: 10).hex == "#00050A")
    }

    @Test("RGB reads like CSS")
    func rgbForm() {
        #expect(ColorValue(red: 58, green: 123, blue: 255).rgbText == "rgb(58, 123, 255)")
    }

    @Test("HSL for known colours", arguments: [
        (ColorValue(red: 255, green: 0, blue: 0), "hsl(0, 100%, 50%)"),
        (ColorValue(red: 0, green: 255, blue: 0), "hsl(120, 100%, 50%)"),
        (ColorValue(red: 0, green: 0, blue: 255), "hsl(240, 100%, 50%)"),
        (ColorValue(red: 255, green: 255, blue: 255), "hsl(0, 0%, 100%)"),
        (ColorValue(red: 0, green: 0, blue: 0), "hsl(0, 0%, 0%)"),
        (ColorValue(red: 128, green: 128, blue: 128), "hsl(0, 0%, 50%)"),
        (ColorValue(red: 58, green: 123, blue: 255), "hsl(220, 100%, 61%)"),
    ])
    func hslForm(color: ColorValue, expected: String) {
        #expect(color.hslText == expected)
    }

    @Test("A hue that rounds up to 360° reads as 0°, never 360")
    func hueWraps() {
        // 359.76° rounds to 360, which must wrap.
        #expect(ColorValue(red: 255, green: 0, blue: 1).hsl.hue == 0)
        #expect(ColorValue(red: 255, green: 0, blue: 40).hsl.hue == 351)
    }

    @Test("HEX parses with or without the hash, in either case, and the short form")
    func hexParsing() {
        let expected = ColorValue(red: 58, green: 123, blue: 255)
        #expect(ColorValue(hex: "#3A7BFF") == expected)
        #expect(ColorValue(hex: "3a7bff") == expected)
        #expect(ColorValue(hex: "  #3a7bff ") == expected)
        #expect(ColorValue(hex: "#fa0") == ColorValue(red: 255, green: 170, blue: 0))
    }

    @Test("Bad HEX is rejected", arguments: ["", "#", "#12", "#12345", "#1234567", "GGGGGG", "#12 456"])
    func badHex(text: String) {
        #expect(ColorValue(hex: text) == nil)
    }

    @Test("HEX round-trips for every channel value")
    func hexRoundTrip() {
        for value in stride(from: 0, through: 255, by: 5) {
            let color = ColorValue(red: UInt8(value), green: UInt8(255 - value), blue: UInt8(value / 2))
            #expect(ColorValue(hex: color.hex) == color)
        }
    }

    @Test("Unit components round to the nearest byte")
    func fromUnit() {
        let (color, outside) = ColorValue.fromUnit(red: 0.5, green: 0, blue: 1)
        #expect(color == ColorValue(red: 128, green: 0, blue: 255))
        #expect(!outside)
    }

    @Test("A colour sRGB can't hold is clamped and flagged")
    func outOfGamut() {
        let (color, outside) = ColorValue.fromUnit(red: 1.08, green: -0.04, blue: 0.5)
        #expect(color == ColorValue(red: 255, green: 0, blue: 128))
        #expect(outside)
    }

    @Test("Rounding noise at the edges isn't called out of gamut")
    func edgeNoise() {
        let (_, outside) = ColorValue.fromUnit(red: 1.0005, green: -0.0005, blue: 0.5)
        #expect(!outside)
    }

    @Test("Components that aren't numbers become 0 instead of crashing")
    func nonFinite() {
        let (color, _) = ColorValue.fromUnit(red: .nan, green: .infinity, blue: -.infinity)
        #expect(color == ColorValue(red: 0, green: 0, blue: 0))
    }

    @Test("Each format copies its own text")
    func formats() {
        let color = ColorValue(red: 58, green: 123, blue: 255)
        #expect(ColorFormat.hex.text(for: color) == "#3A7BFF")
        #expect(ColorFormat.rgb.text(for: color) == "rgb(58, 123, 255)")
        #expect(ColorFormat.hsl.text(for: color) == "hsl(220, 100%, 61%)")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The UV colour, band and advice rules (#51). The island is black, so the contrast is tested too.
@Suite("UVScale")
struct UVScaleTests {
    private func rgb(_ hex: UInt32) -> WeatherLook.RGB {
        WeatherLook.RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    private func close(_ a: WeatherLook.RGB, _ b: WeatherLook.RGB, tolerance: Double = 0.0001) -> Bool {
        abs(a.r - b.r) < tolerance && abs(a.g - b.g) < tolerance && abs(a.b - b.b) < tolerance
    }

    @Test("The colour is exact at each stop: sky blue to deep sunburn red")
    func stops() {
        #expect(close(UVScale.color(for: 0), rgb(0x9AD6FF)))
        #expect(close(UVScale.color(for: 2), rgb(0x6EC3FF)))
        #expect(close(UVScale.color(for: 3), rgb(0xFFD84A)))
        #expect(close(UVScale.color(for: 5), rgb(0xFFB03A)))
        #expect(close(UVScale.color(for: 6.5), rgb(0xFF8C2E)))
        #expect(close(UVScale.color(for: 8), rgb(0xFF5B33)))
        #expect(close(UVScale.color(for: 10), rgb(0xFF3B30)))
        #expect(close(UVScale.color(for: 11), rgb(0xEC2A3C)))
    }

    @Test("Between stops it blends smoothly, so 5.4 and 5.6 look different")
    func blends() {
        let mid = UVScale.color(for: 4)  // halfway between the stops at 3 and 5
        let low = rgb(0xFFD84A), high = rgb(0xFFB03A)
        #expect(close(mid, WeatherLook.RGB(r: (low.r + high.r) / 2, g: (low.g + high.g) / 2, b: (low.b + high.b) / 2)))
        #expect(!close(UVScale.color(for: 5.4), UVScale.color(for: 5.6), tolerance: 0.0001))
    }

    @Test("Above 11 the colour stays the deepest red, but the real number is kept")
    func clamps() {
        #expect(UVScale.color(for: 14) == UVScale.color(for: 11))
        #expect(UVScale.color(for: 99) == UVScale.color(for: 11))
        #expect(UVScale.displayValue(14) == 14)
        #expect(UVScale.displayValue(7.4) == 7)
        #expect(UVScale.displayValue(7.5) == 8)
    }

    @Test("The WHO bands: low 0–2, moderate 3–5, high 6–7, very high 8–10, extreme 11+")
    func categories() {
        #expect(UVScale.category(0) == .low)
        #expect(UVScale.category(2.4) == .low)
        #expect(UVScale.category(2.9) == .moderate)   // shows as 3, so it reads Moderate
        #expect(UVScale.category(3.0) == .moderate)
        #expect(UVScale.category(5.4) == .moderate)
        #expect(UVScale.category(5.9) == .high)       // shows as 6
        #expect(UVScale.category(6.0) == .high)
        #expect(UVScale.category(7.4) == .high)
        #expect(UVScale.category(7.5) == .veryHigh)
        #expect(UVScale.category(10.4) == .veryHigh)
        #expect(UVScale.category(10.9) == .extreme)   // shows as 11
        #expect(UVScale.category(11.0) == .extreme)
        #expect(UVScale.category(14) == .extreme)
    }

    @Test("The number and the word always agree")
    func numberMatchesWord() {
        var value = 0.0
        while value <= 14 {
            let shown = UVScale.displayValue(value)
            let expected: UVScale.Category = shown <= 2 ? .low : shown <= 5 ? .moderate : shown <= 7 ? .high : shown <= 10 ? .veryHigh : .extreme
            #expect(UVScale.category(value) == expected, "UV \(value)")
            value += 0.05
        }
    }

    @Test("Negative and not-a-number input read as a calm 0, Low")
    func badInput() {
        for value in [-3.0, -0.4, .nan, -.infinity] {
            #expect(UVScale.displayValue(value) == 0)
            #expect(UVScale.category(value) == .low)
            #expect(UVScale.color(for: value) == UVScale.color(for: 0))
        }
        #expect(UVScale.displayValue(.infinity) == 0)
    }

    @Test("Every band has its own words and advice")
    func words() {
        let all: [UVScale.Category] = [.low, .moderate, .high, .veryHigh, .extreme]
        #expect(Set(all.map(\.title)).count == 5)
        #expect(UVScale.Category.veryHigh.title == "Very high")
        #expect(Set(all.map { UVScale.advice(for: $0) }).count == 5)
        #expect(UVScale.advice(for: .low).contains("No sun protection"))
        #expect(UVScale.advice(for: .moderate).contains("Sun protection recommended"))
        #expect(UVScale.advice(for: .extreme).contains("Stay out of the midday sun"))
    }

    @Test("The protection line names the hours, or says UV stays low")
    func protection() {
        #expect(UVScale.protectionText(start: nil, end: nil) == "UV stays below 3 today.")
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = start.addingTimeInterval(6 * 3600)
        let text = UVScale.protectionText(start: start, end: end)
        #expect(text.hasPrefix("Protect from UV 3: "))
        #expect(text.contains("–"))
    }

    @Test("VoiceOver gets the value, the band, the advice and the peak")
    func spoken() {
        let peak = Date(timeIntervalSince1970: 1_800_000_000)
        let label = UVScale.accessibilityLabel(value: 8, peak: 9, peakTime: peak)
        #expect(label.hasPrefix("UV index 8, very high. "))
        #expect(label.contains("Extra protection needed"))
        #expect(label.contains("Peak today 9"))
        #expect(UVScale.accessibilityLabel(value: 0, peak: nil, peakTime: nil) == "UV index 0, low. No sun protection needed.")
    }

    @Test("Contrast against black is worked out the standard way")
    func contrastMath() {
        #expect(abs(UVScale.contrastAgainstBlack(rgb(0xFFFFFF)) - 21) < 0.01)
        #expect(abs(UVScale.contrastAgainstBlack(rgb(0x000000)) - 1) < 0.01)
    }
}

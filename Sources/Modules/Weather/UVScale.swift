// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The UV index's colour, band and advice (#51). Pure.
///
/// The colour runs smoothly from light sky blue to a deep sunburn red, so 5.4
/// and 5.6 look different. Every colour keeps at least 4.5:1 against the black
/// island (a test checks it), so the top end is a luminous red, not a dark one.
/// The bands follow the WHO: low 0–2, moderate 3–5, high 6–7, very high 8–10,
/// extreme 11+. The band follows the number as it is shown (rounded), so the
/// word and the number never disagree.
enum UVScale {
    /// UV where the colour is exactly this. Above the last it stays put.
    private static let stops: [(value: Double, rgb: WeatherLook.RGB)] = [
        (0, rgb(0x9AD6FF)),    // light sky blue
        (2, rgb(0x6EC3FF)),    // sky blue
        (3, rgb(0xFFD84A)),    // warm yellow
        (5, rgb(0xFFB03A)),    // yellow-orange
        (6.5, rgb(0xFF8C2E)),  // orange
        (8, rgb(0xFF5B33)),    // red-orange
        (10, rgb(0xFF3B30)),   // red
        (11, rgb(0xEC2A3C)),   // deep sunburn red
    ]

    /// The top of the gauge: the real number can be higher, the gauge stops here.
    static let gaugeMaximum = 12.0

    private static func rgb(_ hex: UInt32) -> WeatherLook.RGB {
        WeatherLook.RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// Not-a-number, infinite and negative readings are treated as 0.
    private static func sanitised(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    static func color(for value: Double) -> WeatherLook.RGB {
        let value = min(sanitised(value), stops[stops.count - 1].value)
        for index in 1..<stops.count where value <= stops[index].value {
            let (from, to) = (stops[index - 1], stops[index])
            let t = (value - from.value) / (to.value - from.value)
            return WeatherLook.RGB(r: from.rgb.r + (to.rgb.r - from.rgb.r) * t,
                                   g: from.rgb.g + (to.rgb.g - from.rgb.g) * t,
                                   b: from.rgb.b + (to.rgb.b - from.rgb.b) * t)
        }
        return stops[stops.count - 1].rgb
    }

    /// The colours of the gauge's track, from 0 to its end.
    static var gaugeColors: [WeatherLook.RGB] {
        (0...12).map { color(for: Double($0)) }
    }

    /// The whole number shown. A reading of 14 shows 14.
    static func displayValue(_ value: Double) -> Int { Int(sanitised(value).rounded()) }

    enum Category: String, Equatable, Sendable {
        case low, moderate, high, veryHigh, extreme

        var title: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            case .veryHigh: "Very high"
            case .extreme: "Extreme"
            }
        }
    }

    static func category(_ value: Double) -> Category {
        switch displayValue(value) {
        case ...2: .low
        case 3...5: .moderate
        case 6...7: .high
        case 8...10: .veryHigh
        default: .extreme
        }
    }

    static func advice(for category: Category) -> String {
        switch category {
        case .low: "No sun protection needed."
        case .moderate: "Sun protection recommended."
        case .high: "Protection needed: shade at midday, sunscreen and a hat."
        case .veryHigh: "Extra protection needed. Avoid the midday sun."
        case .extreme: "Take every precaution. Stay out of the midday sun."
        }
    }

    /// Where the gauge's marker sits, 0…1.
    static func gaugeFraction(_ value: Double) -> Double { min(sanitised(value), gaugeMaximum) / gaugeMaximum }

    /// "Protect from UV 3: 10 am – 4 pm", or that UV stays low.
    static func protectionText(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "UV stays below 3 today." }
        return "Protect from UV 3: \(start.formatted(.dateTime.hour())) – \(end.formatted(.dateTime.hour()))"
    }

    /// What VoiceOver reads: the value, the band, the advice and the peak.
    static func accessibilityLabel(value: Double, peak: Double?, peakTime: Date?) -> String {
        let band = category(value)
        var text = "UV index \(displayValue(value)), \(band.title.lowercased()). \(advice(for: band))"
        if let peak, let peakTime {
            text += " Peak today \(displayValue(peak)) at \(peakTime.formatted(.dateTime.hour()))."
        }
        return text
    }

    /// WCAG contrast of a colour against pure black (the island).
    static func contrastAgainstBlack(_ color: WeatherLook.RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        return (luminance + 0.05) / 0.05
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The weather's look, worked out from the forecast. Pure.
enum WeatherLook {
    struct RGB: Equatable, Sendable {
        var r: Double, g: Double, b: Double
        var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    }

    /// A soft colour for the scene behind the glyph: warm for sun, indigo at night, blue for rain.
    static func tint(code: Int, isDay: Bool) -> RGB {
        switch code {
        case 0, 1, 2: isDay ? RGB(r: 1.00, g: 0.78, b: 0.30) : RGB(r: 0.45, g: 0.50, b: 1.00)
        case 71, 73, 75, 77, 85, 86: RGB(r: 0.75, g: 0.88, b: 1.00)
        case 95, 96, 99: RGB(r: 0.62, g: 0.45, b: 1.00)
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: RGB(r: 0.35, g: 0.60, b: 1.00)
        default: isDay ? RGB(r: 0.62, g: 0.72, b: 0.88) : RGB(r: 0.45, g: 0.52, b: 0.78)
        }
    }

    /// Where the current temperature sits between the day's low and high, 0…1. Halfway when they're equal.
    static func rangeFraction(current: Double, low: Double, high: Double) -> Double {
        guard high > low else { return 0.5 }
        return min(max((current - low) / (high - low), 0), 1)
    }

    /// The best chance of rain in the next hours, when it is worth a mention (20 % or more).
    static func rainChance(in hours: [HourlyWeather]) -> Int? {
        let best = hours.compactMap(\.precipitationChance).max() ?? 0
        return best >= 20 ? best : nil
    }
}

/// One hour: its time, a glyph, the temperature, and a chance of rain if there is one.
struct WeatherHourColumn: View {
    let hour: HourlyWeather
    let unit: TemperatureUnit
    var large = false

    var body: some View {
        VStack(spacing: large ? 4 : 1) {
            Text(hour.time.formatted(.dateTime.hour()))
                .font(.system(size: large ? 11 : 9))
                .dimmedText(0.7)
            Image(systemName: WeatherCondition(code: hour.code).symbol(isDay: hour.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: large ? 18 : 13))
                .frame(height: large ? 22 : 16)
            Text(unit.text(fromCelsius: hour.celsius))
                .font(.system(size: large ? 13 : 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let chance = hour.precipitationChance, chance >= 20 {
                Text("\(chance)%").font(.system(size: large ? 10 : 8, weight: .semibold)).foregroundStyle(Color.cyan)
            } else if large {
                // Keeps the columns level.
                Text(" ").font(.system(size: 10))
            }
        }
        .frame(minWidth: large ? 36 : 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hour.time.formatted(.dateTime.hour())): \(unit.text(fromCelsius: hour.celsius)), \(WeatherCondition(code: hour.code).text)"
            + (hour.precipitationChance.map { $0 >= 20 ? ", \($0) percent chance of rain" : "" } ?? ""))
    }
}

/// The day's range as a bar, low to high, with a dot where it is now.
struct WeatherRangeBar: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit

    var body: some View {
        let fraction = WeatherLook.rangeFraction(current: snapshot.celsius, low: snapshot.lowCelsius, high: snapshot.highCelsius)
        HStack(spacing: 8) {
            Text(unit.text(fromCelsius: snapshot.lowCelsius))
                .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().dimmedText(0.7)
            Capsule()
                .fill(LinearGradient(colors: [Color(.sRGB, red: 0.35, green: 0.60, blue: 1.0), Color(.sRGB, red: 1.0, green: 0.72, blue: 0.30)],
                                     startPoint: .leading, endPoint: .trailing).opacity(0.85))
                .frame(height: 5)
                .overlay {
                    GeometryReader { proxy in
                        Circle()
                            .fill(.white)
                            .frame(width: 9, height: 9)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .position(x: max(4.5, min(proxy.size.width - 4.5, proxy.size.width * fraction)), y: proxy.size.height / 2)
                    }
                }
            Text(unit.text(fromCelsius: snapshot.highCelsius))
                .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().dimmedText(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: low \(unit.text(fromCelsius: snapshot.lowCelsius)), high \(unit.text(fromCelsius: snapshot.highCelsius)), now \(unit.text(fromCelsius: snapshot.celsius))")
    }
}

/// The expanded weather on the Island tab: the big temperature with a soft
/// glow of the sky behind its glyph, the next hours, and the day's range.
struct WeatherExpandedBody: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit
    /// The day's range bar under the row. The Weather tab hides it while its UV card is showing.
    var showsRange = true
    /// A small UV reading beside the range bar; nil leaves it out.
    var uv: UVSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The temperature and conditions always win; the hours that don't fit are
            // dropped (five down to two) rather than squeezing the temperature out, which
            // is what a smaller Expanded size would otherwise do.
            ViewThatFits(in: .horizontal) {
                row(hours: 5)
                row(hours: 4)
                row(hours: 3)
                row(hours: 2)
            }
            if showsRange {
                HStack(spacing: 14) {
                    WeatherRangeBar(snapshot: snapshot, unit: unit)
                    if let uv { UVMini(uv: uv) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(hours count: Int) -> some View {
        let tint = WeatherLook.tint(code: snapshot.code, isDay: snapshot.isDay).color
        return HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 42))
                    .frame(width: 52)
                    .background {
                        Circle().fill(tint.opacity(0.30)).frame(width: 110, height: 110).blur(radius: 26)
                            .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(unit.text(fromCelsius: snapshot.celsius))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    Text(snapshot.condition.text)
                        .font(.system(size: 13, weight: .medium))
                        .dimmedText(0.85)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(snapshot.hours.dropFirst().prefix(count)) { hour in
                    WeatherHourColumn(hour: hour, unit: unit, large: true)
                }
            }
        }
    }
}

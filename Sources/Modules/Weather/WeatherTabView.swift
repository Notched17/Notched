// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// MARK: Small pieces

/// UV's small reading for the Today strip: a sun, the number in the scale colour, and the band's word.
/// The word is always shown, so the colour is never the only signal.
struct UVChip: View {
    let uv: UVSummary

    var body: some View {
        let color = UVScale.color(for: uv.current).color
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill").font(.system(size: 10)).foregroundStyle(color)
            Text("\(UVScale.displayValue(uv.current))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(UVScale.category(uv.current).title)
                .font(.system(size: 11))
                .dimmedText(0.75)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("UV index \(UVScale.displayValue(uv.current)), \(UVScale.category(uv.current).title.lowercased())")
    }
}

/// UV in a corner of the island's weather page: the chip and a short gauge.
struct UVMini: View {
    let uv: UVSummary

    var body: some View {
        HStack(spacing: 8) {
            UVChip(uv: uv)
            UVGauge(value: uv.current).frame(width: 52)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UVScale.accessibilityLabel(value: uv.current, peak: uv.peak, peakTime: uv.peakTime))
    }
}

/// The scale as a bar, with a marker where UV is now.
struct UVGauge: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fraction = UVScale.gaugeFraction(value)
        Capsule()
            .fill(LinearGradient(colors: UVScale.gaugeColors.map(\.color), startPoint: .leading, endPoint: .trailing))
            .frame(height: 6)
            .overlay {
                GeometryReader { proxy in
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .position(x: max(5.5, min(proxy.size.width - 5.5, proxy.size.width * fraction)), y: proxy.size.height / 2)
                        .animation(reduceMotion ? Motion.reduced : .spring(response: 0.5, dampingFraction: 0.85), value: fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

/// UV hour by hour through the daylight hours, each bar tinted by the scale.
struct UVHourStrip: View {
    let hours: [HourlyWeather]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(hours) { hour in
                    let uv = hour.uvIndex ?? 0
                    Capsule()
                        .fill(UVScale.color(for: uv).color)
                        .frame(width: 8, height: max(4, barHeight * min(uv, 11) / 11))
                        .animation(reduceMotion ? Motion.reduced : .smooth(duration: 0.4), value: uv)
                }
            }
            .frame(height: barHeight, alignment: .bottom)
            HStack(spacing: 0) {
                Text(hours.first?.time.formatted(.dateTime.hour()) ?? "")
                Spacer(minLength: 4)
                if hours.count > 1 { Text(hours.last?.time.formatted(.dateTime.hour()) ?? "") }
            }
            .font(.system(size: 8))
            .dimmedText(0.7)
            .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("UV by hour: " + hours.map { "\($0.time.formatted(.dateTime.hour())) \(UVScale.displayValue($0.uvIndex ?? 0))" }.joined(separator: ", "))
    }
}

/// The full UV card (ADR-0033): the number big in the scale colour, its band, a gauge with a marker,
/// the advice, today's peak, and the hours ahead. A content card, so it has no glass of its own.
struct UVCard: View {
    let uv: UVSummary
    let snapshot: WeatherSnapshot
    @Environment(\.islandSurfaceIsGlass) private var surfaceIsGlass

    /// The daylight hours still to come (this one included), with a UV reading.
    private var daylight: [HourlyWeather] {
        snapshot.hours.filter { $0.isDay && $0.uvIndex != nil }
    }

    var body: some View {
        let color = UVScale.color(for: uv.current).color
        let band = UVScale.category(uv.current)
        ViewThatFits(in: .horizontal) {
            card(strip: Array(daylight.prefix(8)))
            card(strip: Array(daylight.prefix(5)))
            card(strip: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            ZStack {
                if surfaceIsGlass { Color.white.opacity(0.06) }
                color.opacity(0.10)
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UVScale.accessibilityLabel(value: uv.current, peak: uv.peak, peakTime: uv.peakTime))
        .accessibilityValue(band.title)
    }

    private func card(strip: [HourlyWeather]) -> some View {
        let color = UVScale.color(for: uv.current).color
        let band = UVScale.category(uv.current)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("UV INDEX").font(.system(size: 9, weight: .semibold)).tracking(0.6).dimmedText(0.7)
                Text("\(UVScale.displayValue(uv.current))")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text(band.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 5) {
                UVGauge(value: uv.current)
                Text(UVScale.advice(for: band))
                    .font(.system(size: 11))
                    .dimmedText(0.85)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10))
                    .dimmedText(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            if !strip.isEmpty { UVHourStrip(hours: strip) }
        }
    }

    /// "Peak 8 at 1 pm · Protect from UV 3: 10 am – 4 pm"; "was" once the peak has passed.
    private var detail: String {
        var parts: [String] = []
        if let peak = uv.peak, let time = uv.peakTime {
            let passed = time.addingTimeInterval(3600) <= snapshot.fetchedAt
            parts.append("\(passed ? "Today's peak was" : "Peak") \(UVScale.displayValue(peak)) at \(time.formatted(.dateTime.hour()))")
        }
        parts.append(UVScale.protectionText(start: uv.protectionStart, end: uv.protectionEnd))
        return parts.joined(separator: " · ")
    }
}

// MARK: The tab

/// Weather's tab (ADR-0033): the conditions, then the UV card. Without UV (none in the forecast, or
/// "Show UV index" off) the card goes and the day's range bar takes its place.
struct WeatherTabView: View {
    let model: WeatherModel
    @Environment(\.islandSurfaceIsGlass) private var surfaceIsGlass

    var body: some View {
        switch model.shownDisplay {
        case .noLocation:
            note("No city chosen yet. Choose one on the Today tab or in Settings.")
        case .loading:
            note("Loading weather…")
        case .unavailable:
            note("Weather isn't available right now.")
        case .ready(let snapshot, _, _, let isStale):
            let uv = model.uvToShow
            VStack(alignment: .leading, spacing: 8) {
                WeatherExpandedBody(snapshot: snapshot, unit: model.unit, showsRange: uv == nil)
                if let uv { UVCard(uv: uv.summary, snapshot: uv.snapshot) }
            }
            .opacity(isStale ? 0.55 : 1)
            .accessibilityElement(children: .contain)
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "cloud.sun")
            .font(IslandFont.subtitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The weather page on the Island tab: the conditions and range, with a small UV reading when it is on.
struct WeatherActivityBody: View {
    let snapshot: WeatherSnapshot
    let unit: TemperatureUnit
    let model: WeatherModel

    var body: some View {
        WeatherExpandedBody(snapshot: snapshot, unit: unit, uv: model.uvToShow?.summary)
    }
}

/// Beside the camera housing on a notched display: where the weather is for.
struct WeatherTabHeaderLeading: View {
    let model: WeatherModel

    var body: some View {
        if case .ready(_, let location, _, _) = model.shownDisplay {
            HStack(spacing: 5) {
                Image(systemName: "location.fill").font(.system(size: 10, weight: .semibold)).dimmedText(0.7)
                Text(verbatim: location.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
        }
    }
}

/// Beside the camera housing, on the right: UV now in its colour, when there is one to show.
struct WeatherTabHeaderTrailing: View {
    let model: WeatherModel

    var body: some View {
        if let uv = model.uvToShow {
            UVChip(uv: uv.summary)
        }
    }
}

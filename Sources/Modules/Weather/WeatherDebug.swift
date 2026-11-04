// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation

/// A made-up UV for screenshots: `notched://debug/weather?uv=8` (see DebugCommands).
enum WeatherDebugUV: Equatable {
    case real
    /// The forecast has no UV (the "unavailable" look).
    case none
    case value(Double)
}

extension WeatherModel {
    /// The real display, with the UV replaced or a whole forecast made up. The reducer, the
    /// cache and the network never see any of it.
    func debugAdjusted(_ real: WeatherDisplay) -> WeatherDisplay {
        let location = WeatherLocation(name: "Bristol", latitude: 51.5, longitude: -2.6, source: .city)
        var shown = real
        if debugFake {
            shown = .ready(Self.fakeSnapshot(location: location), location, isOffline: false, isStale: false)
        }
        guard case .ready(var snapshot, let place, let isOffline, let isStale) = shown else { return shown }
        switch debugUV {
        case .real: break
        case .none:
            snapshot.uv = nil
            snapshot.hours = snapshot.hours.map { var hour = $0; hour.uvIndex = nil; return hour }
        case .value(let peak): Self.applyUV(peak: peak, to: &snapshot)
        }
        return .ready(snapshot, place, isOffline: isOffline, isStale: isStale)
    }

    private static func fakeSnapshot(location: WeatherLocation) -> WeatherSnapshot {
        let now = Date()
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        var hours: [HourlyWeather] = []
        for offset in 0..<12 {
            let rainy = offset % 5 == 4
            let time: Date = start.addingTimeInterval(Double(offset) * 3600)
            let celsius: Double = 13 + Double(offset % 6)
            let code: Int = rainy ? 61 : 2
            let chance: Int? = rainy ? 40 : nil
            hours.append(HourlyWeather(time: time, celsius: celsius, code: code, isDay: true, precipitationChance: chance))
        }
        var snapshot = WeatherSnapshot(locationKey: location.key, fetchedAt: now, celsius: 14, code: 2, isDay: true, highCelsius: 17, lowCelsius: 8, hours: hours)
        applyUV(peak: 6, to: &snapshot)
        return snapshot
    }

    /// UV that follows the sun: a curve peaking at `peak` at 1 pm local time, zero from about 7 pm to 7 am. The reading "now" is `peak`, so `uv=8` shows 8.
    private static func applyUV(peak: Double, to snapshot: inout WeatherSnapshot) {
        func uv(at date: Date) -> Double {
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            let hour = Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60
            return max(0, peak * cos(Double.pi * (hour - 13) / 12))
        }
        snapshot.hours = snapshot.hours.map { var hour = $0; hour.uvIndex = uv(at: hour.time); return hour }
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: snapshot.fetchedAt)
        let day = (0..<24).map { midnight.addingTimeInterval(Double($0) * 3600) }
        let protective = day.filter { uv(at: $0.addingTimeInterval(1800)) >= 3 }
        let top = day.max { uv(at: $0) < uv(at: $1) }
        snapshot.uv = UVSummary(current: peak, peak: peak, peakTime: peak > 0 ? midnight.addingTimeInterval(13 * 3600) : top,
                                protectionStart: protective.first, protectionEnd: protective.last.map { $0.addingTimeInterval(3600) })
    }
}
#endif

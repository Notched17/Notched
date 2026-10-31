// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where the weather is for. Coordinates are rounded to 0.1° (about 11 km)
/// before they are sent anywhere: enough for a forecast, and less precise
/// than the place the user chose.
struct WeatherLocation: Equatable, Codable, Sendable {
    enum Source: String, Codable, Sendable { case city, device }

    var name: String
    var latitude: Double
    var longitude: Double
    var source: Source

    init(name: String, latitude: Double, longitude: Double, source: Source) {
        self.name = name
        self.latitude = Self.rounded(latitude)
        self.longitude = Self.rounded(longitude)
        self.source = source
    }

    static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Two locations with the same key get the same forecast.
    var key: String { String(format: "%.1f,%.1f", latitude, longitude) }
}

struct HourlyWeather: Equatable, Codable, Sendable, Identifiable {
    var time: Date
    var celsius: Double
    var code: Int
    var isDay: Bool
    /// 0...100, nil when the service doesn't say.
    var precipitationChance: Int?

    var id: Date { time }
}

/// One successful look at the forecast. Temperatures stay in °C and are
/// converted when shown.
struct WeatherSnapshot: Equatable, Codable, Sendable {
    var locationKey: String
    var fetchedAt: Date
    var celsius: Double
    var code: Int
    var isDay: Bool
    var highCelsius: Double
    var lowCelsius: Double
    var hours: [HourlyWeather]

    var condition: WeatherCondition { WeatherCondition(code: code) }
}

// MARK: Conditions

/// What a WMO weather code means, in words and as an SF Symbol.
struct WeatherCondition: Equatable, Sendable {
    let code: Int

    var text: String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61: "Light rain"
        case 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71: "Light snow"
        case 73: "Snow"
        case 75: "Heavy snow"
        case 77: "Snow grains"
        case 80, 81: "Showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Unknown"
        }
    }

    func symbol(isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81, 82: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

// MARK: Units

enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit

    /// Follows the Mac's region: Fahrenheit in the US, Celsius elsewhere.
    static func system(locale: Locale = .current) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    func degrees(fromCelsius celsius: Double) -> Int {
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        // -0 reads badly.
        let rounded = Int(value.rounded())
        return rounded == 0 ? 0 : rounded
    }

    /// "14°"
    func text(fromCelsius celsius: Double) -> String { "\(degrees(fromCelsius: celsius))°" }
}

enum TemperatureUnitSetting: String, CaseIterable, Sendable {
    case system, celsius, fahrenheit

    func resolved(locale: Locale = .current) -> TemperatureUnit {
        switch self {
        case .system: .system(locale: locale)
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        }
    }
}

// MARK: Search results

struct GeocodeResult: Identifiable, Equatable, Sendable {
    let id: Int
    var name: String
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    /// "Bristol, England, United Kingdom"
    var label: String { [name, region, country].compactMap { $0 }.joined(separator: ", ") }

    var location: WeatherLocation { WeatherLocation(name: name, latitude: latitude, longitude: longitude, source: .city) }
}

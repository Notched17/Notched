// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Open-Meteo (#51): free, no key. Weather data by Open-Meteo.com, licensed
/// CC BY 4.0 (the settings pane credits it). Only rounded coordinates, or a
/// city name the user typed, are ever sent.
enum OpenMeteo {
    static let forecastHost = "api.open-meteo.com"
    static let geocodingHost = "geocoding-api.open-meteo.com"

    static func forecastURL(for location: WeatherLocation) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = forecastHost
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.1f", location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.1f", location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,uv_index"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability,uv_index"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,uv_index_max"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components.url
    }

    static func geocodeURL(for name: String, language: String = Locale.current.language.languageCode?.identifier ?? "en") -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = geocodingHost
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    enum ParseError: Error, Equatable { case malformed, missingCurrent }

    // MARK: Forecast

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var time: Double
            var temperature_2m: Double?
            var weather_code: Int?
            var is_day: Int?
            var uv_index: Double?
        }
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]?
            var weather_code: [Int?]?
            var is_day: [Int?]?
            var precipitation_probability: [Double?]?
            var uv_index: [Double?]?
        }
        struct Daily: Decodable {
            var time: [Double]?
            var uv_index_max: [Double?]?
            var temperature_2m_max: [Double?]?
            var temperature_2m_min: [Double?]?
        }
        var current: Current?
        var hourly: Hourly?
        var daily: Daily?
    }

    /// Reads a forecast response. The current reading is required; missing
    /// hourly or daily parts only leave those parts empty. Hourly points start
    /// at the hour containing now and run for `hourCount`.
    static func parseForecast(_ data: Data, location: WeatherLocation, fetchedAt: Date, hourCount: Int = 12) throws -> WeatherSnapshot {
        guard let response = try? JSONDecoder().decode(ForecastResponse.self, from: data) else { throw ParseError.malformed }
        guard let current = response.current, let celsius = current.temperature_2m, celsius.isFinite else { throw ParseError.missingCurrent }

        var hours: [HourlyWeather] = []
        if let hourly = response.hourly, let temperatures = hourly.temperature_2m {
            let startOfHour = (current.time / 3600).rounded(.down) * 3600
            for (index, time) in hourly.time.enumerated() where time >= startOfHour && index < temperatures.count {
                guard let value = temperatures[index], value.isFinite else { continue }
                let code = hourly.weather_code.flatMap { index < $0.count ? $0[index] : nil } ?? 3
                let isDay = hourly.is_day.flatMap { index < $0.count ? $0[index] : nil } ?? 1
                let chance = hourly.precipitation_probability.flatMap { index < $0.count ? $0[index] : nil }
                hours.append(HourlyWeather(time: Date(timeIntervalSince1970: time), celsius: value, code: code, isDay: isDay == 1,
                                           precipitationChance: chance.map { min(100, max(0, Int($0.rounded()))) },
                                           uvIndex: Self.cleanUV(hourly.uv_index.flatMap { index < $0.count ? $0[index] : nil })))
                if hours.count == hourCount { break }
            }
        }

        let high = response.daily?.temperature_2m_max?.first.flatMap { $0 } ?? hours.map(\.celsius).max() ?? celsius
        let low = response.daily?.temperature_2m_min?.first.flatMap { $0 } ?? hours.map(\.celsius).min() ?? celsius
        return WeatherSnapshot(locationKey: location.key, fetchedAt: fetchedAt, celsius: celsius, code: current.weather_code ?? 3,
                               isDay: (current.is_day ?? 1) == 1, highCelsius: max(high, celsius), lowCelsius: min(low, celsius), hours: hours,
                               uv: uvSummary(response, now: current.time))
    }

    // MARK: UV

    /// A UV reading that makes sense: not a number or infinite means missing, below 0 means 0.
    private static func cleanUV(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    /// Today's UV from the whole day's hourly values (not just the hours still to come, so the
    /// morning's peak is still known in the afternoon). nil when there is no current reading.
    private static func uvSummary(_ response: ForecastResponse, now: Double) -> UVSummary? {
        let hourly = response.hourly
        let times = hourly?.time ?? []
        let values = hourly?.uv_index ?? []
        // Today runs from the daily midnight (the first hourly time if there is none) for 24 hours.
        let dayStart = response.daily?.time?.first ?? times.first ?? now
        let today: [(time: Double, uv: Double)] = times.enumerated().compactMap { index, time in
            guard time >= dayStart, time < dayStart + 86_400, index < values.count, let uv = cleanUV(values[index]) else { return nil }
            return (time, uv)
        }
        let nowHour = (now / 3600).rounded(.down) * 3600
        guard let current = cleanUV(response.current?.uv_index) ?? today.first(where: { $0.time == nowHour })?.uv else { return nil }

        let best = today.max { $0.uv < $1.uv }
        let peak = response.daily?.uv_index_max?.first.flatMap { cleanUV($0) } ?? best?.uv
        // The first hour of the highest value, not the last.
        let peakTime = best.flatMap { top in today.first { $0.uv == top.uv }?.time }
        let protective = today.filter { $0.uv >= 3 }
        return UVSummary(current: current, peak: peak, peakTime: peakTime.map { Date(timeIntervalSince1970: $0) },
                         protectionStart: protective.first.map { Date(timeIntervalSince1970: $0.time) },
                         protectionEnd: protective.last.map { Date(timeIntervalSince1970: $0.time + 3600) })
    }

    // MARK: Geocoding

    private struct GeocodeResponse: Decodable {
        struct Item: Decodable {
            var id: Int?
            var name: String?
            var latitude: Double?
            var longitude: Double?
            var country: String?
            var admin1: String?
        }
        var results: [Item]?
    }

    /// No `results` key means no matches, not an error.
    static func parseGeocoding(_ data: Data) throws -> [GeocodeResult] {
        guard let response = try? JSONDecoder().decode(GeocodeResponse.self, from: data) else { throw ParseError.malformed }
        return (response.results ?? []).compactMap { item in
            guard let name = item.name, let latitude = item.latitude, let longitude = item.longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            return GeocodeResult(id: item.id ?? Int(latitude * 1000 + longitude * 10), name: name, region: item.admin1, country: item.country,
                                 latitude: latitude, longitude: longitude)
        }
    }
}

/// The weather service as the module needs it. A protocol so tests don't use the network.
protocol WeatherAPI: Sendable {
    func forecast(for location: WeatherLocation) async throws -> WeatherSnapshot
    func search(city: String) async throws -> [GeocodeResult]
}

enum WeatherAPIError: Error { case badURL, badResponse, tooLarge }

/// Open-Meteo over HTTPS with a private session: no cookies, no cache on
/// disk, short timeouts.
struct OpenMeteoClient: WeatherAPI {
    private static let maxBytes = 2_000_000

    /// One session for the app's life; a new one per request would never be released.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func forecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
        guard let url = OpenMeteo.forecastURL(for: location) else { throw WeatherAPIError.badURL }
        let data = try await load(url)
        return try OpenMeteo.parseForecast(data, location: location, fetchedAt: Date())
    }

    func search(city: String) async throws -> [GeocodeResult] {
        guard let url = OpenMeteo.geocodeURL(for: city) else { return [] }
        return try OpenMeteo.parseGeocoding(try await load(url))
    }

    private func load(_ url: URL) async throws -> Data {
        let (data, response) = try await Self.session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WeatherAPIError.badResponse }
        guard data.count <= Self.maxBytes else { throw WeatherAPIError.tooLarge }
        return data
    }
}

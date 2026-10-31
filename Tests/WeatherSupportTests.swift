// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Weather's pure parts: codes, units, the Open-Meteo parser, the location rules (#51).
@Suite("Weather support")
struct WeatherSupportTests {
    let bristol = WeatherLocation(name: "Bristol", latitude: 51.45523, longitude: -2.59665, source: .city)

    // MARK: Location

    @Test("Coordinates are rounded to 0.1° and make a key")
    func rounding() {
        #expect(bristol.latitude == 51.5)
        #expect(bristol.longitude == -2.6)
        #expect(bristol.key == "51.5,-2.6")
        #expect(WeatherLocation(name: "x", latitude: 51.52, longitude: -2.58, source: .device).key == bristol.key)
    }

    // MARK: Conditions

    @Test("Known codes read well and have a symbol that follows day and night")
    func conditions() {
        #expect(WeatherCondition(code: 0).text == "Clear")
        #expect(WeatherCondition(code: 0).symbol(isDay: true) == "sun.max.fill")
        #expect(WeatherCondition(code: 0).symbol(isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition(code: 2).symbol(isDay: false) == "cloud.moon.fill")
        #expect(WeatherCondition(code: 61).text == "Light rain")
        #expect(WeatherCondition(code: 65).symbol(isDay: true) == "cloud.heavyrain.fill")
        #expect(WeatherCondition(code: 73).symbol(isDay: true) == "cloud.snow.fill")
        #expect(WeatherCondition(code: 95).symbol(isDay: false) == "cloud.bolt.rain.fill")
    }

    @Test("Every code Open-Meteo documents has words and a symbol")
    func allCodes() {
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            #expect(WeatherCondition(code: code).text != "Unknown", "code \(code)")
            #expect(!WeatherCondition(code: code).symbol(isDay: true).isEmpty)
        }
    }

    @Test("An unknown code is still shown")
    func unknownCode() {
        #expect(WeatherCondition(code: 123).text == "Unknown")
        #expect(WeatherCondition(code: 123).symbol(isDay: true) == "cloud.fill")
    }

    // MARK: Units

    @Test("Temperatures convert and round, and never read -0")
    func units() {
        #expect(TemperatureUnit.celsius.text(fromCelsius: 14.4) == "14°")
        #expect(TemperatureUnit.celsius.text(fromCelsius: 14.5) == "15°")
        #expect(TemperatureUnit.fahrenheit.text(fromCelsius: 0) == "32°")
        #expect(TemperatureUnit.fahrenheit.text(fromCelsius: 100) == "212°")
        #expect(TemperatureUnit.celsius.text(fromCelsius: -0.4) == "0°")
        #expect(TemperatureUnit.celsius.text(fromCelsius: -3.6) == "-4°")
    }

    @Test("The system unit follows the region")
    func systemUnit() {
        #expect(TemperatureUnit.system(locale: Locale(identifier: "en_US")) == .fahrenheit)
        #expect(TemperatureUnit.system(locale: Locale(identifier: "en_GB")) == .celsius)
        #expect(TemperatureUnit.system(locale: Locale(identifier: "de_DE")) == .celsius)
        #expect(TemperatureUnitSetting.celsius.resolved(locale: Locale(identifier: "en_US")) == .celsius)
        #expect(TemperatureUnitSetting.fahrenheit.resolved(locale: Locale(identifier: "en_GB")) == .fahrenheit)
    }

    // MARK: URLs

    @Test("The forecast request carries only rounded coordinates, over HTTPS")
    func forecastURL() throws {
        let url = try #require(OpenMeteo.forecastURL(for: bristol))
        let text = url.absoluteString
        #expect(url.scheme == "https" && url.host == "api.open-meteo.com")
        #expect(text.contains("latitude=51.5") && text.contains("longitude=-2.6"))
        #expect(!text.contains("51.45") && !text.contains("2.59"))
        #expect(text.contains("timeformat=unixtime") && text.contains("timezone=auto"))
    }

    @Test("A city search is encoded, and too-short searches send nothing")
    func geocodeURL() throws {
        let url = try #require(OpenMeteo.geocodeURL(for: " São Paulo ", language: "en"))
        #expect(url.host == "geocoding-api.open-meteo.com")
        #expect(url.absoluteString.contains("name=S%C3%A3o%20Paulo"))
        #expect(OpenMeteo.geocodeURL(for: "a", language: "en") == nil)
        #expect(OpenMeteo.geocodeURL(for: "   ", language: "en") == nil)
    }

    // MARK: Parsing

    private let forecastJSON = """
    {"current":{"time":1800009000,"temperature_2m":14.4,"weather_code":3,"is_day":1},
     "hourly":{"time":[1800003600,1800007200,1800010800,1800014400],
               "temperature_2m":[10.0,14.0,15.5,null],"weather_code":[0,3,61,80],
               "is_day":[1,1,1,0],"precipitation_probability":[0,10,45,null]},
     "daily":{"time":[1799971200],"temperature_2m_max":[17.2],"temperature_2m_min":[8.1]}}
    """

    @Test("A forecast becomes a snapshot: now, the hours from this one on, high and low")
    func parsesForecast() throws {
        let fetched = Date(timeIntervalSince1970: 1_800_009_100)
        let snapshot = try OpenMeteo.parseForecast(Data(forecastJSON.utf8), location: bristol, fetchedAt: fetched)
        #expect(snapshot.locationKey == bristol.key)
        #expect(snapshot.fetchedAt == fetched)
        #expect(snapshot.celsius == 14.4 && snapshot.code == 3 && snapshot.isDay)
        #expect(snapshot.highCelsius == 17.2 && snapshot.lowCelsius == 8.1)
        // The 09:00 point is before this hour; the last has no temperature.
        #expect(snapshot.hours.map(\.celsius) == [14.0, 15.5])
        #expect(snapshot.hours[0].time == Date(timeIntervalSince1970: 1_800_007_200))
        #expect(snapshot.hours[1].code == 61 && snapshot.hours[1].precipitationChance == 45)
        #expect(snapshot.condition.text == "Overcast")
    }

    @Test("Missing hourly and daily parts leave those parts empty, with sensible high and low")
    func parsesCurrentOnly() throws {
        let json = #"{"current":{"time":1800009000,"temperature_2m":12}}"#
        let snapshot = try OpenMeteo.parseForecast(Data(json.utf8), location: bristol, fetchedAt: .now)
        #expect(snapshot.hours.isEmpty)
        #expect(snapshot.highCelsius == 12 && snapshot.lowCelsius == 12)
        #expect(snapshot.code == 3)
    }

    @Test("The high is never below now, nor the low above it")
    func highLowEnvelope() throws {
        let json = #"{"current":{"time":1800009000,"temperature_2m":14.4},"daily":{"temperature_2m_max":[10],"temperature_2m_min":[16]}}"#
        let snapshot = try OpenMeteo.parseForecast(Data(json.utf8), location: bristol, fetchedAt: .now)
        #expect(snapshot.highCelsius == 14.4 && snapshot.lowCelsius == 14.4)
    }

    @Test("A response without a usable current reading is refused")
    func refusesBad() {
        #expect(throws: OpenMeteo.ParseError.malformed) { try OpenMeteo.parseForecast(Data("not json".utf8), location: bristol, fetchedAt: .now) }
        #expect(throws: OpenMeteo.ParseError.missingCurrent) { try OpenMeteo.parseForecast(Data(#"{"daily":{}}"#.utf8), location: bristol, fetchedAt: .now) }
        #expect(throws: OpenMeteo.ParseError.missingCurrent) {
            try OpenMeteo.parseForecast(Data(#"{"current":{"time":1,"temperature_2m":null}}"#.utf8), location: bristol, fetchedAt: .now)
        }
    }

    @Test("A long hourly array stops at 12 hours")
    func hourCap() throws {
        let times = (0..<30).map { 1_800_007_200 + $0 * 3600 }
        let temps = (0..<30).map { Double($0) }
        let json = """
        {"current":{"time":1800009000,"temperature_2m":14},"hourly":{"time":\(times),"temperature_2m":\(temps)}}
        """
        let snapshot = try OpenMeteo.parseForecast(Data(json.utf8), location: bristol, fetchedAt: .now)
        #expect(snapshot.hours.count == 12)
        #expect(snapshot.hours.first?.celsius == 0)
    }

    @Test("Cities come back with names, regions and rounded coordinates; broken entries are dropped")
    func parsesGeocoding() throws {
        let json = """
        {"results":[{"id":2654675,"name":"Bristol","latitude":51.45523,"longitude":-2.59665,"country":"United Kingdom","admin1":"England"},
                    {"name":"Nowhere"},
                    {"id":9,"name":"Off the map","latitude":95,"longitude":0}]}
        """
        let results = try OpenMeteo.parseGeocoding(Data(json.utf8))
        #expect(results.count == 1)
        #expect(results[0].label == "Bristol, England, United Kingdom")
        #expect(results[0].location.key == "51.5,-2.6")
        #expect(results[0].location.source == .city)
    }

    @Test("No matches is an empty list, not an error; junk is an error")
    func geocodingEdges() throws {
        #expect(try OpenMeteo.parseGeocoding(Data(#"{"generationtime_ms":0.4}"#.utf8)).isEmpty)
        #expect(throws: OpenMeteo.ParseError.malformed) { try OpenMeteo.parseGeocoding(Data("nope".utf8)) }
    }

    // MARK: Location plan (ADR-0027)

    private func makeFix(hoursAgo: Double, now: Date) -> DeviceFix {
        DeviceFix(location: WeatherLocation(name: "Here", latitude: 48.9, longitude: 2.4, source: .device), takenAt: now - hoursAgo * 3600)
    }

    @Test("The city is used unless device mode, allowed, and a fix exists")
    func activeLocation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fix = makeFix(hoursAgo: 2, now: now)
        #expect(WeatherLocationPlan.active(mode: .city, city: bristol, fix: fix, locationAllowed: true) == bristol)
        #expect(WeatherLocationPlan.active(mode: .device, city: bristol, fix: fix, locationAllowed: true) == fix.location)
        #expect(WeatherLocationPlan.active(mode: .device, city: bristol, fix: fix, locationAllowed: false) == bristol)
        #expect(WeatherLocationPlan.active(mode: .device, city: bristol, fix: nil, locationAllowed: true) == bristol)
        #expect(WeatherLocationPlan.active(mode: .device, city: nil, fix: nil, locationAllowed: true) == nil)
    }

    @Test("A new fix is taken at most once a day, and only when allowed")
    func fixTiming() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WeatherLocationPlan.needsFix(mode: .device, fix: nil, locationAllowed: true, now: now))
        #expect(!WeatherLocationPlan.needsFix(mode: .device, fix: makeFix(hoursAgo: 23.9, now: now), locationAllowed: true, now: now))
        #expect(WeatherLocationPlan.needsFix(mode: .device, fix: makeFix(hoursAgo: 24, now: now), locationAllowed: true, now: now))
        #expect(!WeatherLocationPlan.needsFix(mode: .city, fix: nil, locationAllowed: true, now: now))
        #expect(!WeatherLocationPlan.needsFix(mode: .device, fix: nil, locationAllowed: false, now: now))
    }

    // MARK: Settings and cache

    @MainActor
    @Test("Settings default to a chosen city, system units and no compact temperature, and round-trip")
    func settings() {
        let defaults = UserDefaults(suiteName: "WeatherSettingsTests.\(UUID().uuidString)")!
        let settings = WeatherSettings(defaults: defaults)
        #expect(settings.mode == .city && settings.unit == .system && !settings.showCompact)
        #expect(settings.city == nil && settings.deviceFix == nil)
        settings.mode = .device
        settings.city = bristol
        settings.unit = .fahrenheit
        settings.showCompact = true
        settings.deviceFix = DeviceFix(location: bristol, takenAt: Date(timeIntervalSince1970: 1_800_000_000))
        let reloaded = WeatherSettings(defaults: defaults)
        #expect(reloaded.mode == .device && reloaded.city == bristol && reloaded.unit == .fahrenheit && reloaded.showCompact)
        #expect(reloaded.deviceFix?.takenAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reloaded.reducerConfig() == WeatherConfig(unit: .fahrenheit, showCompact: true))
        settings.city = nil
        #expect(WeatherSettings(defaults: defaults).city == nil)
    }

    @MainActor
    @Test("Damaged saved places are ignored")
    func damagedSettings() {
        let defaults = UserDefaults(suiteName: "WeatherDamaged.\(UUID().uuidString)")!
        defaults.set(Data("garbage".utf8), forKey: WeatherSettings.Key.city)
        defaults.set("sideways", forKey: WeatherSettings.Key.mode)
        let settings = WeatherSettings(defaults: defaults)
        #expect(settings.city == nil && settings.mode == .city)
    }

    @Test("The cache round-trips with private permissions and tolerates a missing or damaged file")
    func cache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WeatherCacheStore(url: directory.appendingPathComponent("cache.json"))
        #expect(store.load() == nil)
        let snapshot = try OpenMeteo.parseForecast(Data(forecastJSON.utf8), location: bristol, fetchedAt: Date(timeIntervalSince1970: 1_800_009_100))
        store.save(snapshot)
        #expect(store.load() == snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        try Data("nope".utf8).write(to: store.url)
        #expect(store.load() == nil)
        store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

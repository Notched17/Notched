// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

enum WeatherLocationMode: String, CaseIterable, Sendable {
    /// A city the user picked. The default: nothing is asked of macOS.
    case city
    /// An approximate fix from macOS, taken at most once a day.
    case device
}

/// The last approximate location macOS gave, and when.
struct DeviceFix: Codable, Equatable, Sendable {
    var location: WeatherLocation
    var takenAt: Date
}

/// Which place the weather is for, and when to ask macOS again (ADR-0027).
/// Pure so the rules can be tested.
enum WeatherLocationPlan {
    /// Location is asked for no more than once a day.
    static let fixInterval: TimeInterval = 24 * 3600

    /// The place to show. Device mode uses the last fix while macOS still allows
    /// Location; without permission, or before the first fix, it falls back to the city.
    static func active(mode: WeatherLocationMode, city: WeatherLocation?, fix: DeviceFix?, locationAllowed: Bool) -> WeatherLocation? {
        if mode == .device, locationAllowed, let fix { return fix.location }
        return city
    }

    /// Whether to take a new fix now: device mode, allowed, and none in the last day.
    static func needsFix(mode: WeatherLocationMode, fix: DeviceFix?, locationAllowed: Bool, now: Date) -> Bool {
        guard mode == .device, locationAllowed else { return false }
        guard let fix else { return true }
        return now.timeIntervalSince(fix.takenAt) >= fixInterval
    }
}

/// Weather's settings (Settings ▸ Modules ▸ Weather), under `weather.*`.
@MainActor
@Observable
final class WeatherSettings {
    enum Key {
        static let mode = "weather.mode"
        static let city = "weather.city"
        static let unit = "weather.unit"
        static let showCompact = "weather.showCompact"
        static let deviceFix = "weather.deviceFix"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var mode: WeatherLocationMode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    var city: WeatherLocation? { didSet { Self.store(city, key: Key.city, in: defaults) } }
    var unit: TemperatureUnitSetting { didSet { defaults.set(unit.rawValue, forKey: Key.unit) } }
    /// A temperature on the compact island when nothing more important is showing.
    var showCompact: Bool { didSet { defaults.set(showCompact, forKey: Key.showCompact) } }
    var deviceFix: DeviceFix? { didSet { Self.store(deviceFix, key: Key.deviceFix, in: defaults) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Key.mode).flatMap(WeatherLocationMode.init(rawValue:)) ?? .city
        city = Self.load(WeatherLocation.self, key: Key.city, from: defaults)
        unit = defaults.string(forKey: Key.unit).flatMap(TemperatureUnitSetting.init(rawValue:)) ?? .system
        showCompact = defaults.object(forKey: Key.showCompact) as? Bool ?? false
        deviceFix = Self.load(DeviceFix.self, key: Key.deviceFix, from: defaults)
    }

    func reducerConfig(locale: Locale = .current) -> WeatherConfig {
        WeatherConfig(unit: unit.resolved(locale: locale), showCompact: showCompact)
    }

    private static func store<T: Encodable>(_ value: T?, key: String, in defaults: UserDefaults) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// The last forecast on disk, so the island isn't empty after a relaunch.
struct WeatherCacheStore: Sendable {
    let url: URL

    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notched/Weather/cache.json")
    }

    func load() -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }

    func save(_ snapshot: WeatherSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct WeatherConfig: Equatable, Sendable {
    var unit: TemperatureUnit = .celsius
    /// A passive temperature on the compact island (off by default).
    var showCompact = false
}

/// What the Today tab's weather strip shows.
enum WeatherDisplay: Equatable, Sendable {
    /// No city chosen (and no device location).
    case noLocation
    /// Waiting for the first forecast.
    case loading
    /// The first forecast failed and there is nothing saved.
    case unavailable
    case ready(WeatherSnapshot, WeatherLocation, isOffline: Bool, isStale: Bool)
}

/// Weather's rules (#51): when to ask for a forecast, what to do when it
/// fails, and when old data is too old. Pure; the shell does the networking.
///
/// - A forecast is refreshed every 30 minutes, only while there is a place and
///   a connection. The first one is requested at once.
/// - After a failure it retries after 1, 5, 15, then every 30 minutes, and
///   again as soon as the connection returns.
/// - Saved data for the same place is used straight away; for another place it
///   is ignored. A new place is fetched at once.
/// - Data older than 6 hours is stale: shown dimmed, and the compact
///   temperature goes away. It is still better than a blank.
/// - One request at a time; an answer for a place that has since changed is dropped.
struct WeatherReducer: Sendable {
    static let refreshInterval: TimeInterval = 30 * 60
    static let staleAfter: TimeInterval = 6 * 3600
    static let backoff: [TimeInterval] = [60, 300, 900, 1800]

    struct State: Equatable, Sendable {
        var config = WeatherConfig()
        var location: WeatherLocation?
        var snapshot: WeatherSnapshot?
        var isOnline = true
        var failures = 0
        var lastAttempt: Date?
        /// The generation of the request in flight, if any.
        var inFlight: Int?
        var generation = 0
        var display: WeatherDisplay = .noLocation
        var compact: CompactKey?
        var scheduledWake: Date?
    }

    /// What the compact activity was last built from.
    struct CompactKey: Equatable, Sendable {
        var fetchedAt: Date
        var unit: TemperatureUnit
        var location: String
    }

    enum Event: Equatable, Sendable {
        case configure(WeatherConfig)
        /// The place changed (nil: none chosen).
        case location(WeatherLocation?)
        /// At start: the place, and saved data (used only if it is for that place).
        /// One event, so a fresh saved forecast is seen before any fetch is considered.
        case startup(location: WeatherLocation?, cache: WeatherSnapshot?)
        /// A wake, a settings change, or the user asked to refresh.
        case tick
        case network(isOnline: Bool)
        case fetched(WeatherSnapshot, generation: Int)
        case fetchFailed(generation: Int)
    }

    enum Effect: Equatable, Sendable {
        case fetch(WeatherLocation, generation: Int)
        case saveCache(WeatherSnapshot)
        case publish(WeatherDisplay)
        case postCompact(WeatherSnapshot, WeatherLocation)
        case endCompact
        case wake(Date?)
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .configure(let config):
            state.config = config
        case .location(let location):
            guard location != state.location else { break }
            let moved = location?.key != state.location?.key
            state.location = location
            if moved {
                // Another place: forget the old forecast and any request for it.
                state.snapshot = nil
                state.failures = 0
                state.lastAttempt = nil
                state.inFlight = nil
            }
        case .startup(let location, let cache):
            state.location = location
            state.snapshot = nil
            if let cache, cache.locationKey == location?.key { state.snapshot = cache }
        case .tick:
            break
        case .network(let isOnline):
            let regained = isOnline && !state.isOnline
            state.isOnline = isOnline
            // Back online after failures: try now, not at the end of the back-off.
            if regained, state.failures > 0 { state.lastAttempt = nil }
        case .fetched(let snapshot, let generation):
            guard generation == state.inFlight else { break }
            state.inFlight = nil
            guard snapshot.locationKey == state.location?.key else { break }
            state.snapshot = snapshot
            state.failures = 0
            state.lastAttempt = now
            effects.append(.saveCache(snapshot))
        case .fetchFailed(let generation):
            guard generation == state.inFlight else { break }
            state.inFlight = nil
            state.failures += 1
            state.lastAttempt = now
        }

        if let location = state.location, state.inFlight == nil, state.isOnline, isDue(now: now) {
            state.generation += 1
            state.inFlight = state.generation
            state.lastAttempt = now
            effects.append(.fetch(location, generation: state.generation))
        }
        return effects + evaluate(now: now)
    }

    // MARK: Evaluation

    /// Whether a new forecast should be requested now.
    private func isDue(now: Date) -> Bool {
        // Back online after failing: try now, whatever the back-off said.
        if state.failures > 0, state.lastAttempt == nil { return true }
        guard state.lastAttempt != nil || state.snapshot != nil else { return true }
        return (nextAttempt(now: now) ?? now) <= now
    }

    private func nextAttempt(now: Date) -> Date? {
        if state.failures > 0, let last = state.lastAttempt {
            return last.addingTimeInterval(Self.backoff[min(state.failures - 1, Self.backoff.count - 1)])
        }
        guard let fetched = state.snapshot?.fetchedAt else { return state.lastAttempt == nil ? now : state.lastAttempt }
        return fetched.addingTimeInterval(Self.refreshInterval)
    }

    private mutating func evaluate(now: Date) -> [Effect] {
        var effects: [Effect] = []

        let display = makeDisplay(now: now)
        if display != state.display {
            state.display = display
            effects.append(.publish(display))
        }

        // Compact temperature
        if state.config.showCompact, case .ready(let snapshot, let location, _, let isStale) = display, !isStale {
            let key = CompactKey(fetchedAt: snapshot.fetchedAt, unit: state.config.unit, location: location.key)
            if key != state.compact {
                state.compact = key
                effects.append(.postCompact(snapshot, location))
            }
        } else if state.compact != nil {
            state.compact = nil
            effects.append(.endCompact)
        }

        let wake = nextWake(now: now)
        if wake != state.scheduledWake {
            state.scheduledWake = wake
            effects.append(.wake(wake))
        }
        return effects
    }

    private func makeDisplay(now: Date) -> WeatherDisplay {
        guard let location = state.location else { return .noLocation }
        guard let snapshot = state.snapshot else {
            return state.failures > 0 || (!state.isOnline && state.lastAttempt != nil) ? .unavailable : .loading
        }
        let isStale = now.timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter
        return .ready(snapshot, location, isOffline: state.failures > 0 || !state.isOnline, isStale: isStale)
    }

    /// The next refresh, or the moment saved data turns stale.
    private func nextWake(now: Date) -> Date? {
        guard state.location != nil else { return nil }
        var candidates: [Date] = []
        if state.isOnline, state.inFlight == nil, let next = nextAttempt(now: now) { candidates.append(next) }
        if let fetched = state.snapshot?.fetchedAt { candidates.append(fetched.addingTimeInterval(Self.staleAfter + 1)) }
        return candidates.filter { $0 > now }.min()
    }
}

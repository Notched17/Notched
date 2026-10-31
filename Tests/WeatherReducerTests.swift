// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Weather's refresh, back-off, offline and stale rules (#51).
@Suite("WeatherReducer")
struct WeatherReducerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_007_200)
    let bristol = WeatherLocation(name: "Bristol", latitude: 51.5, longitude: -2.6, source: .city)
    let paris = WeatherLocation(name: "Paris", latitude: 48.9, longitude: 2.4, source: .city)

    private func snapshot(_ location: WeatherLocation, at date: Date) -> WeatherSnapshot {
        WeatherSnapshot(locationKey: location.key, fetchedAt: date, celsius: 14, code: 3, isDay: true, highCelsius: 17, lowCelsius: 8, hours: [])
    }

    private func fetches(_ effects: [WeatherReducer.Effect]) -> [(WeatherLocation, Int)] {
        effects.compactMap { if case .fetch(let location, let generation) = $0 { (location, generation) } else { nil } }
    }

    private func has(_ effects: [WeatherReducer.Effect], _ matches: (WeatherReducer.Effect) -> Bool) -> Bool { effects.contains(where: matches) }

    /// Started at `t0` in `location`, with saved data of the given age (nil: none).
    private func started(_ location: WeatherLocation? = nil, cacheAge: TimeInterval? = nil,
                         config: WeatherConfig = WeatherConfig()) -> (WeatherReducer, [WeatherReducer.Effect]) {
        let place = location ?? bristol
        var sut = WeatherReducer()
        _ = sut.reduce(.configure(config), now: t0)
        let effects = sut.reduce(.startup(location: place, cache: cacheAge.map { snapshot(place, at: t0 - $0) }), now: t0)
        return (sut, effects)
    }

    // MARK: Start

    @Test("With no place there is nothing to do")
    func noLocation() {
        var sut = WeatherReducer()
        let effects = sut.reduce(.startup(location: nil, cache: nil), now: t0)
        #expect(fetches(effects).isEmpty)
        #expect(sut.state.display == .noLocation)
        #expect(sut.state.scheduledWake == nil)
    }

    @Test("A place with nothing saved fetches at once and shows Loading")
    func firstFetch() {
        let (sut, effects) = started()
        #expect(fetches(effects).map(\.1) == [1])
        #expect(sut.state.display == .loading)
    }

    @Test("Fresh saved data shows at once and is not fetched again until 30 minutes old")
    func freshCache() {
        let (sut, effects) = started(cacheAge: 5 * 60)
        #expect(fetches(effects).isEmpty)
        guard case .ready(_, let location, let isOffline, let isStale) = sut.state.display else { Issue.record("not ready"); return }
        #expect(location == bristol && !isOffline && !isStale)
        #expect(sut.state.scheduledWake == t0 + 25 * 60)
    }

    @Test("Old saved data is shown while a new forecast is fetched")
    func oldCache() {
        let (sut, effects) = started(cacheAge: 40 * 60)
        #expect(fetches(effects).count == 1)
        if case .ready = sut.state.display {} else { Issue.record("expected the saved forecast to show") }
    }

    @Test("Saved data for another place is ignored")
    func cacheForAnotherPlace() {
        var sut = WeatherReducer()
        let effects = sut.reduce(.startup(location: bristol, cache: snapshot(paris, at: t0 - 60)), now: t0)
        #expect(fetches(effects).count == 1)
        #expect(sut.state.display == .loading)
    }

    // MARK: Refresh

    @Test("A forecast is saved, shown, and refreshed after 30 minutes")
    func refreshCycle() {
        var (sut, _) = started()
        let saved = sut.reduce(.fetched(snapshot(bristol, at: t0), generation: 1), now: t0)
        #expect(has(saved) { if case .saveCache = $0 { true } else { false } })
        #expect(sut.state.scheduledWake == t0 + 30 * 60)
        #expect(fetches(sut.reduce(.tick, now: t0 + 30 * 60 - 1)).isEmpty)
        #expect(fetches(sut.reduce(.tick, now: t0 + 30 * 60)).map(\.1) == [2])
    }

    @Test("Only one request is in flight at a time")
    func oneAtATime() {
        var (sut, _) = started()
        #expect(fetches(sut.reduce(.tick, now: t0 + 1)).isEmpty)
        #expect(fetches(sut.reduce(.tick, now: t0 + 9999)).isEmpty)
        #expect(sut.state.inFlight == 1)
    }

    @Test("An answer from an older request is dropped")
    func staleAnswer() {
        var (sut, _) = started()
        let effects = sut.reduce(.fetched(snapshot(bristol, at: t0), generation: 7), now: t0 + 1)
        #expect(effects.isEmpty || !has(effects) { if case .saveCache = $0 { true } else { false } })
        #expect(sut.state.snapshot == nil)
        #expect(sut.state.inFlight == 1)
    }

    // MARK: Failure

    @Test("After failures it waits 1, 5, 15, then 30 minutes between tries")
    func backoff() {
        var (sut, _) = started()
        var now = t0
        var generation = 1
        for delay in [60.0, 300, 900, 1800, 1800] {
            now += 2
            _ = sut.reduce(.fetchFailed(generation: generation), now: now)
            #expect(sut.state.scheduledWake == now + delay)
            #expect(fetches(sut.reduce(.tick, now: now + delay - 1)).isEmpty)
            let retry = fetches(sut.reduce(.tick, now: now + delay))
            generation += 1
            #expect(retry.map(\.1) == [generation])
            now += delay
        }
    }

    @Test("A success resets the back-off")
    func successResets() {
        var (sut, _) = started()
        _ = sut.reduce(.fetchFailed(generation: 1), now: t0 + 1)
        _ = sut.reduce(.tick, now: t0 + 61)                       // retry, generation 2
        _ = sut.reduce(.fetched(snapshot(bristol, at: t0 + 62), generation: 2), now: t0 + 62)
        #expect(sut.state.failures == 0)
        #expect(sut.state.scheduledWake == t0 + 62 + 30 * 60)
    }

    @Test("Failing with nothing saved says unavailable; failing with a saved forecast keeps it, marked offline")
    func failureDisplay() {
        var (empty, _) = started()
        _ = empty.reduce(.fetchFailed(generation: 1), now: t0 + 1)
        #expect(empty.state.display == .unavailable)

        var (saved, _) = started(cacheAge: 40 * 60)
        _ = saved.reduce(.fetchFailed(generation: 1), now: t0 + 1)
        guard case .ready(_, _, let isOffline, _) = saved.state.display else { Issue.record("not ready"); return }
        #expect(isOffline)
    }

    // MARK: Offline

    @Test("Nothing is fetched while offline; coming back fetches at once")
    func offline() {
        var (sut, _) = started()
        _ = sut.reduce(.fetched(snapshot(bristol, at: t0), generation: 1), now: t0)
        _ = sut.reduce(.network(isOnline: false), now: t0 + 10)
        guard case .ready(_, _, let isOffline, _) = sut.state.display else { Issue.record("not ready"); return }
        #expect(isOffline)
        #expect(fetches(sut.reduce(.tick, now: t0 + 31 * 60)).isEmpty)
        #expect(fetches(sut.reduce(.network(isOnline: true), now: t0 + 32 * 60)).count == 1)
    }

    @Test("Coming back after a failure skips the rest of the back-off, with or without a saved forecast")
    func regainedAfterFailure() {
        var (empty, _) = started()
        _ = empty.reduce(.fetchFailed(generation: 1), now: t0 + 1)
        _ = empty.reduce(.network(isOnline: false), now: t0 + 2)
        #expect(fetches(empty.reduce(.network(isOnline: true), now: t0 + 3)).count == 1)

        // The same with a saved forecast on screen: its schedule must not hold the retry back.
        var (retrying, _) = started(cacheAge: 40 * 60)
        _ = retrying.reduce(.fetchFailed(generation: 1), now: t0 + 1)
        _ = retrying.reduce(.network(isOnline: false), now: t0 + 2)
        #expect(fetches(retrying.reduce(.network(isOnline: true), now: t0 + 3)).count == 1)
    }

    @Test("Staying online doesn't trigger a fetch")
    func onlineAgain() {
        var (sut, _) = started(cacheAge: 60)
        #expect(fetches(sut.reduce(.network(isOnline: true), now: t0 + 5)).isEmpty)
    }

    // MARK: Stale

    @Test("After 6 hours the forecast is marked out of date, and the wake is set for that moment")
    func stale() {
        var (sut, _) = started(cacheAge: 5 * 3600 + 59 * 60)
        _ = sut.reduce(.network(isOnline: false), now: t0)
        guard case .ready(_, _, _, let before) = sut.state.display else { Issue.record("not ready"); return }
        #expect(!before)
        let expected = t0 - (5 * 3600 + 59 * 60) + 6 * 3600 + 1
        #expect(sut.state.scheduledWake == expected)
        _ = sut.reduce(.tick, now: expected)
        guard case .ready(_, _, _, let after) = sut.state.display else { Issue.record("not ready"); return }
        #expect(after)
    }

    // MARK: Place changes

    @Test("A new place drops the old forecast and fetches at once; the old request's answer is ignored")
    func placeChange() {
        var (sut, _) = started()                                  // generation 1 for Bristol
        let effects = sut.reduce(.location(paris), now: t0 + 5)
        #expect(fetches(effects).map(\.1) == [2])
        #expect(fetches(effects).first?.0 == paris)
        _ = sut.reduce(.fetched(snapshot(bristol, at: t0 + 6), generation: 1), now: t0 + 6)
        #expect(sut.state.snapshot == nil)
        _ = sut.reduce(.fetched(snapshot(paris, at: t0 + 7), generation: 2), now: t0 + 7)
        #expect(sut.state.snapshot?.locationKey == paris.key)
    }

    @Test("Another name for the same spot keeps the forecast")
    func sameSpot() {
        var (sut, _) = started(cacheAge: 60)
        let renamed = WeatherLocation(name: "Bristol UK", latitude: 51.52, longitude: -2.58, source: .device)
        #expect(fetches(sut.reduce(.location(renamed), now: t0 + 5)).isEmpty)
        #expect(sut.state.snapshot != nil)
    }

    @Test("Removing the place clears the display and stops refreshing")
    func placeRemoved() {
        var (sut, _) = started(cacheAge: 60)
        _ = sut.reduce(.location(nil), now: t0 + 5)
        #expect(sut.state.display == .noLocation)
        #expect(sut.state.scheduledWake == nil)
    }

    // MARK: Compact

    @Test("The compact temperature is posted once, again for a new forecast or unit, and ends when turned off or stale")
    func compact() {
        var (sut, _) = started(config: WeatherConfig(unit: .celsius, showCompact: true))
        func posts(_ effects: [WeatherReducer.Effect]) -> Int { effects.filter { if case .postCompact = $0 { true } else { false } }.count }
        #expect(posts(sut.reduce(.fetched(snapshot(bristol, at: t0), generation: 1), now: t0)) == 1)
        #expect(posts(sut.reduce(.tick, now: t0 + 10)) == 0)
        #expect(posts(sut.reduce(.configure(WeatherConfig(unit: .fahrenheit, showCompact: true)), now: t0 + 20)) == 1)
        #expect(has(sut.reduce(.configure(WeatherConfig(unit: .fahrenheit, showCompact: false)), now: t0 + 30)) { $0 == .endCompact })
        #expect(posts(sut.reduce(.configure(WeatherConfig(unit: .fahrenheit, showCompact: true)), now: t0 + 40)) == 1)
        _ = sut.reduce(.network(isOnline: false), now: t0 + 50)
        #expect(has(sut.reduce(.tick, now: t0 + 6 * 3600 + 5)) { $0 == .endCompact })
    }

    @Test("No compact temperature unless asked for")
    func compactOff() {
        var (sut, _) = started()
        let effects = sut.reduce(.fetched(snapshot(bristol, at: t0), generation: 1), now: t0)
        #expect(!has(effects) { if case .postCompact = $0 { true } else { false } })
    }

    // MARK: Fuzz

    @Test("Random events keep one request in flight at most, never fetch offline, and always wake in the future")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        var sut = WeatherReducer()
        var now = t0
        let places: [WeatherLocation?] = [nil, bristol, paris]
        for _ in 0..<800 {
            now += TimeInterval.random(in: 0...2400, using: &generator)
            let before = sut.state.inFlight
            let effects: [WeatherReducer.Effect]
            switch Int.random(in: 0..<7, using: &generator) {
            case 0: effects = sut.reduce(.location(places.randomElement(using: &generator)!), now: now)
            case 1: effects = sut.reduce(.network(isOnline: Bool.random(using: &generator)), now: now)
            case 2:
                let place = places.compactMap { $0 }.randomElement(using: &generator)!
                effects = sut.reduce(.fetched(snapshot(place, at: now), generation: Int.random(in: 0...(sut.state.generation + 1), using: &generator)), now: now)
            case 3: effects = sut.reduce(.fetchFailed(generation: Int.random(in: 0...(sut.state.generation + 1), using: &generator)), now: now)
            case 4: effects = sut.reduce(.configure(WeatherConfig(unit: .celsius, showCompact: Bool.random(using: &generator))), now: now)
            default: effects = sut.reduce(.tick, now: now)
            }
            for (location, generation) in fetches(effects) {
                #expect(sut.state.isOnline)
                #expect(sut.state.location == location)
                #expect(sut.state.inFlight == generation)
                #expect(before == nil || before != generation)
            }
            if sut.state.inFlight != nil { #expect(sut.state.location != nil) }
            if let wake = sut.state.scheduledWake { #expect(wake > now) }
            if sut.state.location == nil { #expect(sut.state.display == .noLocation) }
        }
    }
}

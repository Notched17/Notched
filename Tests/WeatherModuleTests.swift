// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// A forecast service the tests control.
final class FakeWeatherAPI: WeatherAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [WeatherLocation] = []
    private var _fails = false

    var calls: [WeatherLocation] { lock.withLock { _calls } }
    var fails: Bool {
        get { lock.withLock { _fails } }
        set { lock.withLock { _fails = newValue } }
    }

    func forecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
        lock.withLock { _calls.append(location) }
        if fails { throw WeatherAPIError.badResponse }
        return WeatherSnapshot(locationKey: location.key, fetchedAt: Date(), celsius: 14, code: 3, isDay: true, highCelsius: 17, lowCelsius: 8,
                               hours: [HourlyWeather(time: Date(), celsius: 14, code: 3, isDay: true, precipitationChance: nil)])
    }

    func search(city: String) async throws -> [GeocodeResult] { [] }
}

@MainActor
final class FakeDeviceLocation: DeviceLocationProvider {
    var result: WeatherLocation? = WeatherLocation(name: "Here", latitude: 48.9, longitude: 2.4, source: .device)
    private(set) var requests = 0

    func approximateLocation() async -> WeatherLocation? {
        requests += 1
        return result
    }
}

@MainActor
final class FakeReachability: ReachabilitySource {
    private var handler: (@MainActor (Bool) -> Void)?
    private(set) var isWatching = false

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        handler = onChange
        isWatching = true
        onChange(true)
    }

    func stop() {
        handler = nil
        isWatching = false
    }

    func set(online: Bool) { handler?(online) }
}

/// The Weather shell (#51).
@MainActor
@Suite("WeatherModule")
struct WeatherModuleTests {
    private let bristol = WeatherLocation(name: "Bristol", latitude: 51.5, longitude: -2.6, source: .city)

    private struct Rig {
        let module: WeatherModule
        let api: FakeWeatherAPI
        let device: FakeDeviceLocation
        let reachability: FakeReachability
        let coordinator: ActivityCoordinator
        let today: TodayHub
        let settings: SettingsStore
        let cache: WeatherCacheStore
    }

    private func makeRig(city: WeatherLocation?, mode: WeatherLocationMode = .city, allowed: Bool = false, cacheURL: URL? = nil) -> Rig {
        let coordinator = ActivityCoordinator()
        let today = TodayHub()
        today.publishTabs = { [coordinator] tabs in coordinator.setTabs(tabs, from: TodayHub.pseudoModuleID) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "WeatherModuleTests.\(UUID().uuidString)")!)
        settings.weather.city = city
        settings.weather.mode = mode
        let context = ModuleContext(activities: ActivitySink(moduleID: WeatherModule.descriptor.id, coordinator: coordinator),
                                    scheduler: RefreshScheduler(), settings: settings, services: ModuleServices(today: today), previousSessionCrashed: false)
        let api = FakeWeatherAPI()
        let device = FakeDeviceLocation()
        let reachability = FakeReachability()
        let cache = WeatherCacheStore(url: cacheURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeatherModuleTests-\(UUID().uuidString)/cache.json"))
        let module = WeatherModule(context: context, api: api, deviceLocation: device, reachability: reachability, cache: cache, locationAllowed: { allowed })
        return Rig(module: module, api: api, device: device, reachability: reachability, coordinator: coordinator, today: today, settings: settings, cache: cache)
    }

    private func cleanUp(_ rig: Rig) { try? FileManager.default.removeItem(at: rig.cache.url.deletingLastPathComponent()) }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    private func isReady(_ rig: Rig) -> Bool {
        if case .ready = rig.module.model.display { true } else { false }
    }

    @Test("Starting adds the top strip to the Today tab and starts watching the network; stopping undoes both")
    func startStop() {
        let rig = makeRig(city: nil)
        defer { cleanUp(rig) }
        rig.module.start()
        #expect(rig.today.sections.map(\.id) == ["weather"])
        #expect(rig.today.sections.first?.slot == .header)
        #expect(rig.coordinator.moduleTabs.map(\.id) == ["today"])
        #expect(rig.reachability.isWatching)
        rig.module.stop()
        #expect(rig.today.sections.isEmpty)
        #expect(rig.coordinator.moduleTabs.isEmpty)
        #expect(!rig.reachability.isWatching)
    }

    @Test("Without a city it asks for one and makes no request")
    func noCity() {
        let rig = makeRig(city: nil)
        defer { cleanUp(rig) }
        rig.module.start()
        #expect(rig.module.model.display == .noLocation)
        #expect(rig.api.calls.isEmpty)
        rig.module.stop()
    }

    @Test("A chosen city is fetched, shown, and saved for next time")
    func fetchesAndCaches() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.module.start()
        await settle { isReady(rig) }
        #expect(isReady(rig))
        #expect(rig.api.calls == [bristol])
        #expect(rig.cache.load()?.locationKey == bristol.key)
        rig.module.stop()
    }

    @Test("A fresh saved forecast shows at once and nothing is fetched")
    func usesCache() {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.cache.save(WeatherSnapshot(locationKey: bristol.key, fetchedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 60),
                                       celsius: 11, code: 0, isDay: true, highCelsius: 12, lowCelsius: 6, hours: []))
        rig.module.start()
        #expect(isReady(rig))
        #expect(rig.api.calls.isEmpty)
        rig.module.stop()
    }

    @Test("A failing service shows it isn't available; going offline and back retries")
    func failureThenRecovery() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.api.fails = true
        rig.module.start()
        await settle { rig.module.model.display == .unavailable }
        #expect(rig.module.model.display == .unavailable)
        rig.api.fails = false
        rig.reachability.set(online: false)
        rig.reachability.set(online: true)
        await settle { isReady(rig) }
        #expect(isReady(rig))
        rig.module.stop()
    }

    @Test("Device mode takes one fix, uses it, and doesn't ask again within a day")
    func deviceMode() async {
        let rig = makeRig(city: bristol, mode: .device, allowed: true)
        defer { cleanUp(rig) }
        rig.module.start()
        await settle { rig.settings.weather.deviceFix != nil && !rig.api.calls.isEmpty && rig.api.calls.last?.source == .device }
        #expect(rig.device.requests == 1)
        #expect(rig.settings.weather.deviceFix?.location.name == "Here")
        #expect(rig.api.calls.last?.source == .device)
        rig.module.stop()

        rig.module.start()
        #expect(rig.device.requests == 1)
        rig.module.stop()
    }

    @Test("Device mode without permission keeps the city and never asks macOS")
    func deviceModeDenied() async {
        let rig = makeRig(city: bristol, mode: .device, allowed: false)
        defer { cleanUp(rig) }
        rig.module.start()
        await settle { !rig.api.calls.isEmpty }
        #expect(rig.api.calls == [bristol])
        #expect(rig.device.requests == 0)
        rig.module.stop()
    }

    @Test("If macOS gives no location the city is kept")
    func noFix() async {
        let rig = makeRig(city: bristol, mode: .device, allowed: true)
        defer { cleanUp(rig) }
        rig.device.result = nil
        rig.module.start()
        await settle { !rig.api.calls.isEmpty }
        for _ in 0..<20 { await Task.yield() }
        #expect(rig.settings.weather.deviceFix == nil)
        #expect(rig.api.calls.allSatisfy { $0 == bristol })
        rig.module.stop()
    }

    @Test("The compact temperature is a passive activity, only when turned on")
    func compact() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.settings.weather.showCompact = true
        rig.module.start()
        await settle { !rig.coordinator.live.isEmpty }
        #expect(rig.coordinator.live.map(\.id) == [WeatherModule.activityID])
        #expect(rig.coordinator.live.first?.activity.kind == .passive)
        rig.settings.weather.showCompact = false
        rig.module.settingsChanged()
        #expect(rig.coordinator.live.isEmpty)
        rig.module.stop()
    }

    @Test("Choosing another city fetches it")
    func changeCity() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.module.start()
        await settle { isReady(rig) }
        let paris = WeatherLocation(name: "Paris", latitude: 48.9, longitude: 2.4, source: .city)
        rig.settings.weather.city = paris
        rig.module.settingsChanged()
        await settle { rig.api.calls.contains(paris) }
        #expect(rig.api.calls == [bristol, paris])
        rig.module.stop()
    }

    @Test("An answer that arrives after stopping is ignored")
    func lateAnswer() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.module.start()
        rig.module.stop()
        for _ in 0..<50 { await Task.yield() }
        #expect(rig.module.model.display == .noLocation)
        #expect(rig.cache.load() == nil)
    }

    @Test("Switching it on and off five times leaves nothing behind")
    func neverLeaks() async {
        let rig = makeRig(city: bristol)
        defer { cleanUp(rig) }
        rig.settings.weather.showCompact = true
        for _ in 0..<5 {
            rig.module.start()
            await settle { isReady(rig) }
            rig.module.stop()
            #expect(rig.today.sections.isEmpty)
            #expect(rig.coordinator.moduleTabs.isEmpty)
            #expect(rig.coordinator.live.isEmpty)
            #expect(!rig.reachability.isWatching)
        }
    }
}

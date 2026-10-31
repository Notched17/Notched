// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Weather (#51): current conditions, the next hours and today's high and low
/// in the Today tab's top strip, and an optional temperature on the compact
/// island. A thin shell around `WeatherReducer`.
///
/// Open-Meteo, no key. The place is a city the user picked (the default; no
/// permission) or, if they opt in, an approximate fix from macOS taken at most
/// once a day. It refreshes every 30 minutes while it is on, retries with a
/// back-off, and shows the last result (marked offline or out of date) when
/// there is no connection.
@MainActor
final class WeatherModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "weather",
        name: "Weather",
        symbol: "cloud.sun",
        summary: "Shows the current weather, the next few hours and today's high and low in the Today tab. Choose a city; asking macOS for your location is optional.",
        // Location is asked only if the user picks "My Location" in this module's pane, never on enabling.
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let activityID: ActivityID = "weather.now"
    static let sectionID = "weather"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(WeatherSettingsPane(settings: context.settings.weather, registry: context.registry, permissions: context.permissions))
    }

    let model = WeatherModel()
    private let context: ModuleContext
    private let api: any WeatherAPI
    private let deviceLocation: any DeviceLocationProvider
    private let reachability: any ReachabilitySource
    private let cache: WeatherCacheStore
    private let locationAllowed: () -> Bool
    private let wake = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = WeatherReducer()
    private var isRunning = false
    private var isTakingFix = false
    private let log = Log.module("weather")

    private var settings: WeatherSettings { context.settings.weather }

    convenience init(context: ModuleContext) {
        let permissions = context.services.permissions
        self.init(context: context, api: OpenMeteoClient(), deviceLocation: CoreLocationProvider(), reachability: ReachabilityWatcher(),
                  cache: WeatherCacheStore(url: WeatherCacheStore.defaultURL()),
                  locationAllowed: { permissions?.status(.location) == .granted })
    }

    init(context: ModuleContext, api: any WeatherAPI, deviceLocation: any DeviceLocationProvider, reachability: any ReachabilitySource,
         cache: WeatherCacheStore, locationAllowed: @escaping () -> Bool) {
        self.context = context
        self.api = api
        self.deviceLocation = deviceLocation
        self.reachability = reachability
        self.cache = cache
        self.locationAllowed = locationAllowed
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = WeatherActions(refresh: { [weak self] in self?.send(.tick) })
        wake.action = { [weak self] in self?.tick() }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in self?.tick() }
        observers.observe(.NSSystemClockDidChange) { [weak self] in self?.tick() }

        let model = model
        context.services.today.set(TodaySection(
            id: Self.sectionID, moduleID: Self.descriptor.id, slot: .header,
            content: IslandRegion { WeatherSectionView(model: model) }
        ))
        send(.configure(settings.reducerConfig()))
        send(.startup(location: activeLocation(), cache: cache.load()))
        reachability.start { [weak self] online in self?.send(.network(isOnline: online)) }
        takeFixIfNeeded()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        wake.schedule(at: nil)
        reachability.stop()
        observers.invalidate()
        context.services.today.remove(moduleID: Self.descriptor.id)
        context.activities.endAll()
        model.actions = WeatherActions()
        model.reset()
        reducer = WeatherReducer()
    }

    /// The pane changed the place, the mode, the unit or the compact option.
    func settingsChanged() {
        guard isRunning else { return }
        send(.configure(settings.reducerConfig()))
        applyLocation()
        takeFixIfNeeded()
    }

    // MARK: Place

    private func activeLocation() -> WeatherLocation? {
        WeatherLocationPlan.active(mode: settings.mode, city: settings.city, fix: settings.deviceFix, locationAllowed: locationAllowed())
    }

    private func applyLocation() {
        send(.location(activeLocation()))
    }

    /// A new approximate location, at most once a day, and only when allowed.
    private func takeFixIfNeeded() {
        guard isRunning, !isTakingFix,
              WeatherLocationPlan.needsFix(mode: settings.mode, fix: settings.deviceFix, locationAllowed: locationAllowed(), now: Date()) else { return }
        isTakingFix = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let location = await self.deviceLocation.approximateLocation()
            self.isTakingFix = false
            guard self.isRunning else { return }
            if let location {
                self.settings.deviceFix = DeviceFix(location: location, takenAt: Date())
                self.applyLocation()
            } else {
                self.log.notice("macOS gave no location; keeping the city")
            }
        }
    }

    private func tick() {
        send(.tick)
        takeFixIfNeeded()
    }

    // MARK: Events and effects

    func send(_ event: WeatherReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .fetch(let location, let generation):
                fetch(location, generation: generation)
            case .saveCache(let snapshot):
                cache.save(snapshot)
            case .publish(let display):
                model.display = display
            case .postCompact(let snapshot, let location):
                context.activities.post(WeatherPresentation.activity(snapshot, location: location, unit: reducer.state.config.unit))
            case .endCompact:
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .wake(let date):
                wake.schedule(at: date)
            }
        }
        model.unit = reducer.state.config.unit
    }

    private func fetch(_ location: WeatherLocation, generation: Int) {
        let api = api
        Task { @MainActor [weak self] in
            do {
                let snapshot = try await api.forecast(for: location)
                self?.send(.fetched(snapshot, generation: generation))
            } catch {
                self?.log.notice("Couldn't get the forecast")
                self?.send(.fetchFailed(generation: generation))
            }
        }
    }
}

// MARK: Model

@MainActor
struct WeatherActions {
    var refresh: () -> Void = {}
}

@MainActor
@Observable
final class WeatherModel {
    var display: WeatherDisplay = .noLocation
    var unit: TemperatureUnit = .celsius
    @ObservationIgnored var actions = WeatherActions()

    func reset() {
        display = .noLocation
    }
}

// MARK: Compact and expanded presentation

/// A passive temperature (#51): it never takes the island from a live activity or media.
@MainActor
enum WeatherPresentation {
    static func activity(_ snapshot: WeatherSnapshot, location: WeatherLocation, unit: TemperatureUnit) -> LiveActivity {
        let symbol = snapshot.condition.symbol(isDay: snapshot.isDay)
        let temperature = unit.text(fromCelsius: snapshot.celsius)
        let detail = "\(snapshot.condition.text), high \(unit.text(fromCelsius: snapshot.highCelsius)), low \(unit.text(fromCelsius: snapshot.lowCelsius))"
        return LiveActivity(
            id: WeatherModule.activityID,
            moduleID: WeatherModule.descriptor.id,
            kind: .passive,
            title: "Weather",
            relevance: 0,
            staleDate: snapshot.fetchedAt.addingTimeInterval(WeatherReducer.staleAfter),
            accessibilityLabel: "\(temperature), \(detail), in \(location.name)",
            staleNote: StaleNote(text: "Out of date", symbol: "clock.badge.exclamationmark"),
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 14, weight: .semibold))
                },
                compactTrailing: IslandRegion {
                    Text(temperature).font(IslandFont.compact).monospacedDigit().lineLimit(1)
                },
                minimal: IslandRegion {
                    Text(temperature).font(IslandFont.minimal).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile {
                            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 20, weight: .semibold))
                        }
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion {
                        Text(temperature).font(IslandFont.hero).monospacedDigit().lineLimit(1)
                    },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(snapshot.condition.text).font(IslandFont.title).lineLimit(1)
                            Text("H \(unit.text(fromCelsius: snapshot.highCelsius))  L \(unit.text(fromCelsius: snapshot.lowCelsius)) · \(location.name)")
                                .font(IslandFont.subtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            )
        )
    }
}

// MARK: Today strip

/// Weather's strip across the top of the Today tab.
struct WeatherSectionView: View {
    let model: WeatherModel
    @Environment(\.todayHasColumns) private var hasColumns

    var body: some View {
        switch model.display {
        case .noLocation:
            note("Choose a city in Settings ▸ Weather.")
        case .loading:
            note("Loading weather…")
        case .unavailable:
            note("Weather isn't available right now.")
        case .ready(let snapshot, let location, let isOffline, let isStale):
            strip(snapshot, location: location, isOffline: isOffline, isStale: isStale)
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "cloud.sun")
            .font(IslandFont.subtitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func strip(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool) -> some View {
        let unit = model.unit
        let hours = Array(snapshot.hours.dropFirst().prefix(hasColumns ? 4 : 8))
        return HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 28))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Text(unit.text(fromCelsius: snapshot.celsius))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if isOffline {
                        Image(systemName: "wifi.slash").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityLabel("Offline")
                    }
                }
                Text("\(snapshot.condition.text) · H \(unit.text(fromCelsius: snapshot.highCelsius)) L \(unit.text(fromCelsius: snapshot.lowCelsius))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(footnote(snapshot, location: location, isOffline: isOffline, isStale: isStale))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            HStack(spacing: Spacing.s) {
                ForEach(hours) { hour in
                    HourCell(hour: hour, unit: unit)
                }
            }
        }
        .opacity(isStale ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool) -> String {
        guard isOffline || isStale else { return location.name }
        let age = snapshot.fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return "\(location.name) · Updated \(age)"
    }
}

private struct HourCell: View {
    let hour: HourlyWeather
    let unit: TemperatureUnit

    var body: some View {
        VStack(spacing: 1) {
            Text(hour.time.formatted(.dateTime.hour()))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Image(systemName: WeatherCondition(code: hour.code).symbol(isDay: hour.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
            Text(unit.text(fromCelsius: hour.celsius))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            if let chance = hour.precipitationChance, chance >= 20 {
                Text("\(chance)%").font(.system(size: 8, weight: .medium)).foregroundStyle(.cyan)
            }
        }
        .frame(minWidth: 26)
    }
}

// MARK: Settings

struct WeatherSettingsPane: View {
    @Bindable var settings: WeatherSettings
    let registry: ModuleRegistry
    let permissions: PermissionCenter?

    @State private var query = ""
    @State private var results: [GeocodeResult] = []
    @State private var message: String?
    @State private var isSearching = false

    private let client = OpenMeteoClient()
    private var module: WeatherModule? { registry.module(WeatherModule.descriptor.id) as? WeatherModule }

    var body: some View {
        Form {
            Section {
                Picker("Place", selection: $settings.mode) {
                    Text("A city I choose").tag(WeatherLocationMode.city)
                    Text("My location (approximate)").tag(WeatherLocationMode.device)
                }
                if settings.mode == .device, let permissions {
                    LabeledContent("Location access", value: permissions.status(.location).title)
                    if permissions.status(.location) != .granted {
                        Button("Allow Location…") {
                            Task {
                                await permissions.request(.location)
                                module?.settingsChanged()
                            }
                        }
                    }
                }
            } footer: {
                Text(settings.mode == .city
                     ? "Nothing is asked of macOS. Only the city's rounded coordinates are sent to Open-Meteo."
                     : "macOS is asked for an approximate fix at most once a day, and never tracked. Without permission, the city below is used.")
            }

            Section("City") {
                LabeledContent("Current", value: settings.city?.name ?? "None chosen")
                HStack {
                    TextField("Search for a city", text: $query)
                        .onSubmit { search() }
                    Button("Search", action: search)
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                }
                if let message { Text(message).foregroundStyle(.secondary) }
                ForEach(results) { result in
                    Button {
                        settings.city = result.location
                        results = []
                        query = ""
                        message = nil
                        module?.settingsChanged()
                    } label: {
                        Text(result.label)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Picker("Temperature", selection: $settings.unit) {
                    Text("Follow the system").tag(TemperatureUnitSetting.system)
                    Text("Celsius").tag(TemperatureUnitSetting.celsius)
                    Text("Fahrenheit").tag(TemperatureUnitSetting.fahrenheit)
                }
                Toggle("Show the temperature on the compact island", isOn: $settings.showCompact)
            } footer: {
                Text("The compact temperature never replaces music or a live activity. The forecast refreshes every 30 minutes while Weather is on.")
            }

            Section {
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
            } footer: {
                Text("Open-Meteo's data is licensed CC BY 4.0.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Weather")
        .onChange(of: settings.mode) { module?.settingsChanged() }
        .onChange(of: settings.unit) { module?.settingsChanged() }
        .onChange(of: settings.showCompact) { module?.settingsChanged() }
    }

    private func search() {
        let text = query
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        isSearching = true
        message = nil
        Task {
            do {
                let found = try await client.search(city: text)
                results = found
                message = found.isEmpty ? "No cities found." : nil
            } catch {
                results = []
                message = "Couldn't search. Check your connection."
            }
            isSearching = false
        }
    }
}

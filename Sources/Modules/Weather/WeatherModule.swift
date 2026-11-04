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
    static let tabID = "weather"

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
        model.picker.searcher = { [api] text in try await api.search(city: text) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = WeatherActions(
            refresh: { [weak self] in self?.send(.tick) },
            chooseCity: { [weak self] location in self?.choose(location) },
            setTyping: { [weak self] on in self?.setTyping(on) }
        )
        wake.action = { [weak self] in self?.tick() }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in self?.tick() }
        observers.observe(.NSSystemClockDidChange) { [weak self] in self?.tick() }

        let model = model
        context.services.today.set(TodaySection(
            id: Self.sectionID, moduleID: Self.descriptor.id, slot: .header,
            content: IslandRegion { WeatherSectionView(model: model) }
        ))
        context.activities.setTabs([weatherTab()])
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
        context.services.today.claimKeyboard(Self.sectionID, false)
        context.services.today.remove(moduleID: Self.descriptor.id)
        context.activities.setTabs([])
        context.activities.endAll()
        model.actions = WeatherActions()
        model.reset()
        reducer = WeatherReducer()
    }

    /// The Weather tab: the conditions, and the UV card (ADR-0033).
    private func weatherTab() -> IslandTab {
        let model = model
        return IslandTab(
            id: Self.tabID, moduleID: Self.descriptor.id, title: "Weather", symbol: "sun.max",
            accessibilityLabel: "Weather and UV index", order: 16,
            headerLeading: IslandRegion { WeatherTabHeaderLeading(model: model) },
            headerTrailing: IslandRegion { WeatherTabHeaderTrailing(model: model) }
        ) { WeatherTabView(model: model) }
    }

    /// A city picked in the island: that is the place from now on, even if
    /// the mode was "my location".
    private func choose(_ location: WeatherLocation) {
        settings.city = location
        settings.mode = .city
        settingsChanged()
    }

    /// The city search opened or closed. While it is open the Today tab
    /// captures the keyboard, and the island asks for focus so typing works.
    private func setTyping(_ on: Bool) {
        context.services.today.claimKeyboard(Self.sectionID, on)
        if on { context.services.islandCommands.requestKeyFocus() }
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
                context.activities.post(WeatherPresentation.activity(snapshot, location: location, unit: reducer.state.config.unit, model: model))
            case .endCompact:
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .wake(let date):
                wake.schedule(at: date)
            }
        }
        model.unit = reducer.state.config.unit
        model.showUV = settings.showUV
        model.showUVInToday = settings.showUV && settings.showUVInToday
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
    /// The user picked a city in the island.
    var chooseCity: (WeatherLocation) -> Void = { _ in }
    /// The city search opened (true) or closed: the Today tab claims the keyboard.
    var setTyping: (Bool) -> Void = { _ in }
}

@MainActor
@Observable
final class WeatherModel {
    var display: WeatherDisplay = .noLocation
    var unit: TemperatureUnit = .celsius
    /// The UV card on the Weather tab, and the small reading in the Today strip.
    var showUV = true
    var showUVInToday = true
    /// The inline city search is showing in place of the strip.
    var isChoosingCity = false
    let picker = CitySearchModel()
    @ObservationIgnored var actions = WeatherActions()

    #if DEBUG
    /// DEBUG only (`notched://debug/weather`): a made-up UV, or a made-up forecast, for screenshots.
    var debugUV = WeatherDebugUV.real
    var debugFake = false
    #endif

    /// What the views draw: the real display (a made-up one in DEBUG builds, when asked).
    var shownDisplay: WeatherDisplay {
        #if DEBUG
        return debugAdjusted(display)
        #else
        return display
        #endif
    }

    /// The UV to show, when there is a forecast with one and the settings allow it.
    var uvToShow: (summary: UVSummary, snapshot: WeatherSnapshot)? {
        guard showUV, case .ready(let snapshot, _, _, _) = shownDisplay, let uv = snapshot.uv else { return nil }
        return (uv, snapshot)
    }

    func reset() {
        display = .noLocation
        isChoosingCity = false
        picker.reset()
    }

    func openPicker() {
        picker.reset()
        isChoosingCity = true
        actions.setTyping(true)
    }

    func closePicker() {
        guard isChoosingCity else { return }
        isChoosingCity = false
        picker.reset()
        actions.setTyping(false)
    }

    func choose(_ result: GeocodeResult) {
        closePicker()
        actions.chooseCity(result.location)
    }
}

// MARK: Compact and expanded presentation

/// A passive temperature (#51): it never takes the island from a live activity or media.
@MainActor
enum WeatherPresentation {
    static func activity(_ snapshot: WeatherSnapshot, location: WeatherLocation, unit: TemperatureUnit, model: WeatherModel) -> LiveActivity {
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
                    // Beside the camera housing: where, and whether to expect rain.
                    leading: ExpandedRegion {
                        // The pin goes first when the region is narrow (Expanded size 85–100%).
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill").font(.system(size: 10, weight: .semibold)).dimmedText(0.7)
                                Text(verbatim: location.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            }
                            Text(verbatim: location.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                    },
                    trailing: WeatherLook.rainChance(in: Array(snapshot.hours.dropFirst().prefix(6))).map { chance in
                        ExpandedRegion {
                            Label("\(chance)%", systemImage: "umbrella.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.cyan)
                                .accessibilityLabel("\(chance) percent chance of rain")
                        }
                    },
                    center: ExpandedRegion { WeatherActivityBody(snapshot: snapshot, unit: unit, model: model) }
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
    /// A glass theme gives the strip its card; Notch Black has none, so the strip sits straight on the black.
    @Environment(\.islandSurfaceIsGlass) private var surfaceIsGlass
    /// On Notch Black at 110%+ the weather wraps around the camera housing instead of sitting in a strip below it.
    @Environment(\.notchWrap) private var wrap

    var body: some View {
        if model.isChoosingCity {
            CityPickerView(model: model)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.shownDisplay {
        case .noLocation:
            HStack(spacing: Spacing.m) {
                Label("No city chosen yet.", systemImage: "cloud.sun")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Choose City") { model.openPicker() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 26)
                    .background(.white.opacity(0.16), in: Capsule())
                    .accessibilityHint("Search for a city to show its weather")
            }
        case .loading:
            note("Loading weather…")
        case .unavailable:
            note("Weather isn't available right now.")
        case .ready(let snapshot, let location, let isOffline, let isStale):
            if let wrap {
                wrapped(snapshot, location: location, isOffline: isOffline, isStale: isStale, wrap: wrap)
            } else {
                strip(snapshot, location: location, isOffline: isOffline, isStale: isStale)
            }
        }
    }

    /// The city line: tapping it changes the city.
    private func cityButton(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool) -> some View {
        Button { model.openPicker() } label: {
            HStack(spacing: 2) {
                Text(footnote(snapshot, location: location, isOffline: isOffline, isStale: isStale))
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 10))
            .dimmedText(0.65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(location.name). Change city")
    }

    /// Everything the strip shows, split around the camera housing: the conditions on the left,
    /// the hours on the right, the middle clear. Pulled up into the row beside the notch, so the
    /// Calendar and Reminders columns start higher and the island is shorter.
    private func wrapped(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool, wrap: NotchWrap) -> some View {
        let unit = model.unit
        let upcoming = Array(snapshot.hours.dropFirst())
        func hoursRow(_ count: Int) -> some View {
            HStack(spacing: Spacing.s) {
                ForEach(upcoming.prefix(count)) { hour in
                    WeatherHourColumn(hour: hour, unit: unit)
                }
            }
        }
        return HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 30))
                    .frame(width: 34)
                    .background {
                        Circle().fill(WeatherLook.tint(code: snapshot.code, isDay: snapshot.isDay).color.opacity(0.28))
                            .frame(width: 60, height: 60).blur(radius: 14).allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Spacing.xs) {
                        Text(unit.text(fromCelsius: snapshot.celsius))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if isOffline {
                            Image(systemName: "wifi.slash").font(.system(size: 10)).foregroundStyle(.secondary).accessibilityLabel("Offline")
                        }
                    }
                    Text(snapshot.condition.text)
                        .font(.system(size: 11))
                        .dimmedText(0.85)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("H \(unit.text(fromCelsius: snapshot.highCelsius)) L \(unit.text(fromCelsius: snapshot.lowCelsius))")
                        .font(.system(size: 10))
                        .dimmedText(0.7)
                        .lineLimit(1)
                    cityButton(snapshot, location: location, isOffline: isOffline, isStale: isStale)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: wrap.gap)
            // The hours that don't fit are dropped (four at most, down to two).
            // The column beside the notch is too narrow for the UV reading, so it sits above the hours on this side.
            VStack(alignment: .trailing, spacing: 3) {
                if let uv = todayUV(snapshot) { UVChip(uv: uv) }
                ViewThatFits(in: .horizontal) {
                    hoursRow(4)
                    hoursRow(3)
                    hoursRow(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .opacity(isStale ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        // Up into the row beside the notch; the layout shrinks by the same amount, so what follows moves up too.
        .padding(.top, -wrap.rise)
    }

    /// UV for the Today strip: only with the settings on and a reading in the forecast.
    private func todayUV(_ snapshot: WeatherSnapshot) -> UVSummary? {
        model.showUVInToday ? snapshot.uv : nil
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "cloud.sun")
            .font(IslandFont.subtitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func strip(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool) -> some View {
        let unit = model.unit
        let upcoming = Array(snapshot.hours.dropFirst())
        // The temperature and conditions come first; the hours that don't fit are dropped
        // (fewer at a small Expanded size).
        let counts = hasColumns ? (4, 3, 2) : (8, 6, 4)
        func hoursRow(_ count: Int) -> some View {
            HStack(spacing: Spacing.s) {
                ForEach(upcoming.prefix(count)) { hour in
                    WeatherHourColumn(hour: hour, unit: unit)
                }
            }
        }
        return HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 30))
                .frame(width: 36)
                .background {
                    Circle().fill(WeatherLook.tint(code: snapshot.code, isDay: snapshot.isDay).color.opacity(0.28))
                        .frame(width: 60, height: 60).blur(radius: 14).allowsHitTesting(false)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Text(unit.text(fromCelsius: snapshot.celsius))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if isOffline {
                        Image(systemName: "wifi.slash").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityLabel("Offline")
                    }
                }
                // The small UV reading follows the high and low when there is room; without room it goes.
                let detail = Text("\(snapshot.condition.text) · H \(unit.text(fromCelsius: snapshot.highCelsius)) L \(unit.text(fromCelsius: snapshot.lowCelsius))")
                    .font(.system(size: 11))
                    .dimmedText(0.75)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let uv = todayUV(snapshot) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { detail; Text("·").font(.system(size: 11)).dimmedText(0.75); UVChip(uv: uv) }
                        detail
                    }
                } else {
                    detail
                }
                cityButton(snapshot, location: location, isOffline: isOffline, isStale: isStale)
            }
            Spacer(minLength: Spacing.s)
            ViewThatFits(in: .horizontal) {
                hoursRow(counts.0)
                hoursRow(counts.1)
                hoursRow(counts.2)
            }
            .layoutPriority(-1)
        }
        .padding(.horizontal, surfaceIsGlass ? 12 : 0)
        .padding(.vertical, 8)
        .background(surfaceIsGlass ? Color.white.opacity(0.06) : Color.clear, in: .rect(cornerRadius: 14, style: .continuous))
        .opacity(isStale ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private func footnote(_ snapshot: WeatherSnapshot, location: WeatherLocation, isOffline: Bool, isStale: Bool) -> String {
        guard isOffline || isStale else { return location.name }
        let age = snapshot.fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return "\(location.name) · Updated \(age)"
    }
}

// MARK: Settings

struct WeatherSettingsPane: View {
    @Bindable var settings: WeatherSettings
    let registry: ModuleRegistry
    let permissions: PermissionCenter?

    @State private var picker = CitySearchModel(searcher: { try await OpenMeteoClient().search(city: $0) })

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
                    TextField("Search for a city", text: Binding(get: { picker.query }, set: { picker.query = $0 }))
                        .onSubmit { Task { await picker.search() } }
                    Button("Search") { Task { await picker.search() } }
                        .disabled(!picker.canSearch)
                }
                if let message = picker.message { Text(message).foregroundStyle(.secondary) }
                ForEach(picker.results) { result in
                    Button {
                        settings.city = result.location
                        settings.mode = .city
                        picker.reset()
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
                Toggle("Show UV index", isOn: $settings.showUV)
                Toggle("Show UV in Today", isOn: $settings.showUVInToday)
                    .disabled(!settings.showUV)
            } header: {
                Text("UV index")
            } footer: {
                Text("A UV card on the Weather tab and a small reading in the Today strip. It comes from the same forecast, so there are no extra requests.")
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
        .onChange(of: settings.showUV) { module?.settingsChanged() }
        .onChange(of: settings.showUVInToday) { module?.settingsChanged() }
        .task(id: picker.query) { await picker.searchAfterPause() }
    }
}

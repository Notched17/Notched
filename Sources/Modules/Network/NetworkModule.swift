// SPDX-License-Identifier: GPL-3.0-or-later

import CoreWLAN
import Network
import Observation
import SwiftUI

/// Network (#29): a banner when the Mac moves between Wi-Fi, Ethernet and a
/// Personal Hotspot, or goes offline. `NWPathMonitor` delivers each path on
/// a utility queue; `NetworkReducer` keeps flapping quiet. The Wi-Fi name is
/// optional, because macOS only gives it to apps allowed to use Location.
@MainActor
final class NetworkModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "network",
        name: "Network",
        symbol: "wifi",
        summary: "A short banner when your Mac switches between Wi-Fi, Ethernet and a Personal Hotspot, or goes offline.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(NetworkSettingsPane(settings: context.settings.network, permissions: context.registry.host.services.permissions))
    }

    private let context: ModuleContext
    private let settings: NetworkSettings
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "me.rkck.Notched.network-path", qos: .utility)
    private let wakeTimer = OneShotTimer()
    private var reducer = NetworkReducer()
    private var isRunning = false
    /// The latest path, before the Wi-Fi name is added.
    private var path: NetworkState?

    init(context: ModuleContext) {
        self.context = context
        settings = context.settings.network
    }

    /// True while the path monitor runs (tests check `stop()` cancels it).
    var isMonitoring: Bool { monitor != nil }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        wakeTimer.action = { [weak self] in self?.send(.tick) }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.state(of: path)
            Task { @MainActor [weak self] in self?.pathChanged(state) }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
        observeSettings()
    }

    func stop() {
        isRunning = false
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
        wakeTimer.schedule(at: nil)
        reducer = NetworkReducer()
        path = nil
        context.activities.endAll()
    }

    /// How the Mac is connected. An expensive path is a Personal Hotspot
    /// (Wi-Fi or USB from an iPhone).
    nonisolated static func state(of path: NWPath) -> NetworkState {
        guard path.status == .satisfied else { return .offline }
        if path.isExpensive { return .hotspot }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.wifi) { return .wifi(name: nil) }
        if path.usesInterfaceType(.cellular) { return .hotspot }
        return .other
    }

    private func pathChanged(_ state: NetworkState) {
        guard isRunning else { return }
        path = state
        send(.path(named(state)))
    }

    /// Adds the Wi-Fi network's name when the user asked for it. macOS
    /// returns no name without Location access, so the banner then says
    /// Connected. (Not gated on PermissionCenter's cached status: it's read
    /// once at launch, before Location answers, and was stale on 27.2.)
    private func named(_ state: NetworkState) -> NetworkState {
        guard case .wifi = state, settings.showWiFiName else { return state }
        return .wifi(name: CWWiFiClient.shared().interface()?.ssid())
    }

    private func observeSettings() {
        guard isRunning else { return }
        withObservationTracking {
            _ = settings.showWiFiName
            _ = context.services.permissions?.status(.location)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeSettings()
                // Learning or losing the name is silent (NetworkReducer).
                if let self, let path = self.path { self.send(.path(self.named(path))) }
            }
        }
    }

    private func send(_ event: NetworkReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .wake(let date): wakeTimer.schedule(at: date)
            case .banner(let state): context.activities.show(Self.banner(state))
            }
        }
    }

    static func banner(_ state: NetworkState) -> TransientBanner {
        let content: BannerContent
        let spoken: String
        switch state {
        case .wifi(let name):
            content = BannerContent(symbol: "wifi", value: name ?? "Connected")
            spoken = name.map { "Wi-Fi, connected to \($0)" } ?? "Wi-Fi connected"
        case .ethernet:
            content = BannerContent(symbol: "cable.connector", value: "Ethernet")
            spoken = "Ethernet connected"
        case .hotspot:
            content = BannerContent(symbol: "personalhotspot", symbolTint: .green, value: "Hotspot")
            spoken = "Connected to a Personal Hotspot"
        case .other:
            content = BannerContent(symbol: "network", value: "Connected")
            spoken = "Network connected"
        case .offline:
            content = BannerContent(symbol: "wifi.slash", symbolTint: .orange, value: "Offline")
            spoken = "Offline"
        }
        return .standard(id: "network", moduleID: descriptor.id, content: content, accessibilityLabel: spoken)
    }
}

/// Network's settings (Settings ▸ Modules ▸ Network), persisted under `network.*`.
@MainActor
@Observable
final class NetworkSettings {
    enum Key {
        static let showWiFiName = "network.showWiFiName"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Needs Location: macOS only gives Wi-Fi names to apps allowed to use it.
    var showWiFiName: Bool { didSet { defaults.set(showWiFiName, forKey: Key.showWiFiName) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showWiFiName = defaults.object(forKey: Key.showWiFiName) as? Bool ?? false
    }
}

/// Settings ▸ Modules ▸ Network.
struct NetworkSettingsPane: View {
    @Bindable var settings: NetworkSettings
    let permissions: PermissionCenter?

    var body: some View {
        Form {
            Section {
                Toggle("Show the Wi-Fi network's name", isOn: Binding(
                    get: { settings.showWiFiName },
                    set: { isOn in
                        settings.showWiFiName = isOn
                        if isOn, let permissions, permissions.status(.location) != .granted {
                            Task { await permissions.request(.location) }
                        }
                    }
                ))
                if settings.showWiFiName, let permissions, permissions.status(.location) == .denied {
                    LabeledContent {
                        Button("Open System Settings…") { permissions.openSystemSettings(for: .location) }
                    } label: {
                        Label("Location is off for Notched", systemImage: "location.slash.fill")
                        Text("The banner says “Connected” until you allow it.")
                    }
                }
            } footer: {
                Text("macOS only shares Wi-Fi names with apps allowed to use Location. Notched reads the name when the network changes, never your location.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Network")
    }
}

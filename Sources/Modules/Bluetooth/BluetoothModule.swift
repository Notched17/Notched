// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Bluetooth (#27): a banner when a Bluetooth device connects or
/// disconnects. Audio devices come from the shared CoreAudio output list;
/// keyboards, mice, trackpads and controllers from the I/O Registry. Neither
/// needs a permission. A thin shell around `BluetoothReducer`.
@MainActor
final class BluetoothModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "bluetooth",
        name: "Bluetooth",
        symbol: "headphones",
        summary: "A short banner when AirPods, headphones, a keyboard, mouse or trackpad connects or disconnects.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(BluetoothSettingsPane(settings: context.settings.bluetooth))
    }

    private let context: ModuleContext
    private let settings: BluetoothSettings
    /// Shared with Now Playing; held only while this module runs.
    private let outputs: AudioOutputService
    private var holdsOutputs = false
    private let accessories = BluetoothHIDMonitor()
    private let wakeTimer = OneShotTimer()
    private var reducer = BluetoothReducer()
    private var isRunning = false
    private var watchesAccessories = false

    init(context: ModuleContext) {
        self.context = context
        settings = context.settings.bluetooth
        outputs = context.services.audioOutputs
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        wakeTimer.action = { [weak self] in self?.send(.tick) }
        accessories.onChange = { [weak self] devices in self?.send(.devices(.input, devices)) }
        outputs.acquire()
        holdsOutputs = true
        observeAudio()
        observeSettings()
    }

    func stop() {
        isRunning = false
        accessories.stop()
        accessories.onChange = { _ in }
        watchesAccessories = false
        if holdsOutputs {
            holdsOutputs = false
            outputs.release()
        }
        wakeTimer.schedule(at: nil)
        reducer = BluetoothReducer()
        context.activities.endAll()
    }

    // MARK: Sources

    private func observeAudio() {
        guard isRunning else { return }
        let devices = withObservationTracking {
            outputs.devices
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAudio() }
        }
        send(.devices(.audio, Self.audioDevices(devices)))
    }

    private func observeSettings() {
        guard isRunning else { return }
        let include = withObservationTracking {
            settings.includeAccessories
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSettings() }
        }
        guard include != watchesAccessories else { return }
        watchesAccessories = include
        // Start over so the change itself announces nothing: each source's
        // first list is silent.
        reducer = BluetoothReducer()
        wakeTimer.schedule(at: nil)
        send(.devices(.audio, Self.audioDevices(outputs.devices)))
        if include { accessories.start() } else { accessories.stop() }
    }

    static func audioDevices(_ devices: [AudioOutputDevice]) -> [BluetoothDevice] {
        devices.filter { $0.transport == .bluetooth }.map {
            BluetoothDevice(address: BluetoothDevice.normalizedAddress(in: $0.uid), name: $0.name, kind: .audio(symbol: $0.symbol))
        }
    }

    // MARK: Effects

    private func send(_ event: BluetoothReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .wake(let date):
                wakeTimer.schedule(at: date)
            case .banner(let banner):
                if case .disconnected = banner, !settings.announceDisconnects { continue }
                context.activities.show(Self.banner(banner))
            }
        }
    }

    static func banner(_ banner: BluetoothReducer.Banner) -> TransientBanner {
        switch banner {
        case .connected(let device):
            .standard(id: "bluetooth.\(device.key)", moduleID: descriptor.id, content: BannerContent(
                symbol: device.symbol, value: BluetoothDevice.displayName(device.name)
            ), accessibilityLabel: "\(device.name) connected")
        case .disconnected(let device):
            .standard(id: "bluetooth.\(device.key)", moduleID: descriptor.id, content: BannerContent(
                symbol: device.symbol, value: BluetoothDevice.displayName(device.name), isDimmed: true
            ), priority: .low, accessibilityLabel: "\(device.name) disconnected")
        }
    }
}

/// Settings ▸ Modules ▸ Bluetooth.
struct BluetoothSettingsPane: View {
    @Bindable var settings: BluetoothSettings

    var body: some View {
        Form {
            Section {
                Toggle("Keyboards, mice and trackpads", isOn: $settings.includeAccessories)
                Toggle("Show when a device disconnects", isOn: $settings.announceDisconnects)
            } footer: {
                Text("Headphones and speakers always show. Notched reads which devices are connected from macOS itself, so it doesn't need Bluetooth permission.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bluetooth")
    }
}

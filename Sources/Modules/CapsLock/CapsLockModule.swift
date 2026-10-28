// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Caps Lock (#25): a banner when Caps Lock turns on or off. It watches
/// modifier-key changes with an `NSEvent` monitor; `CapsLockReducer`
/// ignores every other modifier. It never uses Input Monitoring.
@MainActor
final class CapsLockModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "capslock",
        name: "Caps Lock",
        symbol: "capslock.fill",
        summary: "A short banner when Caps Lock turns on or off.",
        permissions: [],
        isDebugOnly: false
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(CapsLockSettingsPane(permissions: context.registry.host.services.permissions))
    }

    private let context: ModuleContext
    private var reducer = CapsLockReducer()
    private var monitors: [Any] = []
    private let log = Log.module("capslock")

    /// True while the event monitors are installed.
    var isRunning: Bool { !monitors.isEmpty }

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard monitors.isEmpty else { return }
        reducer.seed(NSEvent.modifierFlags.contains(.capsLock))
        // Other apps' key events, and our own (the Settings window).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.flagsChanged(event.modifierFlags)
        }) {
            monitors.append(global)
        } else {
            log.error("Couldn't watch modifier keys")
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.flagsChanged(event.modifierFlags)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        reducer = CapsLockReducer()
        context.activities.endAll()
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        for effect in reducer.reduce(capsLock: flags.contains(.capsLock)) {
            switch effect {
            case .banner(let isOn): context.activities.show(Self.banner(isOn: isOn))
            }
        }
    }

    static func banner(isOn: Bool) -> TransientBanner {
        .standard(id: "capslock", moduleID: descriptor.id, content: BannerContent(
            symbol: isOn ? "capslock.fill" : "capslock",
            symbolTint: isOn ? .green : .white.opacity(0.7),
            value: isOn ? "On" : "Off"
        ), accessibilityLabel: isOn ? "Caps Lock on" : "Caps Lock off")
    }
}

/// Settings ▸ Modules ▸ Caps Lock.
struct CapsLockSettingsPane: View {
    let permissions: PermissionCenter?

    var body: some View {
        Form {
            Section {
                LabeledContent("Shows", value: "Caps Lock On and Off")
            } footer: {
                Text("Notched watches only the Caps Lock key. It never sees what you type.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Caps Lock")
    }
}

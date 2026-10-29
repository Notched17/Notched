// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Settings ▸ Modules ▸ Volume & Brightness: whether the HUD is running, the
/// off switch, and the one permission it needs.
struct HUDSettingsPane: View {
    let settings: HUDSettings
    let registry: ModuleRegistry
    let permissions: PermissionCenter?

    private var module: HUDModule? { registry.module(HUDModule.descriptor.id) as? HUDModule }
    private var accessibility: PermissionStatus { permissions?.status(.accessibility) ?? .notDetermined }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(statusText).foregroundStyle(.secondary)
                }
                if let latch = settings.latch {
                    LabeledContent("Turned off because") {
                        Text(Self.reason(latch.reason)).foregroundStyle(.secondary)
                    }
                    Button("Turn Back On") { turnBackOn() }
                }
                Toggle("Pause HUD replacement", isOn: pausedBinding)
            } header: {
                Text("Volume")
            } footer: {
                Text("While it's paused or turned off, the volume keys work as they always did and macOS shows its own HUD. The same switch is in the Notched menu in the menu bar.")
            }

            Section {
                LabeledContent {
                    HStack(spacing: Spacing.m) {
                        PermissionStatusBadge(status: accessibility)
                        if accessibility != .granted {
                            Button(accessibility == .denied ? "Open System Settings" : "Allow…") {
                                Task { await permissions?.request(.accessibility) }
                            }
                            .controlSize(.small)
                        }
                    }
                } label: {
                    Label("Accessibility", systemImage: Permission.accessibility.symbol)
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Notched listens only for the volume and brightness keys, and never sees what you type. Without Accessibility it can't, so macOS keeps showing its own HUD.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Volume & Brightness")
        .onAppear { permissions?.refresh() }
    }

    private var statusText: String {
        guard let module else { return "Off" }
        switch module.status {
        case .running: return "On: the island shows volume changes"
        case .paused: return "Paused: macOS shows its own HUD"
        case .latched: return "Turned off after a problem"
        case .notAllowed: return "Needs Accessibility"
        }
    }

    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { settings.isPaused },
            set: { paused in
                if let module { module.setPaused(paused) } else { settings.isPaused = paused }
            }
        )
    }

    private func turnBackOn() {
        if let module {
            module.turnBackOn()
        } else {
            settings.latch = nil
            settings.uncleanStreak = 0
            settings.isPaused = false
        }
    }

    private static func reason(_ reason: HUDStopReason) -> String {
        switch reason {
        case .timeouts: "macOS switched the key listener off twice in a short time."
        case .slowCallbacks: "Handling the keys was too slow."
        case .permissionRevoked: "Accessibility was turned off."
        case .uncleanExits: "Notched quit unexpectedly twice while the HUD was on."
        }
    }
}

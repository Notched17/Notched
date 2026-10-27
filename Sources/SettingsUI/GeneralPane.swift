// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            } footer: {
                if launchAtLogin.requiresApproval {
                    HStack {
                        Text("Allow DynamicNotch in Login Items to finish turning this on.")
                        Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
                            .buttonStyle(.link)
                    }
                } else if let error = launchAtLogin.lastError {
                    Text(error)
                }
            }

            Section {
                Picker("Show the island on", selection: $settings.displaySelection) {
                    Text("Main Display").tag(DisplaySelection.main)
                    Text("All Displays").tag(DisplaySelection.all)
                    let screens = connectedScreens
                    if !screens.isEmpty { Divider() }
                    ForEach(screens, id: \.id) { screen in
                        Text(screen.name).tag(DisplaySelection.specific(screen.id))
                    }
                    if case .specific(let id) = settings.displaySelection, !screens.contains(where: { $0.id == id }) {
                        Text("Disconnected Display").tag(settings.displaySelection)
                    }
                }
            } footer: {
                Text("Main Display is your Mac's built-in notched screen, or the primary display when it's closed.")
            }

            Section {
                Toggle("Expand when the pointer rests on the island", isOn: $settings.expandOnHover)
                Toggle("Hide when an app is full screen", isOn: $settings.hideInFullscreen)
                Toggle("Haptic feedback on Force Touch trackpads", isOn: $settings.hapticsEnabled)
            }

            Section {
                Toggle("Hide from screenshots and screen sharing", isOn: $settings.hideFromScreenCapture)
            } footer: {
                Text("Some screen-recording apps can still capture the island.")
            }

            Section {
                Toggle("Pause the island", isOn: $settings.isPaused)
            } footer: {
                Text("Hides the island on every display. Resume it here or from the menu bar.")
            }

            #if DEBUG
            Section("Developer") {
                Toggle("Show the pill on notched displays", isOn: $settings.debugForcePill)
            }
            #endif
        }
        .formStyle(.grouped)
    }

    private var connectedScreens: [(id: DisplayID, name: String)] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { ($0, screen.localizedName) }
        }
    }
}

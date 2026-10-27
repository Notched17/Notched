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
                        Text("Allow Notched in Login Items to finish turning this on.")
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
                Toggle("Keep showing while media plays", isOn: $settings.keepShowingForMedia)
                    .disabled(!settings.hideInFullscreen)
                    .help("Over a fullscreen app, Now Playing stays on the island, unless the fullscreen app is the one playing.")
                Toggle("Haptic feedback on Force Touch trackpads", isOn: $settings.hapticsEnabled)
            }

            Section {
                Picker("Several activities", selection: $settings.multipleActivities) {
                    ForEach(CompactLayout.Mode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Clicking an activity", selection: $settings.clickBehavior) {
                    ForEach(ClickBehavior.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Expand the island for alerts", isOn: $settings.alertExpansion)
                LabeledSlider(
                    title: "Alert duration", value: $settings.alertDuration,
                    range: SettingsStore.alertDurationRange, step: 0.5
                ) { String(format: "%.1f s", $0) }
                .disabled(!settings.alertExpansion)
                LabeledSlider(
                    title: "Banner duration", value: $settings.bannerDuration,
                    range: SettingsStore.bannerDurationRange, step: 0.25
                ) { String(format: "%.2f s", $0) }
                Picker("Keep ended activities", selection: $settings.recentRetention) {
                    ForEach(RecentRetention.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Live Activities")
            } footer: {
                Text("Bubbles show extra activities as small circles beside the island, like iPhone. Side by side shares the island between two activities, like iPhone 18 Pro. Ended activities stay in the island's list for the time you choose.")
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

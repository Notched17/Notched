// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Lock Screen (#59, #13b): a small card on the lock screen with what's
/// playing, a lyric line, the battery and the next event. **Experimental.**
///
/// A thin shell. `LockScreenReducer` owns the lifecycle and every safety rule
/// (ADR-0031): the card exists only while the screen is confirmed locked, never
/// takes the keyboard, never covers the password field, and turns the feature
/// off on any failure or crash. Off by default, and while off it creates and
/// observes nothing.
@MainActor
final class LockScreenModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "lockscreen",
        name: "Lock Screen",
        symbol: "lock.rectangle",
        summary: "Experimental. A small card on the lock screen with what's playing, the battery and your next event. It never takes the keyboard and removes itself the moment you unlock.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: false
    )

    /// The crash rule applies once per launch: after it turns the feature off,
    /// turning it back on on purpose must not trip it again.
    private static var crashRuleSpent = false

    static var isAvailable: Bool { SkyLightLockScreen.isAvailable }

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(LockScreenSettingsPane(settings: context.settings.lockScreen))
    }

    private let context: ModuleContext
    private let log = Log.module("lockscreen")
    private let info = LockScreenInfo()
    private var controller: LockScreenController?
    private var isRunning = false

    private var settings: LockScreenSettings { context.settings.lockScreen }

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let controller = LockScreenController { [weak self] _ in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(LockScreenCardView(options: self.settings.options, nowPlaying: self.context.services.nowPlaying, info: self.info))
        }
        controller.placement = { [weak self] in self?.settings.placement ?? LockScreenGeometry.Placement() }
        controller.currentConfig = { [weak self] in self?.config() ?? LockScreenReducer.Config() }
        controller.onTurnOff = { [weak self] reason in self?.turnOff(reason) }
        self.controller = controller

        controller.apply(config())
        // The first start in this launch hears about the last session; later ones don't.
        let crashed = context.previousSessionCrashed && !Self.crashRuleSpent
        Self.crashRuleSpent = true
        controller.launch(previousSessionCrashed: crashed)
        observeSettings()
        log.info("Lock screen card armed")
    }

    func stop() {
        isRunning = false
        // Off: destroys the card if one is showing, and stops listening.
        controller?.apply(LockScreenReducer.Config())
        controller = nil
        info.release()
    }

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Disable Lock Screen Widgets") { [weak self] in
            self?.context.settings.enabledModules.remove(Self.descriptor.id)
        }]
    }

    /// The reducer's configuration, from the settings, the kill switches and
    /// the Mac's accounts. Read at start, when settings change, and on every lock.
    private func config() -> LockScreenReducer.Config {
        var config = LockScreenReducer.Config()
        config.enabled = isRunning
        config.killSwitch = LockScreenKillSwitch.isActive(arguments: ProcessInfo.processInfo.arguments, defaults: .standard)
        config.includeSecondaryScreens = settings.otherDisplays
        config.allowWithOtherAccounts = settings.otherAccounts
        config.otherAccountsExist = LocalAccounts.otherLoginAccountsExist()
        return config
    }

    private func observeSettings() {
        guard isRunning else { return }
        withObservationTracking {
            _ = settings.otherDisplays
            _ = settings.otherAccounts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.controller?.apply(self.config())
                self.observeSettings()
            }
        }
    }

    /// The reducer turned the feature off: say why, and switch the module off.
    private func turnOff(_ reason: LockScreenReducer.OffReason) {
        log.error("Lock screen widgets turned themselves off: \(String(describing: reason), privacy: .public)")
        settings.lastOffReason = reason.explanation
        context.settings.enabledModules.remove(Self.descriptor.id)
    }
}

struct LockScreenSettingsPane: View {
    @Bindable var settings: LockScreenSettings

    var body: some View {
        Form {
            if let reason = settings.lastOffReason {
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }

            Section {
                Toggle("Track and artist", isOn: $settings.showTrack)
                Toggle("Artwork", isOn: $settings.showArtwork)
                    .disabled(!settings.showTrack)
                Toggle("Lyric line", isOn: $settings.showLyrics)
                    .disabled(!settings.showTrack)
                Toggle("Battery", isOn: $settings.showBattery)
                Toggle("Next event", isOn: $settings.showEvent)
                Toggle("Event title", isOn: $settings.showEventTitle)
                    .disabled(!settings.showEvent)
            } header: {
                Text("Show")
            } footer: {
                Text("Anyone who can see the screen can read the card. Event titles and lyrics are off until you turn them on; the next event otherwise reads \"Event in 12 min\". Now Playing items need the Now Playing module (and its lyrics setting for the lyric line); the next event needs calendar access from the Calendar module.")
            }

            Section {
                Picker("Style", selection: $settings.style) {
                    ForEach(LockScreenCardStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: $settings.size) {
                    ForEach(LockScreenGeometry.Size.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Solid stays readable over any wallpaper. Liquid Glass is the system material, darkened a little for the white text; if it is ever hard to read, switch back to Solid. Large sits a little above the middle so it stays clear of the password area. Both take effect the next time you lock.")
            }

            Section {
                Picker("Height", selection: $settings.vertical) {
                    ForEach(LockScreenGeometry.Placement.Vertical.allCases) { Text($0.title).tag($0) }
                }
                Picker("Side", selection: $settings.horizontal) {
                    ForEach(LockScreenGeometry.Placement.Horizontal.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Position")
            } footer: {
                Text("The card always stays in the upper part of the screen, well clear of the password field and the user list. It takes effect the next time you lock.")
            }

            Section {
                Toggle("Also on other displays", isOn: $settings.otherDisplays)
                Toggle("Show when this Mac has other user accounts", isOn: $settings.otherAccounts)
            } footer: {
                Text("Both are off by default. With other accounts on this Mac, nothing is shown unless the second switch is on.")
            }

            Section {
                Text("If the lock screen ever looks wrong, type your password as usual: the card never takes the keyboard. To switch it off from another Mac, run  defaults write me.rkck.Notched lockScreen.killSwitch -bool true  or open Notched with  --no-lock-screen. The menu bar item “Disable Lock Screen Widgets” also turns it off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("If something goes wrong")
            }
        }
        .formStyle(.grouped)
    }
}

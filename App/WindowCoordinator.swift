// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Opens the app's ordinary windows. The app has no Dock icon, so opening a
/// window also activates the app (ADR-0001).
@MainActor
final class WindowCoordinator {
    private let environment: AppEnvironment
    private let settingsNavigation = SettingsNavigation()
    private var settingsWindow: NSWindow?
    var showWelcome: () -> Void = {}

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsNavigation.selection = pane }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let context = SettingsContext(
            settings: environment.settings,
            modules: environment.modules.descriptors,
            showWelcome: { [weak self] in self?.showWelcome() }
        )
        let controller = NSHostingController(rootView: SettingsRootView(navigation: settingsNavigation, context: context))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentMinSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("DynamicNotchSettings")
        trackTitle(of: window)
        return window
    }

    /// Like System Settings, the title bar shows the selected pane.
    private func trackTitle(of window: NSWindow) {
        withObservationTracking {
            window.title = settingsNavigation.selection.title
        } onChange: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                self.trackTitle(of: window)
            }
        }
    }
}

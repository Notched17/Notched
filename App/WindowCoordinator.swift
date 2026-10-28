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
    private var onboardingWindow: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func showSettings(_ pane: SettingsPane? = nil, module: ModuleID? = nil) {
        if let pane { settingsNavigation.selection = pane }
        if let module {
            settingsNavigation.selection = .modules
            settingsNavigation.modulePath = [module]
        }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let context = SettingsContext(
            settings: environment.settings,
            modules: environment.modules.descriptors,
            registry: environment.modules,
            permissions: environment.permissions,
            scheduler: environment.scheduler,
            launchAtLogin: environment.launchAtLogin,
            accessibility: environment.accessibility,
            showWelcome: { [weak self] in self?.showOnboarding() }
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
        window.setFrameAutosaveName("NotchedSettings")
        trackTitle(of: window)
        return window
    }

    /// The first-run walkthrough. Shown at first launch and from About.
    func showOnboarding(startAt step: OnboardingView.Step = .welcome) {
        if let onboardingWindow, step == .welcome {
            NSApp.activate()
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(
            settings: environment.settings,
            modules: environment.modules.descriptors,
            permissions: environment.permissions,
            scheduler: environment.scheduler,
            launchAtLogin: environment.launchAtLogin,
            startAt: step,
            finish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        onboardingWindow?.close()
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Notched"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Like System Settings, the title bar shows the selected pane.
    private func trackTitle(of window: NSWindow) {
        withObservationTracking {
            let navigation = settingsNavigation
            let module = navigation.selection == .modules ? navigation.modulePath.last : nil
            window.title = module.flatMap { id in environment.modules.descriptors.first { $0.id == id }?.name }
                ?? navigation.selection.title
        } onChange: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                self.trackTitle(of: window)
            }
        }
    }
}

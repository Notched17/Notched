// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The menu-bar status item. It must always offer Settings, Pause island and Quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let environment: AppEnvironment
    private let windows: WindowCoordinator
    private let pauseItem = NSMenuItem(title: "Pause Island", action: #selector(togglePause), keyEquivalent: "")

    init(environment: AppEnvironment, windows: WindowCoordinator) {
        self.environment = environment
        self.windows = windows
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "DynamicNotch")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [weak self] in self?.windows.showSettings() })
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "About DynamicNotch") { [weak self] in self?.windows.showSettings(.about) })

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(DebugMenu.make(environment: environment))
        #endif

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DynamicNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.state = environment.settings.isPaused ? .on : .off
    }

    @objc private func togglePause() {
        environment.settings.isPaused.toggle()
    }
}

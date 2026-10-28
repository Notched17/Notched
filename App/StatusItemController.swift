// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The menu-bar status item. It must always offer Settings, Pause island and Quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let environment: AppEnvironment
    private let windows: WindowCoordinator
    private let pauseItem = NSMenuItem(title: "Pause Island", action: #selector(togglePause), keyEquivalent: "")
    /// Shown only in safe mode, after repeated crashes at launch.
    private let resumeModulesItem = NSMenuItem(title: "Resume Modules", action: #selector(resumeModules), keyEquivalent: "")
    /// Items the running modules add (Keep Awake ▸, Timer ▸), rebuilt each time the menu opens.
    private var moduleItems: [NSMenuItem] = []

    init(environment: AppEnvironment, windows: WindowCoordinator) {
        self.environment = environment
        self.windows = windows
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Notched")
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
        resumeModulesItem.target = self
        resumeModulesItem.toolTip = "Notched quit unexpectedly several times while starting, so modules were paused."
        menu.addItem(resumeModulesItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "About Notched") { [weak self] in self?.windows.showSettings(.about) })

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(DebugMenu.make(environment: environment))
        #endif

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Notched", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.state = environment.settings.isPaused ? .on : .off
        resumeModulesItem.isHidden = !environment.modules.isSafeMode
        rebuildModuleItems(in: menu)
    }

    private func rebuildModuleItems(in menu: NSMenu) {
        for item in moduleItems { menu.removeItem(item) }
        let registry = environment.modules
        let items = registry.descriptors.compactMap { registry.module($0.id) }.flatMap { $0.menuItems() }
        moduleItems = items.isEmpty ? [] : [.separator()] + items
        var index = menu.index(of: resumeModulesItem) + 1
        for item in moduleItems {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    @objc private func togglePause() {
        environment.settings.isPaused.toggle()
    }

    @objc private func resumeModules() {
        environment.modules.leaveSafeMode()
    }
}

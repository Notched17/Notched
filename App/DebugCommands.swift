// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit

/// DEBUG-only commands, sent as URLs so scripts can drive the island into a
/// state and screenshot it, e.g. `open -g "dynamicnotch://debug/expand"`.
///
/// Commands: expand, collapse, pill?on=, outline?on=, reduce-motion?on=,
/// reduce-transparency?on=, increase-contrast?on= (on=default clears an override),
/// fullscreen-fallback?on=, hello-alert, hello-session?on=, settings?pane=,
/// theme?notch=&pill=.
@MainActor
enum DebugCommands {
    static func handle(_ url: URL, environment: AppEnvironment, windows: WindowCoordinator) {
        guard url.scheme == "dynamicnotch", url.host == "debug" else { return }
        let command = url.lastPathComponent
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "on" }?.value
        let on = value != "0"
        let override: Bool? = value == "default" ? nil : on
        Log.app.debug("Debug command \(command, privacy: .public) value=\(value ?? "-", privacy: .public)")

        switch command {
        case "expand": environment.islands.expandAll()
        case "collapse": environment.islands.collapseAll()
        case "pill": environment.settings.debugForcePill = on
        case "launch-at-login": environment.launchAtLogin.setEnabled(on)
            Log.app.info("Launch at login status: \(String(describing: environment.launchAtLogin.status), privacy: .public)")
        case "onboarding": windows.showOnboarding(startAt: query(url, "step").flatMap(OnboardingView.Step.init(name:)) ?? .welcome)
        case "settings":
            windows.showSettings(query(url, "pane").flatMap(SettingsPane.init(rawValue:)))
        case "theme":
            if let theme = query(url, "notch").flatMap(IslandTheme.init(rawValue:)) { environment.settings.notchTheme = theme }
            if let theme = query(url, "pill").flatMap(IslandTheme.init(rawValue:)) { environment.settings.pillTheme = theme }
        case "outline":
            for controller in environment.islands.controllers.values { controller.model.debugOutline = on }
        case "reduce-motion": environment.accessibility.overrideReduceMotion = override
        case "reduce-transparency": environment.accessibility.overrideReduceTransparency = override
        case "increase-contrast": environment.accessibility.overrideIncreaseContrast = override
        case "fullscreen-fallback": environment.fullscreen.forceFallback = on
        case "hello-alert": DebugMenu.hello(environment)?.showAlert()
        case "hello-session":
            if let hello = DebugMenu.hello(environment), hello.isLiveSessionRunning != on { hello.toggleLiveSession() }
        default: Log.app.error("Unknown debug command \(command, privacy: .public)")
        }
    }

    private static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// The status menu's Debug submenu.
@MainActor
enum DebugMenu {
    static func make(environment: AppEnvironment) -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Expand Island") { environment.islands.expandAll() })
        menu.addItem(ClosureMenuItem(title: "Collapse Island") { environment.islands.collapseAll() })
        menu.addItem(ClosureMenuItem(title: "Toggle Pill Geometry") { environment.settings.debugForcePill.toggle() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Show Hello Alert") { hello(environment)?.showAlert() })
        menu.addItem(ClosureMenuItem(title: "Toggle Hello Live Session") { hello(environment)?.toggleLiveSession() })
        item.submenu = menu
        return item
    }

    /// The Hello demo module, turning it on first if needed.
    static func hello(_ environment: AppEnvironment) -> HelloModule? {
        environment.settings.enabledModules.insert(HelloModule.descriptor.id)
        environment.modules.reconcile(enabled: environment.settings.enabledModules)
        return environment.modules.module(HelloModule.descriptor.id) as? HelloModule
    }
}
#endif

/// An `NSMenuItem` that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() { handler() }
}

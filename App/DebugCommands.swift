// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit

/// DEBUG-only commands, sent as URLs so scripts can drive the island into a
/// state and screenshot it, e.g. `open -g "dynamicnotch://debug/expand"`.
///
/// Commands: expand, collapse, pill?on=, outline?on=, reduce-motion?on=,
/// reduce-transparency?on=, increase-contrast?on= (on=default clears an override).
@MainActor
enum DebugCommands {
    static func handle(_ url: URL, environment: AppEnvironment) {
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
        case "pill": environment.islands.configuration.forcePill = on
        case "outline":
            for controller in environment.islands.controllers.values { controller.model.debugOutline = on }
        case "reduce-motion": environment.accessibility.overrideReduceMotion = override
        case "reduce-transparency": environment.accessibility.overrideReduceTransparency = override
        case "increase-contrast": environment.accessibility.overrideIncreaseContrast = override
        default: Log.app.error("Unknown debug command \(command, privacy: .public)")
        }
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
        menu.addItem(ClosureMenuItem(title: "Toggle Pill Geometry") { environment.islands.configuration.forcePill.toggle() })
        item.submenu = menu
        return item
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

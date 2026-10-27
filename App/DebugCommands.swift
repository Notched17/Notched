// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation

/// DEBUG-only commands, sent as URLs so scripts can drive the island into a
/// state and screenshot it: `open -g "dynamicnotch://debug/pill?on=1"`.
@MainActor
enum DebugCommands {
    static func handle(_ url: URL, environment: AppEnvironment) {
        guard url.scheme == "dynamicnotch", url.host == "debug" else { return }
        let command = url.lastPathComponent
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let on = query.first { $0.name == "on" }?.value != "0"
        Log.app.debug("Debug command \(command, privacy: .public) on=\(on)")

        switch command {
        case "pill":
            environment.islands.configuration.forcePill = on
        case "outline":
            for controller in environment.islands.controllers.values { controller.model.debugOutline = on }
        default:
            Log.app.error("Unknown debug command \(command, privacy: .public)")
        }
    }
}
#endif

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Opens `notched://` links in every build (#37). Any app or web page can
/// open one, so each is checked strictly (`TimerURL`) and only does
/// something harmless.
///
/// - `notched://timer?minutes=10&label=Tea` starts a timer (also `seconds=`
///   and `hours=`). With Timers off, it opens the module's settings instead.
@MainActor
enum URLRouter {
    static func handle(_ url: URL, environment: AppEnvironment, windows: WindowCoordinator) {
        guard url.scheme?.lowercased() == "notched" else { return }
        switch url.host?.lowercased() {
        case "timer":
            guard let request = TimerURL.parse(url) else {
                Log.app.notice("Ignored a timer link that wasn't valid")
                return
            }
            if let timers = environment.modules.module(TimersModule.descriptor.id) as? TimersModule {
                timers.start(request)
            } else {
                windows.showSettings(.modules, module: TimersModule.descriptor.id)
            }
        #if DEBUG
        case "debug":
            DebugCommands.handle(url, environment: environment, windows: windows)
        #endif
        default:
            Log.app.notice("Ignored an unknown notched:// link")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Opens `notched://` links in every build (#37). Any app or web page can
/// open one, so each is checked strictly (`TimerURL`), only does something
/// harmless, and is rate-limited so a page can't spam the island.
///
/// - `notched://timer?minutes=10&label=Tea` starts a timer (also `seconds=`
///   and `hours=`; at least 5 s from a link), at most one per 2 s and five a
///   minute. With Timers off, it opens the module's settings instead, at most
///   once a minute.
/// - `notched://banner?title=Done&symbol=checkmark&tint=green` shows a short
///   banner marked "via link". Off unless Activity API ▸ "Allow banners from
///   links" is on, at most one per 2 s and five a minute.
@MainActor
enum URLRouter {
    static let minimumTimer: TimeInterval = 5
    private static var timerLimit = RateLimit(minimumInterval: 2, maxPerWindow: 5, window: 60)
    private static var bannerLimit = RateLimit(minimumInterval: 2, maxPerWindow: 5, window: 60)
    private static var settingsLimit = RateLimit(minimumInterval: 60, maxPerWindow: 1, window: 60)

    static func handle(_ url: URL, environment: AppEnvironment, windows: WindowCoordinator) {
        guard url.scheme?.lowercased() == "notched" else { return }
        switch url.host?.lowercased() {
        case "timer":
            guard let request = TimerURL.parse(url) else {
                Log.app.notice("Ignored a timer link that wasn't valid")
                return
            }
            if let timers = environment.modules.module(TimersModule.descriptor.id) as? TimersModule {
                guard timerLimit.allow(at: Date()) else {
                    Log.app.notice("Ignored a timer link: too many too quickly")
                    return
                }
                timers.startTimer(seconds: max(request.duration, minimumTimer), label: request.label)
            } else if settingsLimit.allow(at: Date()) {
                windows.showSettings(.modules, module: TimersModule.descriptor.id)
            }
        case "banner":
            guard environment.settings.api.allowLinkBanners,
                  let module = environment.modules.module(ActivityAPIModule.descriptor.id) as? ActivityAPIModule else {
                Log.app.notice("Ignored a banner link: links aren't allowed to show banners")
                return
            }
            guard let spec = ActivityPayload.parseBannerURL(url) else {
                Log.app.notice("Ignored a banner link that wasn't valid")
                return
            }
            guard bannerLimit.allow(at: Date()) else {
                Log.app.notice("Ignored a banner link: too many too quickly")
                return
            }
            module.showBanner(spec, clientID: "link", source: "a link")
        #if DEBUG
        case "debug":
            DebugCommands.handle(url, environment: environment, windows: windows)
        #endif
        default:
            Log.app.notice("Ignored an unknown notched:// link")
        }
    }
}

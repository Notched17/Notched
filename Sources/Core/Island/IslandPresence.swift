// SPDX-License-Identifier: GPL-3.0-or-later

import Observation

/// When the HUD may take a volume or brightness key (the safety design §3.1):
/// only if the island can show it right now. Otherwise the key goes to macOS,
/// which shows its own HUD, so a press is never swallowed without a HUD.
enum HUDVisibility {
    static func canShow(paused: Bool, suspended: Bool, anyIslandShown: Bool, alertShowing: Bool, interacting: Bool) -> Bool {
        !paused && !suspended && anyIslandShown && !alertShowing && !interacting
    }
}

/// What the island is doing, as far as the HUD needs to know. The app feeds
/// it; `HUDModule` follows `canShowHUD` and `isSuspended`.
@MainActor
@Observable
final class IslandPresence {
    /// Pause Island is on.
    var isPaused = false { didSet { update() } }
    /// Screens asleep, the screen locked, or another user's session active.
    /// The tap is switched off meanwhile, so macOS handles every key.
    var isSuspended = false { didSet { update() } }
    /// At least one island is on screen (not hidden over a fullscreen app).
    var anyIslandShown = false { didSet { update() } }
    var alertShowing = false { didSet { update() } }
    /// The pointer is on the island, or the user has it expanded.
    var isInteracting = false { didSet { update() } }

    private(set) var canShowHUD = false

    private func update() {
        let next = HUDVisibility.canShow(paused: isPaused, suspended: isSuspended, anyIslandShown: anyIslandShown,
                                         alertShowing: alertShowing, interacting: isInteracting)
        if next != canShowHUD { canShowHUD = next }
    }
}

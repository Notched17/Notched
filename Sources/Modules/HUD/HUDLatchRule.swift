// SPDX-License-Identifier: GPL-3.0-or-later

/// Whether the HUD starts latched off (the safety design §7): two sessions in
/// a row that ended without a clean quit while the tap was armed. Judged once
/// per launch from what `LaunchGuard` and the HUD's own record left behind.
enum HUDLatchRule {
    static let crashesToLatch = 2

    /// `streak` is the number of sessions in a row that crashed while armed
    /// before this launch. Returns the streak to store and whether to latch.
    static func judgeLaunch(previousSessionCrashed: Bool, wasArmed: Bool, streak: Int) -> (streak: Int, latch: Bool) {
        guard previousSessionCrashed, wasArmed else { return (0, false) }
        let next = streak + 1
        return (next, next >= crashesToLatch)
    }
}

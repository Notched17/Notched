// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How a call's duration reads in the compact island, and when it next needs
/// redrawing. A per-second ticking `Text` made a long call cost about 0.6% CPU
/// (measured with `scripts/cpu.sh`), so after the first minute it's whole
/// minutes, redrawn once a minute. The expanded view keeps full seconds.
/// Foundation only, so it's tested.
enum CallClock {
    /// "0:07" in the first minute, then "12 min".
    static func compactText(elapsed: TimeInterval) -> String {
        let seconds = Int(max(elapsed, 0))
        if seconds < 60 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        return "\(seconds / 60) min"
    }

    /// The first moment after `date` when the text changes: the next second
    /// for the first minute, then the next whole minute of the call.
    static func nextTick(startedAt: Date, after date: Date) -> Date {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return startedAt.addingTimeInterval(1) }
        if elapsed < 59 { return startedAt.addingTimeInterval(elapsed.rounded(.down) + 1) }
        return startedAt.addingTimeInterval((elapsed / 60).rounded(.down) * 60 + 60)
    }
}

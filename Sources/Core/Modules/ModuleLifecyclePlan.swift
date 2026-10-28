// SPDX-License-Identifier: GPL-3.0-or-later

/// Which modules to stop and start to match the enabled set. Pure, so the
/// ordering rules are tested:
///
/// - Stops come first, in reverse start order (the newest module first),
///   so nothing new starts beside a module that is going away.
/// - Starts follow in catalogue (display) order, never in the order the
///   user happened to switch modules on.
/// - A blocked module (suspended after crashing, or everything in safe
///   mode) stops if it runs and never starts.
struct ModuleLifecyclePlan: Equatable, Sendable {
    var stop: [ModuleID]
    var start: [ModuleID]

    var isEmpty: Bool { stop.isEmpty && start.isEmpty }

    /// - Parameter running: the running modules, in the order they started.
    static func make(running: [ModuleID], enabled: Set<ModuleID>, catalogOrder: [ModuleID], blocked: Set<ModuleID>) -> Self {
        let keep = enabled.subtracting(blocked)
        let stop = running.reversed().filter { !keep.contains($0) }
        let start = catalogOrder.filter { keep.contains($0) && !running.contains($0) }
        return ModuleLifecyclePlan(stop: Array(stop), start: start)
    }
}

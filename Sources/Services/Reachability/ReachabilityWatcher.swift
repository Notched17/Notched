// SPDX-License-Identifier: GPL-3.0-or-later

import Network

/// Whether the Mac has a network path. A protocol so tests can drive it.
@MainActor
protocol ReachabilitySource: AnyObject {
    /// Reports the current state, then every change. Calls arrive on the main actor.
    func start(onChange: @escaping @MainActor (Bool) -> Void)
    func stop()
}

/// `NWPathMonitor` on a utility queue: event-driven, no polling. A cancelled
/// monitor can't restart, so each `start` makes a new one.
@MainActor
final class ReachabilityWatcher: ReachabilitySource {
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "me.rkck.Notched.reachability", qos: .utility)

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in onChange(online) }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

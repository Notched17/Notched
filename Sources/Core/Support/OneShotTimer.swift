// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Fires once at a given time; rescheduling replaces the pending fire.
/// Used for event deadlines (like an alert's expiry), not for polling.
@MainActor
final class OneShotTimer {
    var action: @MainActor () -> Void = {}
    private var task: Task<Void, Never>?

    func schedule(at date: Date?) {
        task?.cancel()
        guard let date else { task = nil; return }
        task = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.action()
        }
    }
}

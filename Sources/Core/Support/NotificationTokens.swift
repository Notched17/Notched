// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Block-based notification observers that run their handler on the main actor
/// and are removed together with `invalidate()`.
@MainActor
final class NotificationTokens {
    private var tokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    func observe(
        _ name: Notification.Name,
        in center: NotificationCenter = .default,
        object: AnyObject? = nil,
        _ handler: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append((center, token))
    }

    func invalidate() {
        for entry in tokens { entry.center.removeObserver(entry.token) }
        tokens.removeAll()
    }
}

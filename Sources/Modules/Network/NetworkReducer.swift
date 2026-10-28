// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How the Mac is connected, from `NWPathMonitor` (#29).
enum NetworkState: Equatable, Sendable {
    /// The network's name only with "Show Wi-Fi name" on and Location allowed.
    case wifi(name: String?)
    case ethernet
    /// An expensive path, e.g. an iPhone's Personal Hotspot.
    case hotspot
    /// Connected some other way (a VPN-only or unknown interface).
    case other
    case offline
}

/// Network banners without spam (#29). Pure.
///
/// - The path at start is silent.
/// - A change is announced once it has lasted 2 s, so a brief drop says
///   nothing, and at most 3 times a minute; while held back, only the
///   latest state is announced.
/// - Learning or losing the Wi-Fi network's name, on the same network, is
///   silent: Location access changed, not the network.
struct NetworkReducer: Sendable {
    static let policy = BannerPolicy(settle: 2, maxPerWindow: 3, window: 60)

    enum Event: Equatable, Sendable {
        case path(NetworkState)
        /// The wake the reducer asked for.
        case tick
    }

    enum Effect: Equatable, Sendable {
        case banner(NetworkState)
        case wake(Date)
    }

    private var source = BannerSource<NetworkState>(policy: policy)

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .path(let state):
            if case .wifi(let name) = state, case .wifi(let shownName) = source.shown, name == nil || shownName == nil {
                source.seed(state)
                return []
            }
            return effects(source.receive(state, at: now))
        case .tick:
            return effects(source.advance(to: now))
        }
    }

    private func effects(_ output: BannerSource<NetworkState>.Output) -> [Effect] {
        switch output {
        case .none: []
        case .emit(let state): [.banner(state)]
        case .wake(let date): [.wake(date)]
        }
    }
}

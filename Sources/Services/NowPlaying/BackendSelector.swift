// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where Now Playing information comes from (ADR-0008).
enum NowPlayingBackend: String, Sendable {
    /// mediaremote-adapter: any app, through `/usr/bin/perl`.
    case adapter
    /// Music and Spotify only, through their notifications and AppleScript.
    case scripting
}

/// The user's choice of source (Settings ▸ Modules ▸ Now Playing).
enum BackendPreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case adapterOnly
    case scriptingOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .adapterOnly: "Any App Only"
        case .scriptingOnly: "Music and Spotify Only"
        }
    }
}

/// Whether the adapter is known to work on this Mac.
enum AdapterHealth: Equatable, Sendable {
    case unknown
    case healthy
    /// It can't read media; the reason is for logs and Settings.
    case failed(String)
}

/// Which scriptable players exist and which the user has blocked.
struct ScriptingAvailability: Equatable, Sendable {
    /// Bundle IDs of installed scriptable players (Music, Spotify).
    var installedApps: Set<String>
    /// Installed players the user denied Automation for.
    var deniedApps: Set<String>

    var isAvailable: Bool { !installedApps.subtracting(deniedApps).isEmpty }
}

enum BackendSelection: Equatable, Sendable {
    case active(NowPlayingBackend)
    case unavailable(UnavailableReason)

    enum UnavailableReason: Equatable, Sendable {
        case adapterFailed(String)
        case noScriptablePlayers
        case automationDenied
        case adapterFailedAndNoFallback(String)
    }

    var backend: NowPlayingBackend? {
        if case .active(let backend) = self { return backend }
        return nil
    }
}

/// Picks the backend: the adapter unless it's known to be broken, otherwise
/// Music and Spotify by scripting, otherwise nothing (and Settings says why).
enum BackendSelector {
    static func select(preference: BackendPreference, health: AdapterHealth, scripting: ScriptingAvailability) -> BackendSelection {
        let failure: String? = if case .failed(let reason) = health { reason } else { nil }
        switch preference {
        case .auto:
            guard let failure else { return .active(.adapter) }
            return scripting.isAvailable ? .active(.scripting) : .unavailable(.adapterFailedAndNoFallback(failure))
        case .adapterOnly:
            return failure.map { .unavailable(.adapterFailed($0)) } ?? .active(.adapter)
        case .scriptingOnly:
            if scripting.isAvailable { return .active(.scripting) }
            return scripting.installedApps.isEmpty ? .unavailable(.noScriptablePlayers) : .unavailable(.automationDenied)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// How the media visualiser looks (#12).
enum VisualizerStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Bars that move like music while it plays.
    case animated
    /// Bars at rest: no motion at all.
    case still
    /// No bars; the compact island shows only the artwork.
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .animated: "Animated"
        case .still: "Still"
        case .off: "Off"
        }
    }
}

/// The Now Playing module's settings (Settings ▸ Modules ▸ Now Playing),
/// persisted under `media.*` in the same defaults as `SettingsStore`.
@MainActor
@Observable
final class MediaSettings {
    enum Key {
        static let backend = "media.backend"
        static let ignoredApps = "media.ignoredApps"
        static let lyricsEnabled = "media.lyricsEnabled"
        static let lyricsTicker = "media.lyricsTicker"
        static let expandOnTrackChange = "media.expandOnTrackChange"
        static let staleAfterMinutes = "media.staleAfterMinutes"
        static let endAfterMinutes = "media.endAfterMinutes"
        static let visualizer = "media.visualizer"
    }

    static let staleAfterChoices = [1, 2, 5, 10]
    static let endAfterChoices = [5, 10, 30, 60]

    @ObservationIgnored private let defaults: UserDefaults

    /// Where Now Playing reads from: any app (adapter) with a fallback, or one of them only.
    var backend: BackendPreference { didSet { defaults.set(backend.rawValue, forKey: Key.backend) } }
    /// Bundle IDs whose media never shows.
    var ignoredApps: Set<String> { didSet { defaults.set(ignoredApps.sorted(), forKey: Key.ignoredApps) } }
    /// Synced lyrics from LRCLIB. Off means no lyrics request is ever made (ADR-0009).
    var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: Key.lyricsEnabled) } }
    /// Show the current lyric line on the compact island instead of the bars.
    var lyricsTicker: Bool { didSet { defaults.set(lyricsTicker, forKey: Key.lyricsTicker) } }
    var expandOnTrackChange: Bool { didSet { defaults.set(expandOnTrackChange, forKey: Key.expandOnTrackChange) } }
    var staleAfterMinutes: Int { didSet { defaults.set(staleAfterMinutes, forKey: Key.staleAfterMinutes) } }
    var endAfterMinutes: Int { didSet { defaults.set(endAfterMinutes, forKey: Key.endAfterMinutes) } }
    var visualizer: VisualizerStyle { didSet { defaults.set(visualizer.rawValue, forKey: Key.visualizer) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backend = defaults.string(forKey: Key.backend).flatMap(BackendPreference.init(rawValue:)) ?? .auto
        ignoredApps = Set(defaults.array(forKey: Key.ignoredApps) as? [String] ?? [])
        lyricsEnabled = defaults.object(forKey: Key.lyricsEnabled) as? Bool ?? false
        lyricsTicker = defaults.object(forKey: Key.lyricsTicker) as? Bool ?? false
        expandOnTrackChange = defaults.object(forKey: Key.expandOnTrackChange) as? Bool ?? false
        staleAfterMinutes = defaults.object(forKey: Key.staleAfterMinutes) as? Int ?? 2
        endAfterMinutes = defaults.object(forKey: Key.endAfterMinutes) as? Int ?? 10
        visualizer = defaults.string(forKey: Key.visualizer).flatMap(VisualizerStyle.init(rawValue:)) ?? .animated
    }

    var lifecycle: MediaLifecycle {
        MediaLifecycle(staleAfter: TimeInterval(staleAfterMinutes * 60), endAfter: TimeInterval(endAfterMinutes * 60))
    }
}

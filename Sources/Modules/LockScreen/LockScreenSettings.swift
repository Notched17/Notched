// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Lock Screen's settings (Settings ▸ Modules ▸ Lock Screen), under `lockScreen.*`.
/// The module itself is switched on in the Modules list, behind a confirmation
/// (ADR-0031 §1). Everything personal starts off (§4).
@MainActor
@Observable
final class LockScreenSettings {
    enum Key {
        static let showTrack = "lockScreen.showTrack"
        static let showArtwork = "lockScreen.showArtwork"
        static let showBattery = "lockScreen.showBattery"
        static let showEvent = "lockScreen.showEvent"
        static let showEventTitle = "lockScreen.showEventTitle"
        static let showLyrics = "lockScreen.showLyrics"
        static let style = "lockScreen.style"
        static let size = "lockScreen.size"
        static let vertical = "lockScreen.vertical"
        static let horizontal = "lockScreen.horizontal"
        static let otherDisplays = "lockScreen.otherDisplays"
        static let otherAccounts = "lockScreen.otherAccounts"
        /// Why the feature turned itself off, shown in its settings until the user turns it on again.
        static let lastOffReason = "lockScreen.lastOffReason"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showTrack: Bool { didSet { defaults.set(showTrack, forKey: Key.showTrack) } }
    var showArtwork: Bool { didSet { defaults.set(showArtwork, forKey: Key.showArtwork) } }
    var showBattery: Bool { didSet { defaults.set(showBattery, forKey: Key.showBattery) } }
    var showEvent: Bool { didSet { defaults.set(showEvent, forKey: Key.showEvent) } }
    var showEventTitle: Bool { didSet { defaults.set(showEventTitle, forKey: Key.showEventTitle) } }
    var showLyrics: Bool { didSet { defaults.set(showLyrics, forKey: Key.showLyrics) } }
    var style: LockScreenCardStyle { didSet { defaults.set(style.rawValue, forKey: Key.style) } }
    var size: LockScreenGeometry.Size { didSet { defaults.set(size.rawValue, forKey: Key.size) } }
    var vertical: LockScreenGeometry.Placement.Vertical { didSet { defaults.set(vertical.rawValue, forKey: Key.vertical) } }
    var horizontal: LockScreenGeometry.Placement.Horizontal { didSet { defaults.set(horizontal.rawValue, forKey: Key.horizontal) } }
    /// Also show the card on other displays (off: only the display with the login window).
    var otherDisplays: Bool { didSet { defaults.set(otherDisplays, forKey: Key.otherDisplays) } }
    /// Show the card when this Mac has other user accounts (off: nothing is shown then).
    var otherAccounts: Bool { didSet { defaults.set(otherAccounts, forKey: Key.otherAccounts) } }
    var lastOffReason: String? { didSet { defaults.set(lastOffReason, forKey: Key.lastOffReason) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTrack = defaults.object(forKey: Key.showTrack) as? Bool ?? true
        showArtwork = defaults.object(forKey: Key.showArtwork) as? Bool ?? true
        showBattery = defaults.object(forKey: Key.showBattery) as? Bool ?? true
        showEvent = defaults.object(forKey: Key.showEvent) as? Bool ?? true
        showEventTitle = defaults.object(forKey: Key.showEventTitle) as? Bool ?? false
        showLyrics = defaults.object(forKey: Key.showLyrics) as? Bool ?? false
        style = defaults.string(forKey: Key.style).flatMap(LockScreenCardStyle.init(rawValue:)) ?? .solid
        size = defaults.string(forKey: Key.size).flatMap(LockScreenGeometry.Size.init(rawValue:)) ?? .medium
        vertical = defaults.string(forKey: Key.vertical).flatMap(LockScreenGeometry.Placement.Vertical.init(rawValue:)) ?? .middle
        horizontal = defaults.string(forKey: Key.horizontal).flatMap(LockScreenGeometry.Placement.Horizontal.init(rawValue:)) ?? .center
        otherDisplays = defaults.object(forKey: Key.otherDisplays) as? Bool ?? false
        otherAccounts = defaults.object(forKey: Key.otherAccounts) as? Bool ?? false
        lastOffReason = defaults.string(forKey: Key.lastOffReason)
    }

    var options: LockScreenCardOptions {
        LockScreenCardOptions(style: style, showTrack: showTrack, showArtwork: showArtwork, showBattery: showBattery,
                              showEvent: showEvent, showEventTitle: showEventTitle, showLyrics: showLyrics)
    }

    var placement: LockScreenGeometry.Placement {
        LockScreenGeometry.Placement(vertical: vertical, horizontal: horizontal, size: size)
    }
}

extension LockScreenCardStyle: Identifiable {
    var id: Self { self }
    var title: String {
        switch self {
        case .solid: "Solid"
        case .glass: "Liquid Glass"
        }
    }
}

extension LockScreenGeometry.Size: Identifiable {
    var id: Self { self }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

extension LockScreenGeometry.Placement.Vertical: Identifiable {
    var id: Self { self }
    var title: String {
        switch self {
        case .underClock: "Under the clock"
        case .middle: "Middle of the screen"
        }
    }
}

extension LockScreenGeometry.Placement.Horizontal: Identifiable {
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left"
        case .center: "Centre"
        case .right: "Right"
        }
    }
}

extension LockScreenReducer.OffReason {
    /// What Settings says when the feature turned itself off.
    var explanation: String {
        switch self {
        case .crashedLastSession:
            "Notched didn't quit cleanly last time, so lock-screen widgets turned themselves off. Turn them back on when you're ready."
        case .crashedWhileShowing:
            "Notched stopped while the lock-screen card was showing, so lock-screen widgets turned themselves off. Turn them back on when you're ready."
        case .failed:
            "Something went wrong showing the card, so lock-screen widgets turned themselves off. A macOS update may have changed how they work."
        }
    }
}

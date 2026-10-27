// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Every user setting, observable and persisted to `UserDefaults`.
///
/// Each value is read once at launch (falling back to its default if missing
/// or unreadable, and clamped to its range) and written back on change.
@MainActor
@Observable
final class SettingsStore {
    /// UserDefaults keys. Changing one loses that setting for existing users.
    enum Key {
        static let displaySelection = "general.displaySelection"
        static let hideInFullscreen = "general.hideInFullscreen"
        static let hideFromScreenCapture = "general.hideFromScreenCapture"
        static let isPaused = "general.isPaused"
        static let expandOnHover = "island.expandOnHover"
        static let hapticsEnabled = "island.hapticsEnabled"
        static let hoverDelay = "island.hoverDelay"
        static let notchTheme = "appearance.notchTheme"
        static let pillTheme = "appearance.pillTheme"
        static let animationStyle = "appearance.animationStyle"
        static let widthOffset = "appearance.widthOffset"
        static let expandedScale = "appearance.expandedScale"
        static let enabledModules = "modules.enabled"
        static let hasCompletedOnboarding = "onboarding.completed"
        static let debugForcePill = "debug.forcePill"
    }

    static let hoverDelayRange: ClosedRange<Double> = 0...1
    static let widthOffsetRange: ClosedRange<Double> = -20...60
    static let expandedScaleRange: ClosedRange<Double> = 0.85...1.25

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General

    var displaySelection: DisplaySelection {
        didSet { defaults.set(try? JSONEncoder().encode(displaySelection), forKey: Key.displaySelection) }
    }
    var hideInFullscreen: Bool { didSet { defaults.set(hideInFullscreen, forKey: Key.hideInFullscreen) } }
    var hideFromScreenCapture: Bool { didSet { defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }

    // MARK: Appearance

    var notchTheme: IslandTheme { didSet { defaults.set(notchTheme.rawValue, forKey: Key.notchTheme) } }
    var pillTheme: IslandTheme { didSet { defaults.set(pillTheme.rawValue, forKey: Key.pillTheme) } }
    var animationStyle: AnimationStyle { didSet { defaults.set(animationStyle.rawValue, forKey: Key.animationStyle) } }

    /// Seconds before hovering expands the island.
    var hoverDelay: Double {
        didSet {
            // @Observable makes this a computed property, so only re-assign when
            // clamping changes the value (one extra pass, never a loop).
            let clamped = hoverDelay.clamped(to: Self.hoverDelayRange)
            guard clamped == hoverDelay else { hoverDelay = clamped; return }
            defaults.set(hoverDelay, forKey: Key.hoverDelay)
        }
    }

    /// Extra width for the compact island, in points.
    var widthOffset: Double {
        didSet {
            // @Observable makes this a computed property, so only re-assign when
            // clamping changes the value (one extra pass, never a loop).
            let clamped = widthOffset.clamped(to: Self.widthOffsetRange)
            guard clamped == widthOffset else { widthOffset = clamped; return }
            defaults.set(widthOffset, forKey: Key.widthOffset)
        }
    }

    /// Scale of the expanded island relative to its standard size.
    var expandedScale: Double {
        didSet {
            // @Observable makes this a computed property, so only re-assign when
            // clamping changes the value (one extra pass, never a loop).
            let clamped = expandedScale.clamped(to: Self.expandedScaleRange)
            guard clamped == expandedScale else { expandedScale = clamped; return }
            defaults.set(expandedScale, forKey: Key.expandedScale)
        }
    }

    // MARK: Modules and lifecycle

    var enabledModules: Set<ModuleID> {
        didSet { defaults.set(enabledModules.map(\.rawValue).sorted(), forKey: Key.enabledModules) }
    }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }

    #if DEBUG
    /// Show the pill on a notched display, to check the non-notch layout.
    var debugForcePill: Bool { didSet { defaults.set(debugForcePill, forKey: Key.debugForcePill) } }
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displaySelection = (defaults.data(forKey: Key.displaySelection))
            .flatMap { try? JSONDecoder().decode(DisplaySelection.self, from: $0) } ?? .main
        hideInFullscreen = defaults.object(forKey: Key.hideInFullscreen) as? Bool ?? true
        hideFromScreenCapture = defaults.object(forKey: Key.hideFromScreenCapture) as? Bool ?? false
        isPaused = defaults.object(forKey: Key.isPaused) as? Bool ?? false
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        notchTheme = defaults.string(forKey: Key.notchTheme).flatMap(IslandTheme.init(rawValue:)) ?? .notchBlack
        pillTheme = defaults.string(forKey: Key.pillTheme).flatMap(IslandTheme.init(rawValue:)) ?? .liquidGlass
        animationStyle = defaults.string(forKey: Key.animationStyle).flatMap(AnimationStyle.init(rawValue:)) ?? .smooth
        hoverDelay = (defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.15).clamped(to: Self.hoverDelayRange)
        widthOffset = (defaults.object(forKey: Key.widthOffset) as? Double ?? 0).clamped(to: Self.widthOffsetRange)
        expandedScale = (defaults.object(forKey: Key.expandedScale) as? Double ?? 1).clamped(to: Self.expandedScaleRange)
        enabledModules = Set((defaults.array(forKey: Key.enabledModules) as? [String] ?? []).map { ModuleID($0) })
        hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        #if DEBUG
        debugForcePill = defaults.object(forKey: Key.debugForcePill) as? Bool ?? false
        #endif
    }

    // MARK: Derived

    var islandBehavior: IslandBehavior {
        IslandBehavior(
            expandOnHover: expandOnHover,
            hoverDelay: .milliseconds(Int((hoverDelay * 1000).rounded())),
            animationStyle: animationStyle,
            hapticsEnabled: hapticsEnabled
        )
    }

    var islandConfiguration: IslandConfiguration {
        var configuration = IslandConfiguration(displaySelection: displaySelection, widthOffset: widthOffset)
        #if DEBUG
        configuration.forcePill = debugForcePill
        #endif
        return configuration
    }

    func theme(for kind: NotchGeometry.Kind) -> IslandTheme {
        switch kind {
        case .notch: notchTheme
        case .pill: pillTheme
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

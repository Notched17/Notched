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
        static let multipleActivities = "activities.multipleActivities"
        static let activityRanking = "activities.ranking"
        static let alertExpansion = "activities.alertExpansion"
        static let alertDuration = "activities.alertDuration"
        static let bannerDuration = "activities.bannerDuration"
        static let recentRetention = "activities.recentRetention"
        static let clickBehavior = "island.clickBehavior"
        static let keyline = "appearance.keyline"
        static let keepShowingForMedia = "general.keepShowingForMedia"
        static let seenModules = "modules.seen"
        static let launchRecord = "lifecycle.launchRecord"
    }

    static let hoverDelayRange: ClosedRange<Double> = 0...1
    static let widthOffsetRange: ClosedRange<Double> = -20...60
    static let expandedScaleRange: ClosedRange<Double> = 0.85...1.25
    static let alertDurationRange: ClosedRange<Double> = 2...8
    static let bannerDurationRange: ClosedRange<Double> = 1.5...3

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General

    var displaySelection: DisplaySelection {
        didSet { defaults.set(try? JSONEncoder().encode(displaySelection), forKey: Key.displaySelection) }
    }
    var hideInFullscreen: Bool { didSet { defaults.set(hideInFullscreen, forKey: Key.hideInFullscreen) } }
    var hideFromScreenCapture: Bool { didSet { defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    /// Over a fullscreen app, keep the island while media plays from another app (#5).
    var keepShowingForMedia: Bool { didSet { defaults.set(keepShowingForMedia, forKey: Key.keepShowingForMedia) } }
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

    // MARK: Live Activities

    /// Several activities: detached bubbles (iPhone) or side by side (iPhone 18 Pro).
    var multipleActivities: CompactLayout.Mode {
        didSet { defaults.set(multipleActivities.rawValue, forKey: Key.multipleActivities) }
    }
    /// Expand the island briefly for an alerting update.
    var alertExpansion: Bool { didSet { defaults.set(alertExpansion, forKey: Key.alertExpansion) } }

    /// Seconds an alert keeps the island expanded.
    var alertDuration: Double {
        didSet {
            // @Observable makes this a computed property, so only re-assign when
            // clamping changes the value (one extra pass, never a loop).
            let clamped = alertDuration.clamped(to: Self.alertDurationRange)
            guard clamped == alertDuration else { alertDuration = clamped; return }
            defaults.set(alertDuration, forKey: Key.alertDuration)
        }
    }

    /// Seconds a transient banner shows.
    var bannerDuration: Double {
        didSet {
            // @Observable makes this a computed property, so only re-assign when
            // clamping changes the value (one extra pass, never a loop).
            let clamped = bannerDuration.clamped(to: Self.bannerDurationRange)
            guard clamped == bannerDuration else { bannerDuration = clamped; return }
            defaults.set(bannerDuration, forKey: Key.bannerDuration)
        }
    }

    /// Which class wins the island and which modules are pinned above the rest (#8).
    var activityRanking: RankingPolicy {
        didSet { defaults.set(activityRanking.encoded(), forKey: Key.activityRanking) }
    }

    var recentRetention: RecentRetention { didSet { defaults.set(recentRetention.rawValue, forKey: Key.recentRetention) } }
    var clickBehavior: ClickBehavior { didSet { defaults.set(clickBehavior.rawValue, forKey: Key.clickBehavior) } }
    /// A subtle border around bubbles and the expanded island in dark surroundings.
    var keyline: Bool { didSet { defaults.set(keyline, forKey: Key.keyline) } }

    // MARK: Modules and lifecycle

    /// The Now Playing module's settings.
    let media: MediaSettings
    let battery: BatterySettings
    let bluetooth: BluetoothSettings
    let network: NetworkSettings
    let timers: TimersSettings
    let sensors: SensorsSettings
    let calls: CallsSettings

    var enabledModules: Set<ModuleID> {
        didSet { defaults.set(enabledModules.map(\.rawValue).sorted(), forKey: Key.enabledModules) }
    }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    /// Modules the app has offered before, so default-on ones turn on only once (`ModuleDefaults`).
    @ObservationIgnored var seenModules: Set<ModuleID> {
        didSet { defaults.set(seenModules.map(\.rawValue).sorted(), forKey: Key.seenModules) }
    }
    /// Crash-loop protection state (`LaunchGuard`). Not observed: it changes
    /// around every module start.
    @ObservationIgnored var launchRecord: LaunchRecord {
        didSet { defaults.set(try? JSONEncoder().encode(launchRecord), forKey: Key.launchRecord) }
    }

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
        keepShowingForMedia = defaults.object(forKey: Key.keepShowingForMedia) as? Bool ?? true
        media = MediaSettings(defaults: defaults)
        battery = BatterySettings(defaults: defaults)
        bluetooth = BluetoothSettings(defaults: defaults)
        network = NetworkSettings(defaults: defaults)
        timers = TimersSettings(defaults: defaults)
        sensors = SensorsSettings(defaults: defaults)
        calls = CallsSettings(defaults: defaults)
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
        seenModules = Set((defaults.array(forKey: Key.seenModules) as? [String] ?? []).map { ModuleID($0) })
        launchRecord = defaults.data(forKey: Key.launchRecord)
            .flatMap { try? JSONDecoder().decode(LaunchRecord.self, from: $0) } ?? LaunchRecord()
        multipleActivities = defaults.string(forKey: Key.multipleActivities).flatMap(CompactLayout.Mode.init(rawValue:)) ?? .bubbles
        alertExpansion = defaults.object(forKey: Key.alertExpansion) as? Bool ?? true
        alertDuration = (defaults.object(forKey: Key.alertDuration) as? Double ?? 4).clamped(to: Self.alertDurationRange)
        bannerDuration = (defaults.object(forKey: Key.bannerDuration) as? Double ?? 2).clamped(to: Self.bannerDurationRange)
        activityRanking = RankingPolicy.load(from: defaults.data(forKey: Key.activityRanking))
        recentRetention = (defaults.object(forKey: Key.recentRetention) as? Int).flatMap(RecentRetention.init(rawValue:)) ?? .fifteenMinutes
        clickBehavior = defaults.string(forKey: Key.clickBehavior).flatMap(ClickBehavior.init(rawValue:)) ?? .open
        keyline = defaults.object(forKey: Key.keyline) as? Bool ?? true
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
            hapticsEnabled: hapticsEnabled,
            clickExpands: clickBehavior == .expand
        )
    }

    var activityConfiguration: ActivityCoordinator.Configuration {
        ActivityCoordinator.Configuration(
            alertExpansionEnabled: alertExpansion,
            alertDuration: .milliseconds(Int((alertDuration * 1000).rounded())),
            bannerDuration: .milliseconds(Int((bannerDuration * 1000).rounded())),
            recentRetention: recentRetention.duration,
            ranking: activityRanking
        )
    }

    var islandAppearance: IslandAppearance {
        IslandAppearance(
            notchTheme: notchTheme,
            pillTheme: pillTheme,
            expandedScale: expandedScale,
            multipleActivities: multipleActivities,
            keyline: keyline
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

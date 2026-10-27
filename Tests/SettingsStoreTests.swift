// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

// Serialized: every test shares one scratch defaults domain, emptied at the
// start of each test, so test runs never leave preference files behind.
@Suite("SettingsStore", .serialized)
@MainActor
struct SettingsStoreTests {
    static let domain = "me.rkck.Notched.tests"

    /// The scratch defaults domain, emptied.
    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.domain)!
        defaults.removePersistentDomain(forName: Self.domain)
        return defaults
    }

    @Test("A fresh install uses the documented defaults, with every module off")
    func defaults() {
        let sut = SettingsStore(defaults: freshDefaults())
        #expect(sut.displaySelection == .main)
        #expect(sut.hideInFullscreen)
        #expect(!sut.hideFromScreenCapture)
        #expect(!sut.isPaused)
        #expect(sut.expandOnHover)
        #expect(sut.hapticsEnabled)
        #expect(sut.notchTheme == .notchBlack)
        #expect(sut.pillTheme == .liquidGlass)
        #expect(sut.animationStyle == .smooth)
        #expect(sut.hoverDelay == 0.15)
        #expect(sut.widthOffset == 0)
        #expect(sut.expandedScale == 1)
        #expect(sut.enabledModules.isEmpty)
        #expect(!sut.hasCompletedOnboarding)
    }

    @Test("Every setting survives a relaunch")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = SettingsStore(defaults: defaults)
        first.displaySelection = .specific("EXT-1")
        first.hideInFullscreen = false
        first.hideFromScreenCapture = true
        first.isPaused = true
        first.expandOnHover = false
        first.hapticsEnabled = false
        first.notchTheme = .tintedGlass
        first.pillTheme = .notchBlack
        first.animationStyle = .bouncy
        first.hoverDelay = 0.4
        first.widthOffset = 12
        first.expandedScale = 1.1
        first.enabledModules = ["hello", "media"]
        first.hasCompletedOnboarding = true

        let second = SettingsStore(defaults: defaults)
        #expect(second.displaySelection == .specific("EXT-1"))
        #expect(!second.hideInFullscreen)
        #expect(second.hideFromScreenCapture)
        #expect(second.isPaused)
        #expect(!second.expandOnHover)
        #expect(!second.hapticsEnabled)
        #expect(second.notchTheme == .tintedGlass)
        #expect(second.pillTheme == .notchBlack)
        #expect(second.animationStyle == .bouncy)
        #expect(second.hoverDelay == 0.4)
        #expect(second.widthOffset == 12)
        #expect(second.expandedScale == 1.1)
        #expect(second.enabledModules == ["hello", "media"])
        #expect(second.hasCompletedOnboarding)
    }

    @Test("Slider values are clamped to their ranges, including values read back from disk")
    func clamping() {
        let defaults = freshDefaults()
        let sut = SettingsStore(defaults: defaults)
        sut.hoverDelay = 5
        sut.widthOffset = -100
        sut.expandedScale = 2
        #expect(sut.hoverDelay == 1)
        #expect(sut.widthOffset == -20)
        #expect(sut.expandedScale == 1.25)

        defaults.set(-3.0, forKey: "island.hoverDelay")
        #expect(SettingsStore(defaults: defaults).hoverDelay == 0)
    }

    @Test("Unreadable stored values fall back to defaults instead of crashing")
    func corruptValues() {
        let defaults = freshDefaults()
        defaults.set("plaid", forKey: "appearance.notchTheme")
        defaults.set(Data([0xFF, 0x00]), forKey: "general.displaySelection")
        defaults.set(42, forKey: "modules.enabled")
        let sut = SettingsStore(defaults: defaults)
        #expect(sut.notchTheme == .notchBlack)
        #expect(sut.displaySelection == .main)
        #expect(sut.enabledModules.isEmpty)
    }

    @Test("Settings map onto the island's behaviour")
    func islandBehavior() {
        let sut = SettingsStore(defaults: freshDefaults())
        sut.hoverDelay = 0.3
        sut.expandOnHover = false
        sut.animationStyle = .snappy
        sut.hapticsEnabled = false
        #expect(sut.islandBehavior == IslandBehavior(
            expandOnHover: false, hoverDelay: .milliseconds(300), animationStyle: .snappy, hapticsEnabled: false
        ))
    }

    @Test("Settings map onto the island's placement")
    func islandConfiguration() {
        let sut = SettingsStore(defaults: freshDefaults())
        sut.displaySelection = .all
        sut.widthOffset = 8
        #expect(sut.islandConfiguration.displaySelection == .all)
        #expect(sut.islandConfiguration.widthOffset == 8)
    }

    @Test("The theme depends on the kind of display")
    func themePerDisplayKind() {
        let sut = SettingsStore(defaults: freshDefaults())
        sut.notchTheme = .tintedGlass
        sut.pillTheme = .notchBlack
        #expect(sut.theme(for: .notch) == .tintedGlass)
        #expect(sut.theme(for: .pill) == .notchBlack)
    }

    // MARK: Live Activities (M1.5)

    @Test("Live Activity settings default to iPhone-like behaviour")
    func liveActivityDefaults() {
        let sut = SettingsStore(defaults: freshDefaults())
        #expect(sut.multipleActivities == .bubbles)
        #expect(sut.alertExpansion)
        #expect(sut.alertDuration == 4)
        #expect(sut.bannerDuration == 2)
        #expect(sut.recentRetention == .fifteenMinutes)
        #expect(sut.clickBehavior == .open)
        #expect(sut.keyline)
    }

    @Test("Live Activity settings survive a relaunch")
    func liveActivityPersistence() {
        let defaults = freshDefaults()
        let first = SettingsStore(defaults: defaults)
        first.multipleActivities = .sideBySide
        first.alertExpansion = false
        first.alertDuration = 6
        first.bannerDuration = 2.5
        first.recentRetention = .fourHours
        first.clickBehavior = .expand
        first.keyline = false

        let second = SettingsStore(defaults: defaults)
        #expect(second.multipleActivities == .sideBySide)
        #expect(!second.alertExpansion)
        #expect(second.alertDuration == 6)
        #expect(second.bannerDuration == 2.5)
        #expect(second.recentRetention == .fourHours)
        #expect(second.clickBehavior == .expand)
        #expect(!second.keyline)
    }

    @Test("Alert and banner durations are clamped to their ranges")
    func durationClamping() {
        let sut = SettingsStore(defaults: freshDefaults())
        sut.alertDuration = 20
        sut.bannerDuration = 0.5
        #expect(sut.alertDuration == 8)
        #expect(sut.bannerDuration == 1.5)
    }

    @Test("Live Activity settings map onto the coordinator, the island's behaviour and its appearance")
    func liveActivityMapping() {
        let sut = SettingsStore(defaults: freshDefaults())
        sut.alertExpansion = false
        sut.alertDuration = 6
        sut.bannerDuration = 2.5
        sut.recentRetention = .oneHour
        sut.clickBehavior = .expand
        sut.multipleActivities = .sideBySide
        sut.keyline = false
        #expect(sut.activityConfiguration == ActivityCoordinator.Configuration(
            alertExpansionEnabled: false, alertDuration: .seconds(6),
            bannerDuration: .milliseconds(2500), recentRetention: .seconds(3600)
        ))
        #expect(sut.islandBehavior.clickExpands)
        #expect(sut.islandAppearance.multipleActivities == .sideBySide)
        #expect(!sut.islandAppearance.keyline)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Which Now Playing backend runs, and why none can (#10, ADR-0008).
@Suite("BackendSelector")
struct BackendSelectorTests {
    let players = ScriptingAvailability(installedApps: ["com.apple.Music", "com.spotify.client"], deniedApps: [])

    @Test func autoPrefersAdapter() {
        #expect(BackendSelector.select(preference: .auto, health: .healthy, scripting: players) == .active(.adapter))
    }

    @Test func autoUnknownHealthUsesAdapter() {
        #expect(BackendSelector.select(preference: .auto, health: .unknown, scripting: players) == .active(.adapter))
    }

    @Test func autoFallsBackWhenAdapterFailed() {
        #expect(BackendSelector.select(preference: .auto, health: .failed("exit 1"), scripting: players) == .active(.scripting))
    }

    @Test func autoWithNothingLeftIsUnavailable() {
        let none = ScriptingAvailability(installedApps: [], deniedApps: [])
        #expect(BackendSelector.select(preference: .auto, health: .failed("exit 1"), scripting: none)
                == .unavailable(.adapterFailedAndNoFallback("exit 1")))
    }

    @Test func adapterOnlyFailedIsUnavailable() {
        #expect(BackendSelector.select(preference: .adapterOnly, health: .failed("exit 1"), scripting: players)
                == .unavailable(.adapterFailed("exit 1")))
    }

    @Test func scriptingOnlyIgnoresHealthyAdapter() {
        #expect(BackendSelector.select(preference: .scriptingOnly, health: .healthy, scripting: players) == .active(.scripting))
    }

    @Test func scriptingOnlyWithoutPlayersIsUnavailable() {
        let none = ScriptingAvailability(installedApps: [], deniedApps: [])
        #expect(BackendSelector.select(preference: .scriptingOnly, health: .healthy, scripting: none) == .unavailable(.noScriptablePlayers))
    }

    @Test func allDeniedIsAutomationDenied() {
        let denied = ScriptingAvailability(installedApps: ["com.apple.Music"], deniedApps: ["com.apple.Music"])
        #expect(!denied.isAvailable)
        #expect(BackendSelector.select(preference: .scriptingOnly, health: .healthy, scripting: denied) == .unavailable(.automationDenied))
    }

    @Test func oneAllowedPlayerIsEnough() {
        let partly = ScriptingAvailability(installedApps: ["com.apple.Music", "com.spotify.client"], deniedApps: ["com.apple.Music"])
        #expect(partly.isAvailable)
    }
}

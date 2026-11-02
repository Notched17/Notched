// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The lock-screen safety rules (ADR-0031), one test per rule.
@Suite("LockScreenReducer")
struct LockScreenReducerTests {
    typealias Effect = LockScreenReducer.Effect
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func armed(_ tweak: (inout LockScreenReducer.Config) -> Void = { _ in }) -> LockScreenReducer {
        var config = LockScreenReducer.Config()
        config.enabled = true
        tweak(&config)
        var sut = LockScreenReducer()
        _ = sut.reduce(.configure(config), now: now)
        return sut
    }

    private func shown(_ tweak: (inout LockScreenReducer.Config) -> Void = { _ in }) -> LockScreenReducer {
        var sut = armed(tweak)
        _ = sut.reduce(.lockNotification, now: now)
        _ = sut.reduce(.lockState(.locked), now: now)
        return sut
    }

    @Test("Off by default: a lock does nothing")
    func offByDefault() {
        var sut = LockScreenReducer()
        #expect(sut.phase == .off)
        #expect(sut.reduce(.lockNotification, now: now).isEmpty)
        #expect(sut.reduce(.lockState(.locked), now: now).isEmpty)
        #expect(sut.phase == .off)
    }

    @Test("A card shows only after the lock notification and then a read that says locked")
    func twoSignals() {
        var sut = armed()
        #expect(sut.reduce(.lockNotification, now: now) == [.checkLockState(after: 0.5)])
        #expect(sut.phase == .pending)
        #expect(sut.reduce(.lockState(.locked), now: now) == [.setShownFlag(true), .show(includeSecondaryScreens: false), .startWatchdog(every: 2)])
        #expect(sut.phase == .shown)
    }

    @Test("A read alone, without a lock signal, shows nothing")
    func readAloneShowsNothing() {
        var sut = armed()
        #expect(sut.reduce(.lockState(.locked), now: now).isEmpty)
        #expect(sut.phase == .armed)
    }

    @Test("Unknown or unlocked after the notification: nothing is shown (fail closed)")
    func failClosed() {
        for state in [LockState.unknown, .unlocked] {
            var sut = armed()
            _ = sut.reduce(.lockNotification, now: now)
            #expect(sut.reduce(.lockState(state), now: now).isEmpty)
            #expect(sut.phase == .armed)
        }
    }

    @Test("Every way out of a shown card starts by destroying it and clears the flag")
    func everyExitDestroysFirst() {
        var disabled = LockScreenReducer.Config()
        disabled.enabled = false
        var killed = LockScreenReducer.Config()
        killed.enabled = true
        killed.killSwitch = true
        let exits: [LockScreenReducer.Event] = [
            .unlockNotification, .sessionResigned, .sessionBecameActive, .screensSlept, .screensWoke, .displaysChanged,
            .quit, .lockState(.unlocked), .lockState(.unknown), .failure("boom"), .configure(disabled), .configure(killed),
        ]
        for exit in exits {
            var sut = shown()
            let effects = sut.reduce(exit, now: now)
            #expect(effects.first == .destroy, "\(exit) must destroy first")
            #expect(effects.contains(.stopWatchdog), "\(exit)")
            #expect(effects.contains(.setShownFlag(false)), "\(exit)")
            #expect(sut.phase != .shown, "\(exit)")
        }
    }

    @Test("Still locked: the watchdog leaves the card alone; unlocked: it goes")
    func watchdog() {
        var sut = shown()
        #expect(sut.reduce(.lockState(.locked), now: now).isEmpty)
        #expect(sut.phase == .shown)
        #expect(sut.reduce(.lockState(.unlocked), now: now).first == .destroy)
    }

    @Test("Another app becoming active makes it check at once")
    func appActivationChecks() {
        var sut = shown()
        #expect(sut.reduce(.appActivated, now: now) == [.checkLockState(after: 0)])
        var idle = armed()
        #expect(idle.reduce(.appActivated, now: now).isEmpty)
    }

    @Test("Screens waking while still locked: confirmed again, then shown again")
    func wakeWhileLocked() {
        var sut = shown()
        _ = sut.reduce(.screensSlept, now: now)
        #expect(sut.phase == .armed)
        #expect(sut.reduce(.screensWoke, now: now) == [.checkLockState(after: 0.5)])
        #expect(sut.reduce(.lockState(.locked), now: now).contains(.show(includeSecondaryScreens: false)))
    }

    @Test("Closing the lid: sleep comes before the lock, so the card waits for the wake (spike order, 2 Nov)")
    func lidCloseOrder() {
        var sut = armed()
        _ = sut.reduce(.screensSlept, now: now)                       // willSleep, screensDidSleep
        #expect(sut.reduce(.lockNotification, now: now).isEmpty)      // screenIsLocked, 0.2 s later
        #expect(sut.phase == .armed)
        #expect(sut.reduce(.screensWoke, now: now) == [.checkLockState(after: 0.5)])
        #expect(sut.reduce(.lockState(.locked), now: now).contains(.show(includeSecondaryScreens: false)))
    }

    @Test("A lock check that lands while the screens are asleep shows nothing")
    func noShowWhileAsleep() {
        var sut = armed()
        _ = sut.reduce(.lockNotification, now: now)
        _ = sut.reduce(.screensSlept, now: now)
        #expect(sut.reduce(.lockState(.locked), now: now).isEmpty)
        #expect(sut.phase == .armed)
    }

    @Test("A kill switch stops everything, even when enabled")
    func killSwitch() {
        var sut = armed { $0.killSwitch = true }
        #expect(sut.phase == .off)
        #expect(sut.reduce(.lockNotification, now: now).isEmpty)
        #expect(sut.reduce(.screensWoke, now: now).isEmpty)
    }

    @Test("Other accounts: nothing unless the switch allows it")
    func otherAccounts() {
        var blocked = armed { $0.otherAccountsExist = true }
        #expect(blocked.reduce(.lockNotification, now: now).isEmpty)
        let allowed = shown {
            $0.otherAccountsExist = true
            $0.allowWithOtherAccounts = true
        }
        #expect(allowed.phase == .shown)
    }

    @Test("Other displays only when that switch is on; changing it while shown rebuilds")
    func secondaryDisplays() {
        var sut = armed { $0.includeSecondaryScreens = true }
        _ = sut.reduce(.lockNotification, now: now)
        #expect(sut.reduce(.lockState(.locked), now: now).contains(.show(includeSecondaryScreens: true)))
        var config = sut.config
        config.includeSecondaryScreens = false
        let effects = sut.reduce(.configure(config), now: now)
        #expect(effects.first == .destroy)
        #expect(effects.last == .checkLockState(after: 0))
    }

    @Test("A crash last session, or while the card showed, turns it off at launch")
    func crashRules() {
        var crashed = armed()
        #expect(crashed.reduce(.launched(previousSessionCrashed: true, shownFlagWasSet: false), now: now) == [.turnOff(.crashedLastSession)])
        #expect(crashed.phase == .off)
        #expect(crashed.reduce(.lockNotification, now: now).isEmpty)

        var diedShowing = armed()
        #expect(diedShowing.reduce(.launched(previousSessionCrashed: false, shownFlagWasSet: true), now: now)
            == [.setShownFlag(false), .turnOff(.crashedWhileShowing)])

        var clean = armed()
        #expect(clean.reduce(.launched(previousSessionCrashed: false, shownFlagWasSet: false), now: now).isEmpty)
        #expect(clean.phase == .armed)

        var disabled = LockScreenReducer()
        #expect(disabled.reduce(.launched(previousSessionCrashed: true, shownFlagWasSet: true), now: now) == [.setShownFlag(false)])
    }

    @Test("A failure destroys everything and turns the feature off")
    func failureTurnsOff() {
        var sut = shown()
        let effects = sut.reduce(.failure("SLSShowSpaces -1"), now: now)
        #expect(effects.first == .destroy)
        #expect(effects.last == .turnOff(.failed("SLSShowSpaces -1")))
        #expect(sut.phase == .off)
        #expect(sut.reduce(.lockNotification, now: now).isEmpty)
    }

    @Test("The spike's lifetime: destroyed after it, not shown again until unlock")
    func lifetime() {
        var sut = shown { $0.maximumLifetime = 60 }
        let reached = sut.reduce(.lifetimeReached, now: now)
        #expect(reached.first == .destroy)
        #expect(reached.contains(.cancelLifetimeLimit))
        #expect(sut.reduce(.screensWoke, now: now).isEmpty)
        #expect(sut.reduce(.lockNotification, now: now).isEmpty)
        _ = sut.reduce(.unlockNotification, now: now)
        #expect(sut.reduce(.lockNotification, now: now) == [.checkLockState(after: 0.5)])
        #expect(sut.reduce(.lockState(.locked), now: now).contains(.scheduleLifetimeLimit(60)))
    }

    @Test("A confirmed unlock also ends the spent state, if the notification was missed")
    func unlockReadClearsSpent() {
        var sut = shown { $0.maximumLifetime = 60 }
        _ = sut.reduce(.lifetimeReached, now: now)
        _ = sut.reduce(.lockState(.unlocked), now: now)
        #expect(!sut.spentUntilUnlock)
    }
}

@Suite("LockScreenGeometry")
struct LockScreenGeometryTests {
    static let screens: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1470, height: 956),      // MacBook Air 13"
        CGRect(x: 0, y: 0, width: 1710, height: 1112),     // MacBook Air 15"
        CGRect(x: 0, y: 0, width: 1920, height: 1243),     // Charlie's Air 15" at "More Space" (spike, 2 Nov)
        CGRect(x: 0, y: 0, width: 1280, height: 800),
        CGRect(x: 0, y: 0, width: 1024, height: 640),      // scaled for larger text
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 0, y: 0, width: 3840, height: 2160),
        CGRect(x: 0, y: 0, width: 5120, height: 2880),
        CGRect(x: 1710, y: -200, width: 2560, height: 1440), // a secondary display to the right, lower
        CGRect(x: -1080, y: 0, width: 1080, height: 1920),   // a portrait display to the left
    ]

    @Test("The card never reaches the bottom 45 % of any screen, and stays small and inside it")
    func safeZone() throws {
        for screen in Self.screens {
            let frame = try #require(LockScreenGeometry.cardFrame(in: screen), "no frame for \(screen)")
            #expect(frame.minY >= screen.minY + screen.height * 0.45, "\(screen)")
            #expect(screen.contains(frame), "\(screen)")
            #expect(frame.width <= 360 && frame.width <= screen.width * 0.4, "\(screen)")
            #expect(frame.height <= 120, "\(screen)")
            #expect(abs(frame.midX - screen.midX) < 0.5, "\(screen)")
            #expect(abs(frame.maxY - (screen.maxY - screen.height * 0.30)) < 0.5, "\(screen)")
        }
    }

    @Test("A screen too small for the rules gets no card at all")
    func tooSmall() {
        #expect(LockScreenGeometry.cardFrame(in: CGRect(x: 0, y: 0, width: 200, height: 200)) == nil)
        #expect(LockScreenGeometry.cardFrame(in: CGRect(x: 0, y: 0, width: 1470, height: 120)) == nil)
        #expect(LockScreenGeometry.cardFrame(in: .zero) == nil)
    }
}

@Suite("Lock screen support")
struct LockScreenSupportTests {
    @Test("The launch argument or the defaults key switch it off")
    func killSwitch() throws {
        let defaults = try #require(UserDefaults(suiteName: "LockScreenKillSwitch.\(UUID().uuidString)"))
        #expect(!LockScreenKillSwitch.isActive(arguments: ["Notched"], defaults: defaults))
        #expect(LockScreenKillSwitch.isActive(arguments: ["Notched", "--no-lock-screen"], defaults: defaults))
        defaults.set(true, forKey: LockScreenKillSwitch.defaultsKey)
        #expect(LockScreenKillSwitch.isActive(arguments: ["Notched"], defaults: defaults))
    }

    @Test("Other login accounts: real users only, not system accounts, not you")
    func otherAccounts() {
        let entries: [LocalAccounts.Entry] = [
            .init(name: "charlie", uid: 501, shell: "/bin/zsh"),
            .init(name: "sam", uid: 502, shell: "/bin/zsh"),
            .init(name: "test", uid: 503, shell: "/usr/bin/false"),
            .init(name: "_www", uid: 70, shell: "/usr/bin/false"),
            .init(name: "_svc", uid: 600, shell: "/bin/sh"),
            .init(name: "daemon", uid: 1, shell: "/usr/bin/false"),
            .init(name: "nobody", uid: 4_294_967_294, shell: "/usr/bin/false"),
        ]
        #expect(LocalAccounts.otherLoginAccounts(in: entries, current: "charlie") == ["sam"])
        #expect(LocalAccounts.otherLoginAccounts(in: entries.filter { $0.name != "sam" }, current: "charlie").isEmpty)
    }

    @Test("Lock state: only a present, true key is locked; off the console is unknown")
    func lockState() {
        let yes = NSNumber(value: true), no = NSNumber(value: false)
        #expect(LockStateReader.interpret(["CGSSessionScreenIsLocked": yes, "kCGSSessionOnConsoleKey": yes]) == .locked)
        #expect(LockStateReader.interpret(["kCGSSessionOnConsoleKey": yes]) == .unlocked)
        #expect(LockStateReader.interpret(["CGSSessionScreenIsLocked": no, "kCGSSessionOnConsoleKey": yes]) == .unlocked)
        #expect(LockStateReader.interpret(["CGSSessionScreenIsLocked": yes, "kCGSSessionOnConsoleKey": no]) == .unknown)
        #expect(LockStateReader.interpret([:]) == .unknown)
        #expect(LockStateReader.interpret(["CGSSessionScreenIsLocked": "yes", "kCGSSessionOnConsoleKey": yes]) == .unknown)
    }
}

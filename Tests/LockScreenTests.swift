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

@Suite("LockScreenGeometry placement")
struct LockScreenPlacementTests {
    typealias Placement = LockScreenGeometry.Placement

    static let allPlacements: [Placement] = Placement.Vertical.allCases.flatMap { vertical in
        Placement.Horizontal.allCases.map { Placement(vertical: vertical, horizontal: $0) }
    }

    @Test("Every placement, on every screen, stays inside the band: never in the bottom 45 %, never above 30 %, never off the screen")
    func everyPlacementStaysInTheBand() throws {
        for screen in LockScreenGeometryTests.screens {
            for placement in Self.allPlacements {
                let frame = try #require(LockScreenGeometry.cardFrame(in: screen, placement: placement), "\(placement) on \(screen)")
                #expect(frame.minY >= screen.minY + screen.height * 0.45, "\(placement) on \(screen)")
                #expect(frame.maxY <= screen.maxY - screen.height * 0.30 + 0.001, "\(placement) on \(screen)")
                #expect(screen.contains(frame), "\(placement) on \(screen)")
                #expect(frame.width <= 360 && frame.width <= screen.width * 0.4, "\(placement) on \(screen)")
                #expect(frame.height <= 120, "\(placement) on \(screen)")
            }
        }
    }

    @Test("Every size, in every placement, on every screen, stays inside the band and the width cap")
    func everySizeStaysInTheBand() throws {
        for screen in LockScreenGeometryTests.screens {
            for size in LockScreenGeometry.Size.allCases {
                for placement in Self.allPlacements {
                    var placement = placement
                    placement.size = size
                    let frame = try #require(LockScreenGeometry.cardFrame(in: screen, placement: placement), "\(size) \(placement) on \(screen)")
                    #expect(frame.minY >= screen.minY + screen.height * 0.45, "\(size) \(placement) on \(screen)")
                    #expect(frame.maxY <= screen.maxY - screen.height * 0.30 + 0.001, "\(size) \(placement) on \(screen)")
                    #expect(screen.contains(frame), "\(size) \(placement) on \(screen)")
                    #expect(frame.width <= LockScreenGeometry.maxSize.width && frame.width <= screen.width * 0.4, "\(size) on \(screen)")
                    #expect(frame.height <= LockScreenGeometry.maxSize.height, "\(size) on \(screen)")
                }
            }
        }
    }

    @Test("Small, Medium and Large are 0.8, 1 and 1.3 times the tested size; Medium is the tested size")
    func sizesScaleTheBase() {
        #expect(LockScreenGeometry.Size.medium.dimensions == CGSize(width: 360, height: 120))
        #expect(LockScreenGeometry.Size.small.dimensions.width < 360 && LockScreenGeometry.Size.large.dimensions.width > 360)
        #expect(LockScreenGeometry.Size.small.dimensions.height < 120 && LockScreenGeometry.Size.large.dimensions.height > 120)
        #expect(LockScreenGeometry.maxSize == LockScreenGeometry.Size.large.dimensions)
        #expect(LockScreenGeometry.Placement().size == .medium)
    }

    @Test("A larger size gives a larger card, and Large in the middle is lifted, never lowered, to stay out of the bottom 45 %")
    func sizesChangeTheFrame() throws {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1243)
        func frame(_ size: LockScreenGeometry.Size) throws -> CGRect {
            try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .center, size: size)))
        }
        let small = try frame(.small), medium = try frame(.medium), large = try frame(.large)
        #expect(small.width < medium.width && medium.width < large.width)
        #expect(small.height < medium.height && medium.height < large.height)
        #expect(abs(medium.midY - screen.midY) < 0.5)
        #expect(large.minY >= screen.height * 0.45)
        #expect(large.midY >= screen.midY)
    }

    @Test("The default is the Stage 2 position: centred, under the clock")
    func defaultMatchesTheSpike() throws {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1243)
        let frame = try #require(LockScreenGeometry.cardFrame(in: screen))
        #expect(frame == (try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .underClock, horizontal: .center)))))
        #expect(abs(frame.maxY - (screen.maxY - screen.height * 0.30)) < 0.5)
    }

    @Test("Middle puts the card's centre on the screen's middle where the band allows it")
    func middleIsCentred() throws {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1243)
        let frame = try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .center)))
        #expect(abs(frame.midY - screen.midY) < 0.5)
    }

    @Test("On a screen where the middle would be too low, the card is pulled up into the band")
    func middleIsClamped() throws {
        // A 16:10 panel scaled up: the middle minus half a card dips below 45 %.
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 400)
        let frame = try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .center)))
        #expect(frame.minY >= screen.minY + screen.height * 0.45)
    }

    @Test("Left and right sit a margin in from the edge; centre is centred")
    func horizontal() throws {
        let screen = CGRect(x: 100, y: 0, width: 1920, height: 1243)
        let margin = screen.width * LockScreenGeometry.sideMarginFraction
        let left = try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .left)))
        let right = try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .right)))
        let centre = try #require(LockScreenGeometry.cardFrame(in: screen, placement: Placement(vertical: .middle, horizontal: .center)))
        #expect(abs(left.minX - (screen.minX + margin)) < 0.5)
        #expect(abs(right.maxX - (screen.maxX - margin)) < 0.5)
        #expect(abs(centre.midX - screen.midX) < 0.5)
    }

    @Test("A screen too small for the rules gets no card, whatever the placement")
    func tooSmall() {
        for placement in Self.allPlacements {
            #expect(LockScreenGeometry.cardFrame(in: CGRect(x: 0, y: 0, width: 200, height: 200), placement: placement) == nil)
            #expect(LockScreenGeometry.cardFrame(in: .zero, placement: placement) == nil)
        }
    }
}

@Suite("LockScreenCardText")
struct LockScreenCardTextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let utc = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US")

    private func event(_ title: String = "Stand-up", in minutes: Double, lasting: Double = 30, allDay: Bool = false,
                       cancelled: Bool = false, declined: Bool = false) -> CalendarEventSnapshot {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEventSnapshot(id: "\(title)\(minutes)", title: title, start: start, end: start.addingTimeInterval(lasting * 60),
                                     isAllDay: allDay, isCancelled: cancelled, isDeclined: declined, calendarID: "work", calendarName: "Work",
                                     color: ColorValue(red: 0, green: 0, blue: 255), location: nil, urlString: nil, notes: nil)
    }

    private func line(_ events: [CalendarEventSnapshot], title: Bool = false) -> String? {
        LockScreenCardText.nextEvent(events, now: now, showTitle: title, locale: locale, timeZone: utc)
    }

    @Test("Without the title switch, the line never contains the title")
    func titleHiddenByDefault() {
        #expect(line([event("Therapy", in: 12)]) == "Event in 12 min")
        #expect(line([event("Therapy", in: 12)])?.contains("Therapy") == false)
        #expect(line([event("Therapy", in: 12)], title: true) == "Therapy in 12 min")
    }

    @Test("Minutes round up, and under an hour reads as minutes")
    func minutes() {
        #expect(line([event(in: 0.5)]) == "Event in 1 min")
        #expect(line([event(in: 59)]) == "Event in 59 min")
        // 59.5 minutes rounds up to 60, which reads as a clock time, never "in 60 min".
        #expect(line([event(in: 59.5)])?.hasPrefix("Event at ") == true)
    }

    @Test("An hour or more away reads as a clock time")
    func clockTime() {
        let text = line([event(in: 120)])
        #expect(text?.hasPrefix("Event at ") == true)
        #expect(text?.contains("in ") == false)
    }

    @Test("Just started reads as now; long started doesn't count")
    func now_() {
        #expect(line([event(in: -2, lasting: 30)]) == "Event now")
        #expect(line([event(in: -10, lasting: 60)]) == nil)
    }

    @Test("All-day, cancelled, declined and far-off events are ignored; the earliest wins")
    func filtering() {
        #expect(line([event(in: 10, allDay: true)]) == nil)
        #expect(line([event(in: 10, cancelled: true)]) == nil)
        #expect(line([event(in: 10, declined: true)]) == nil)
        #expect(line([event(in: 13 * 60)]) == nil)
        #expect(line([event("Later", in: 90), event("Sooner", in: 20)], title: true) == "Sooner in 20 min")
        #expect(line([]) == nil)
    }

    @Test("A blank title falls back to a plain Event")
    func blankTitle() {
        #expect(line([event("   ", in: 5)], title: true) == "Event in 5 min")
    }

    @Test("Battery text and symbols")
    func battery() {
        #expect(LockScreenCardText.batteryText(level: 82) == "82%")
        #expect(LockScreenCardText.batteryText(level: 140) == "100%")
        #expect(LockScreenCardText.batteryText(level: -3) == "0%")
        #expect(LockScreenCardText.batterySymbol(level: 5, charging: false) == "battery.0percent")
        #expect(LockScreenCardText.batterySymbol(level: 50, charging: false) == "battery.50percent")
        #expect(LockScreenCardText.batterySymbol(level: 100, charging: false) == "battery.100percent")
        #expect(LockScreenCardText.batterySymbol(level: 10, charging: true) == "battery.100percent.bolt")
    }
}

@MainActor
@Suite("LockScreenSettings")
struct LockScreenSettingsTests {
    private func fresh() -> UserDefaults {
        let name = "LockScreenSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Everything personal starts off; the rest of the card starts on (ADR-0031 §4)")
    func defaults() {
        let settings = LockScreenSettings(defaults: fresh())
        #expect(settings.options == LockScreenCardOptions(showTrack: true, showArtwork: true, showBattery: true, showEvent: true,
                                                          showEventTitle: false, showLyrics: false))
        #expect(!settings.otherDisplays)
        #expect(!settings.otherAccounts)
        #expect(settings.placement == LockScreenGeometry.Placement(vertical: .middle, horizontal: .center))
        #expect(settings.style == .solid)
        #expect(settings.size == .medium)
        #expect(settings.lastOffReason == nil)
    }

    @Test("Changes persist")
    func persistence() {
        let defaults = fresh()
        let settings = LockScreenSettings(defaults: defaults)
        settings.showEventTitle = true
        settings.vertical = .underClock
        settings.horizontal = .right
        settings.style = .glass
        settings.size = .large
        settings.otherDisplays = true
        settings.lastOffReason = "why"
        let again = LockScreenSettings(defaults: defaults)
        #expect(again.showEventTitle)
        #expect(again.placement == LockScreenGeometry.Placement(vertical: .underClock, horizontal: .right, size: .large))
        #expect(again.style == .glass)
        #expect(again.options.style == .glass)
        #expect(again.otherDisplays)
        #expect(again.lastOffReason == "why")
    }

    @Test("A stored value that no longer exists falls back to the default")
    func unknownValues() {
        let defaults = fresh()
        defaults.set("diagonal", forKey: LockScreenSettings.Key.vertical)
        defaults.set("up", forKey: LockScreenSettings.Key.horizontal)
        defaults.set("frosted", forKey: LockScreenSettings.Key.style)
        defaults.set("huge", forKey: LockScreenSettings.Key.size)
        let settings = LockScreenSettings(defaults: defaults)
        #expect(settings.placement == LockScreenGeometry.Placement(vertical: .middle, horizontal: .center))
        #expect(settings.style == .solid)
        #expect(settings.size == .medium)
    }

    @Test("Each way the feature turns itself off has words for Settings")
    func explanations() {
        for reason in [LockScreenReducer.OffReason.crashedLastSession, .crashedWhileShowing, .failed("x")] {
            #expect(!reason.explanation.isEmpty)
        }
    }

    @Test("The module is off by default, needs no permission, and never claims to be stable")
    func descriptor() {
        let descriptor = LockScreenModule.descriptor
        #expect(!descriptor.isOnByDefault)
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.summary.hasPrefix("Experimental"))
    }
}

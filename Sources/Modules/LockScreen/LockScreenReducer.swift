// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the lock state reader says (`CGSessionCopyCurrentDictionary`).
/// Anything but `.locked` means "don't show" (ADR-0031 §2: fail closed).
enum LockState: Equatable, Sendable {
    case locked
    case unlocked
    /// The key is missing, the session isn't on the console, or the read failed.
    case unknown
}

/// The lock-screen card's lifecycle (#59, ADR-0031). Pure: the shell turns
/// system signals into events and carries out the effects.
///
/// Invariants (each one tested):
/// - Windows exist only in `.shown`.
/// - `.shown` is reached only from `.pending`, when a lock notification (or a
///   wake, a return to this session, a display change) is followed by a read
///   that says `.locked`, and everything allows it.
/// - Every way out of `.shown` starts with `.destroy`.
/// - Anything unknown, any failure, any kill switch: nothing is shown.
/// - A crash in the last session, or one while the card was showing, turns the
///   feature off until the user turns it on again.
struct LockScreenReducer: Sendable {
    struct Config: Equatable, Sendable {
        var enabled = false
        /// `--no-lock-screen` or `lockScreen.killSwitch`.
        var killSwitch = false
        var includeSecondaryScreens = false
        var allowWithOtherAccounts = false
        var otherAccountsExist = false
        /// The Stage 2 spike destroys the card this long after showing it; nil in the product.
        var maximumLifetime: TimeInterval?
        var confirmDelay: TimeInterval = 0.5
        var watchdogInterval: TimeInterval = 2

        /// Whether a card may be shown at all, before looking at the lock.
        var allowsShowing: Bool {
            enabled && !killSwitch && (!otherAccountsExist || allowWithOtherAccounts)
        }
    }

    enum Phase: Equatable, Sendable {
        /// Not enabled, or turned off for a reason.
        case off
        /// Enabled and waiting for a lock. Nothing exists.
        case armed
        /// A lock signal arrived; waiting for the confirming read.
        case pending
        /// The Space and the card exist.
        case shown
    }

    /// Why the feature turned itself off; the shell turns the setting off and shows this.
    enum OffReason: Equatable, Sendable {
        case crashedLastSession
        case crashedWhileShowing
        case failed(String)
    }

    enum Event: Equatable, Sendable {
        /// At launch, before anything else: what the last session left behind.
        case launched(previousSessionCrashed: Bool, shownFlagWasSet: Bool)
        case configure(Config)
        /// `com.apple.screenIsLocked`.
        case lockNotification
        /// `com.apple.screenIsUnlocked`.
        case unlockNotification
        /// The answer to `.checkLockState`, and each watchdog tick.
        case lockState(LockState)
        /// Fast user switching: this session left, or came back to, the console.
        case sessionResigned
        case sessionBecameActive
        case screensSlept
        case screensWoke
        case displaysChanged
        /// Another app became active: a sign the user may have unlocked.
        case appActivated
        /// The spike's lifetime ran out.
        case lifetimeReached
        /// A private call or window step failed.
        case failure(String)
        case quit
    }

    enum Effect: Equatable, Sendable {
        /// Read the lock state after this many seconds (0: now) and answer `.lockState`.
        case checkLockState(after: TimeInterval)
        /// Persist "the card is showing" before showing it, and clear it after destroying it.
        case setShownFlag(Bool)
        case show(includeSecondaryScreens: Bool)
        /// Hide the Space, close the windows, destroy the Space. Always first on the way out.
        case destroy
        case startWatchdog(every: TimeInterval)
        case stopWatchdog
        case scheduleLifetimeLimit(TimeInterval)
        case cancelLifetimeLimit
        /// Turn the setting off and tell the user why.
        case turnOff(OffReason)
    }

    private(set) var phase: Phase = .off
    private(set) var config = Config()
    /// The spike showed its card for this lock already; don't show it again until unlock.
    private(set) var spentUntilUnlock = false
    /// Between screens sleeping and waking. Closing the lid sends the sleep
    /// signals about 0.2 s *before* the lock notification (spike, 2 Nov), so a
    /// lock seen while asleep waits for the wake, which checks again.
    private(set) var screensAsleep = false

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .launched(let crashed, let wasShowing):
            var effects: [Effect] = wasShowing ? [.setShownFlag(false)] : []
            guard config.enabled, crashed || wasShowing else { return effects }
            config.enabled = false
            phase = .off
            effects.append(.turnOff(wasShowing ? .crashedWhileShowing : .crashedLastSession))
            return effects

        case .configure(let new):
            let old = config
            config = new
            if !new.allowsShowing {
                let effects = leave()
                phase = new.enabled && !new.killSwitch ? .armed : .off
                return effects
            }
            if phase == .off { phase = .armed }
            // A change that alters what is shown (another display) rebuilds it while locked.
            if phase == .shown, old.includeSecondaryScreens != new.includeSecondaryScreens {
                return leave() + recheck(after: 0)
            }
            return []

        case .lockNotification:
            guard config.allowsShowing, phase == .armed, !spentUntilUnlock, !screensAsleep else { return [] }
            phase = .pending
            return [.checkLockState(after: config.confirmDelay)]

        case .screensWoke, .sessionBecameActive, .displaysChanged:
            if event == .screensWoke { screensAsleep = false }
            // Whatever was there goes first; then look again, and show only if confirmed locked.
            let effects = leave()
            guard config.allowsShowing, !spentUntilUnlock else { return effects }
            return effects + recheck(after: config.confirmDelay)

        case .lockState(let state):
            // A confirmed unlock also ends "already shown for this lock", in case the notification was missed.
            if state == .unlocked { spentUntilUnlock = false }
            switch (phase, state) {
            case (.pending, .locked):
                guard config.allowsShowing, !screensAsleep else { phase = .armed; return [] }
                phase = .shown
                var effects: [Effect] = [.setShownFlag(true), .show(includeSecondaryScreens: config.includeSecondaryScreens),
                                         .startWatchdog(every: config.watchdogInterval)]
                if let lifetime = config.maximumLifetime { effects.append(.scheduleLifetimeLimit(lifetime)) }
                return effects
            case (.pending, _):
                phase = .armed
                return []
            case (.shown, .locked):
                return []
            case (.shown, _):
                return leave()
            default:
                return []
            }

        case .unlockNotification:
            spentUntilUnlock = false
            return leave()

        case .appActivated:
            return phase == .shown ? [.checkLockState(after: 0)] : []

        case .screensSlept:
            screensAsleep = true
            return leave()

        case .sessionResigned, .quit:
            return leave()

        case .lifetimeReached:
            guard phase == .shown else { return [] }
            spentUntilUnlock = true
            return leave()

        case .failure(let message):
            let effects = leave()
            config.enabled = false
            phase = .off
            return effects + [.turnOff(.failed(message))]
        }
    }

    /// Back to waiting, destroying the card first if there is one.
    private mutating func leave() -> [Effect] {
        let wasShown = phase == .shown
        if phase == .shown || phase == .pending { phase = config.allowsShowing ? .armed : .off }
        guard wasShown else { return [] }
        var effects: [Effect] = [.destroy, .stopWatchdog]
        if config.maximumLifetime != nil { effects.append(.cancelLifetimeLimit) }
        effects.append(.setShownFlag(false))
        return effects
    }

    private mutating func recheck(after delay: TimeInterval) -> [Effect] {
        guard phase == .armed else { return [] }
        phase = .pending
        return [.checkLockState(after: delay)]
    }
}

/// Where the card goes on one screen (ADR-0031 §3). Pure, so the rule that
/// keeps it away from the password field is tested for every screen size.
enum LockScreenGeometry {
    /// The size the card is designed at, and the one tested on the real lock
    /// screen (Medium). Small and Large are scales of it.
    static let baseSize = CGSize(width: 360, height: 120)
    /// The most the card may ever be: the Large size. Still inside the band
    /// below, which is the rule that protects the password area.
    static let maxSize = Size.large.dimensions

    /// How big the card is. Only a scale of the base size; the band, the width
    /// cap and the final check below apply to every size.
    enum Size: String, CaseIterable, Sendable {
        case small, medium, large

        var scale: CGFloat {
            switch self {
            case .small: 0.8
            case .medium: 1
            case .large: 1.3
            }
        }

        var dimensions: CGSize {
            CGSize(width: LockScreenGeometry.baseSize.width * scale, height: LockScreenGeometry.baseSize.height * scale)
        }
    }
    /// The card's top edge sits this far down from the top of the screen.
    static let topFraction: CGFloat = 0.30
    /// Nothing may reach into the bottom of the screen, where the avatar,
    /// password field, user list and Touch ID prompt are.
    static let forbiddenBottomFraction: CGFloat = 0.45
    static let maxWidthFraction: CGFloat = 0.40

    /// Where on the screen the card sits, inside the band the rules allow
    /// (ADR-0031 §3 and §7). The choices only pick a position inside the band;
    /// nothing here can move the band's edges.
    struct Placement: Equatable, Sendable {
        enum Vertical: String, CaseIterable, Sendable {
            /// Top at 30 % of the screen height: just under the clock.
            case underClock
            /// Centred on the screen's middle, kept inside the band.
            case middle
        }

        enum Horizontal: String, CaseIterable, Sendable {
            case left, center, right
        }

        var vertical: Vertical = .underClock
        var horizontal: Horizontal = .center
        var size: Size = .medium

        init(vertical: Vertical = .underClock, horizontal: Horizontal = .center, size: Size = .medium) {
            self.vertical = vertical
            self.horizontal = horizontal
            self.size = size
        }
    }

    /// Left and right keep this far from the screen's edge (a fraction of its width).
    static let sideMarginFraction: CGFloat = 0.06

    /// The card's frame in AppKit screen coordinates (origin at the bottom
    /// left), or nil if no frame fits the rules on this screen.
    static func cardFrame(in screen: CGRect, preferred: CGSize? = nil, placement: Placement = Placement()) -> CGRect? {
        guard screen.width > 0, screen.height > 0 else { return nil }
        let wanted = preferred ?? placement.size.dimensions
        let width = min(wanted.width, maxSize.width, screen.width * maxWidthFraction)
        let limitTop = screen.maxY - screen.height * topFraction
        let floor = screen.minY + screen.height * forbiddenBottomFraction
        let height = min(wanted.height, maxSize.height, limitTop - floor)
        guard width >= 120, height >= 40 else { return nil }

        let top: CGFloat
        switch placement.vertical {
        case .underClock:
            top = limitTop
        case .middle:
            // Centred on the screen's middle, then pulled into the band.
            top = min(max(screen.midY + height / 2, floor + height), limitTop)
        }

        let margin = screen.width * sideMarginFraction
        let x: CGFloat
        switch placement.horizontal {
        case .left: x = screen.minX + margin
        case .center: x = screen.midX - width / 2
        case .right: x = screen.maxX - margin - width
        }

        let frame = CGRect(x: x, y: top - height, width: width, height: height)
        // The last check is the rule itself: whatever was asked for, a frame
        // outside the band or off the screen is never returned.
        return frame.minY >= floor && frame.maxY <= limitTop + 0.001 && screen.contains(frame) ? frame : nil
    }
}

/// The ways to switch the feature off before anything starts (ADR-0031 §1).
enum LockScreenKillSwitch {
    static let launchArgument = "--no-lock-screen"
    static let defaultsKey = "lockScreen.killSwitch"

    static func isActive(arguments: [String], defaults: UserDefaults) -> Bool {
        arguments.contains(launchArgument) || defaults.bool(forKey: defaultsKey)
    }
}

/// Whether this Mac has another account someone could log in with (ADR-0031 §6.4).
enum LocalAccounts {
    struct Entry: Equatable, Sendable {
        var name: String
        var uid: UInt32
        var shell: String
    }

    /// Login accounts other than `current`: UID 501 or above, a real shell,
    /// not a system account (whose names start with "_").
    static func otherLoginAccounts(in entries: [Entry], current: String) -> [String] {
        let noLogin: Set<String> = ["/usr/bin/false", "/sbin/nologin", "/usr/sbin/nologin", ""]
        return entries
            .filter { $0.uid >= 501 && $0.uid < 0xFFFF_FFFE && !noLogin.contains($0.shell) && !$0.name.hasPrefix("_") && $0.name != current }
            .map(\.name)
    }
}

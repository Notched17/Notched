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
            guard config.allowsShowing, phase == .armed, !spentUntilUnlock else { return [] }
            phase = .pending
            return [.checkLockState(after: config.confirmDelay)]

        case .screensWoke, .sessionBecameActive, .displaysChanged:
            // Whatever was there goes first; then look again, and show only if confirmed locked.
            let effects = leave()
            guard config.allowsShowing, !spentUntilUnlock else { return effects }
            return effects + recheck(after: config.confirmDelay)

        case .lockState(let state):
            // A confirmed unlock also ends "already shown for this lock", in case the notification was missed.
            if state == .unlocked { spentUntilUnlock = false }
            switch (phase, state) {
            case (.pending, .locked):
                guard config.allowsShowing else { phase = .armed; return [] }
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

        case .sessionResigned, .screensSlept, .quit:
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
    static let maxSize = CGSize(width: 360, height: 120)
    /// The card's top edge sits this far down from the top of the screen.
    static let topFraction: CGFloat = 0.30
    /// Nothing may reach into the bottom of the screen, where the avatar,
    /// password field, user list and Touch ID prompt are.
    static let forbiddenBottomFraction: CGFloat = 0.45
    static let maxWidthFraction: CGFloat = 0.40

    /// The card's frame in AppKit screen coordinates (origin at the bottom
    /// left), or nil if no frame fits the rules on this screen.
    static func cardFrame(in screen: CGRect, preferred: CGSize = maxSize) -> CGRect? {
        guard screen.width > 0, screen.height > 0 else { return nil }
        let width = min(preferred.width, maxSize.width, screen.width * maxWidthFraction)
        let top = screen.maxY - screen.height * topFraction
        let floor = screen.minY + screen.height * forbiddenBottomFraction
        let height = min(preferred.height, maxSize.height, top - floor)
        guard width >= 120, height >= 40 else { return nil }
        let frame = CGRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
        return frame.minY >= floor && screen.contains(frame) ? frame : nil
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

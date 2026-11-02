// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The lock-screen card's shell (#59, ADR-0031): system signals in, the
/// reducer's effects out. Used by the Stage 2 spike now and by the module in
/// Stage 3. Observes nothing and runs no timers unless the feature is on.
@MainActor
final class LockScreenController {
    typealias Event = LockScreenReducer.Event
    typealias Effect = LockScreenReducer.Effect

    static let shownFlagKey = "lockScreen.windowsShown"

    /// The card's content for the screen at this index (0 is the primary).
    private let content: @MainActor (Int) -> AnyView
    private let defaults: UserDefaults
    /// Called when the reducer turns the feature off; the owner turns the setting off.
    var onTurnOff: @MainActor (LockScreenReducer.OffReason) -> Void = { _ in }
    /// Every event and effect, for the spike's report.
    var trace: (@MainActor (String) -> Void)?

    private var reducer = LockScreenReducer()
    private let observers = NotificationTokens()
    private var isObserving = false
    private var skyLight: SkyLightLockScreen?
    private var panels: [LockScreenPanel] = []
    private var watchdog: Task<Void, Never>?
    private var lifetime: Task<Void, Never>?
    /// The pending lock read; a newer request replaces it.
    private var check: Task<Void, Never>?
    private var queue: [Event] = []
    private var isSending = false

    init(defaults: UserDefaults = .standard, content: @escaping @MainActor (Int) -> AnyView) {
        self.defaults = defaults
        self.content = content
    }

    var phase: LockScreenReducer.Phase { reducer.phase }

    /// Applies the settings; starts or stops listening to match.
    func apply(_ config: LockScreenReducer.Config) {
        send(.configure(config))
        let listen = config.enabled && !config.killSwitch
        if listen, !isObserving { startObserving() }
        if !listen, isObserving { stopObserving() }
    }

    /// At launch, after `apply`: what the last session left behind.
    func launch(previousSessionCrashed: Bool) {
        send(.launched(previousSessionCrashed: previousSessionCrashed, shownFlagWasSet: defaults.bool(forKey: Self.shownFlagKey)))
    }

    /// Events are queued, so an effect that fails (and sends `.failure`) is
    /// handled after the current effects, never halfway through them.
    func send(_ event: Event) {
        queue.append(event)
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            let effects = reducer.reduce(next, now: Date())
            trace?("\(next) → \(reducer.phase)\(effects.isEmpty ? "" : ": \(effects)")")
            for effect in effects { perform(effect) }
        }
    }

    // MARK: Effects

    private func perform(_ effect: Effect) {
        switch effect {
        case .destroy:
            skyLight?.tearDown(closing: panels)
            panels = []
            skyLight = nil
        case .checkLockState(let delay):
            check?.cancel()
            check = Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                self?.send(.lockState(LockStateReader.current()))
            }
        case .setShownFlag(let shown):
            defaults.set(shown, forKey: Self.shownFlagKey)
        case .show(let includeSecondary):
            showCards(includeSecondaryScreens: includeSecondary)
        case .startWatchdog(let interval):
            watchdog?.cancel()
            watchdog = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                    self?.send(.lockState(LockStateReader.current()))
                }
            }
        case .stopWatchdog:
            watchdog?.cancel()
            watchdog = nil
        case .scheduleLifetimeLimit(let seconds):
            lifetime?.cancel()
            lifetime = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.send(.lifetimeReached)
            }
        case .cancelLifetimeLimit:
            lifetime?.cancel()
            lifetime = nil
        case .turnOff(let reason):
            stopObserving()
            onTurnOff(reason)
        }
    }

    private func showCards(includeSecondaryScreens: Bool) {
        guard let skyLight = SkyLightLockScreen.make() else {
            send(.failure("SkyLight is unavailable on this macOS"))
            return
        }
        self.skyLight = skyLight
        let screens = includeSecondaryScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        do {
            try skyLight.createSpace()
            for (index, screen) in screens.enumerated() {
                guard let frame = LockScreenGeometry.cardFrame(in: screen.frame) else {
                    trace?("no safe frame on screen \(index) \(NSStringFromRect(screen.frame)); nothing shown there")
                    continue
                }
                let panel = LockScreenPanel(frame: frame, content: content(index))
                panels.append(panel)
                try skyLight.add(panel)
                panel.orderFrontRegardless()
                trace?("card on screen \(index) at \(NSStringFromRect(frame))")
            }
        } catch {
            send(.failure("\(error)"))
        }
    }

    // MARK: Signals

    private func startObserving() {
        isObserving = true
        let distributed = DistributedNotificationCenter.default()
        observers.observe(Notification.Name("com.apple.screenIsLocked"), in: distributed) { [weak self] in self?.send(.lockNotification) }
        observers.observe(Notification.Name("com.apple.screenIsUnlocked"), in: distributed) { [weak self] in self?.send(.unlockNotification) }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.observe(NSWorkspace.sessionDidResignActiveNotification, in: workspace) { [weak self] in self?.send(.sessionResigned) }
        observers.observe(NSWorkspace.sessionDidBecomeActiveNotification, in: workspace) { [weak self] in self?.send(.sessionBecameActive) }
        observers.observe(NSWorkspace.screensDidSleepNotification, in: workspace) { [weak self] in self?.send(.screensSlept) }
        observers.observe(NSWorkspace.willSleepNotification, in: workspace) { [weak self] in self?.send(.screensSlept) }
        observers.observe(NSWorkspace.screensDidWakeNotification, in: workspace) { [weak self] in self?.send(.screensWoke) }
        observers.observe(NSWorkspace.didActivateApplicationNotification, in: workspace) { [weak self] in self?.send(.appActivated) }
        observers.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.send(.displaysChanged) }
        observers.observe(NSApplication.willTerminateNotification) { [weak self] in self?.send(.quit) }
    }

    private func stopObserving() {
        isObserving = false
        observers.invalidate()
        check?.cancel()
        check = nil
    }
}

/// The card's window: small, borderless, never key, never main, and
/// click-through (ADR-0031 §3). Hidden from VoiceOver so it can't take focus
/// from the password field.
final class LockScreenPanel: NSPanel {
    init(frame: CGRect, content: AnyView) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        // Within our own Space; the Space's absolute level is what puts it above the lock screen.
        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
        let host = NSHostingView(rootView: content.accessibilityHidden(true))
        host.frame = NSRect(origin: .zero, size: frame.size)
        contentView = host
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

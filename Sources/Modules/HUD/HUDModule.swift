// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Volume and brightness HUD (#20, #21): the island shows the change instead
/// of the macOS HUD. A thin shell around `HUDKeyEngine`: it owns the
/// permission, the tap's lifecycle, the off switches and the latch, and turns
/// what the engine delivers into banners. All the rules about which key goes
/// where live in `HUDKeyReducer` (the safety design in
/// docs/superpowers/specs/2026-10-29-m3b-hud-tap-safety-design.md).
///
/// It asks for Accessibility (when the module is turned on) and installs no
/// tap without it. Turning the module off, Pause HUD Replacement, and a
/// revoked permission all remove the tap, and the keys go straight back to macOS.
@MainActor
@Observable
final class HUDModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "hud",
        name: "Volume & Brightness",
        symbol: "speaker.wave.2.fill",
        summary: "Shows volume and brightness changes in the island instead of the macOS HUD.",
        permissions: [.accessibility],
        isDebugOnly: false
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(HUDSettingsPane(settings: context.settings.hud, registry: context.registry, permissions: context.permissions))
    }

    private(set) var status: HUDStatus = .notAllowed
    var isArmed: Bool { tap != nil }

    /// Lets the engine's delivery find the module without keeping it alive.
    private final class WeakModule: @unchecked Sendable {
        weak var module: HUDModule?
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let judgesLaunch: Bool
    @ObservationIgnored private let observers = NotificationTokens()
    @ObservationIgnored private let trustTimer = OneShotTimer()
    @ObservationIgnored private let verifyTimer = OneShotTimer()
    @ObservationIgnored private var engine: HUDKeyEngine?
    @ObservationIgnored private var tap: (any MediaKeyTapping)?
    @ObservationIgnored private var trustToken: RefreshToken?
    @ObservationIgnored private var isRunning = false
    /// Stale observation chains from an earlier arming check this and stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastOutputID: UInt32?
    /// Counts what's shown, so a press at a limit can nudge the bar each time.
    @ObservationIgnored private var showSerial = 0
    @ObservationIgnored private var lastReading: [HUDKind: HUDReading] = [:]
    @ObservationIgnored private let log = Log.module("hud")

    /// What the module reaches the system through, so tests can stand in fakes.
    struct Dependencies {
        var makeTap: @MainActor (HUDKeyEngine) -> any MediaKeyTapping = { MediaKeyTap(engine: $0) }
        var volume: any LevelControl & MuteControl = CoreAudioVolumeControl()
        var isTrusted: @MainActor () -> Bool = { AXIsProcessTrusted() }
        var feedbackEnabled: @MainActor () -> Bool = { HUDFeedback.systemPreference }
        var playFeedback: @MainActor () -> Void = { HUDFeedback.play() }
    }

    /// The first module started in a process judges how the last session ended.
    private static var launchJudged = false

    private var settings: HUDSettings { context.settings.hud }

    convenience init(context: ModuleContext) {
        self.init(context: context, dependencies: Dependencies(), judgesLaunch: !Self.launchJudged)
    }

    init(context: ModuleContext, dependencies: Dependencies, judgesLaunch: Bool) {
        self.context = context
        self.dependencies = dependencies
        self.judgesLaunch = judgesLaunch
        Self.launchJudged = true
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if judgesLaunch { judgeLaunch() }
        // Granting Accessibility in System Settings arms it without a restart.
        observers.observe(Notification.Name("com.apple.accessibility.api"), in: DistributedNotificationCenter.default()) { [weak self] in
            self?.trustTimer.schedule(at: Date().addingTimeInterval(0.5))
        }
        observers.observe(NSApplication.didBecomeActiveNotification) { [weak self] in self?.checkTrust() }
        trustTimer.action = { [weak self] in self?.checkTrust() }
        verifyTimer.action = { [weak self] in self?.engine?.send(.verifyDue) }
        arm()
        refreshStatus()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        disarm()
        observers.invalidate()
        trustTimer.schedule(at: nil)
        verifyTimer.schedule(at: nil)
        context.activities.endAll()
    }

    /// Two sessions in a row that ended while armed start the HUD latched off.
    private func judgeLaunch() {
        let verdict = HUDLatchRule.judgeLaunch(previousSessionCrashed: context.previousSessionCrashed,
                                               wasArmed: settings.armedSession, streak: settings.uncleanStreak)
        settings.uncleanStreak = verdict.streak
        settings.armedSession = false
        if verdict.latch { settings.latch = HUDLatch(reason: .uncleanExits, date: Date()) }
    }

    // MARK: Arming

    private func arm() {
        guard isRunning, tap == nil, !settings.isPaused, settings.latch == nil, dependencies.isTrusted() else { return }
        let weakModule = WeakModule()
        weakModule.module = self
        let engine = HUDKeyEngine(volume: dependencies.volume, brightness: nil) { effects in
            // On the main thread (a state change) handle it now; from the tap thread, hop over.
            if Thread.isMainThread {
                MainActor.assumeIsolated { weakModule.module?.handle(effects) }
            } else {
                Task { @MainActor in weakModule.module?.handle(effects) }
            }
        }
        let tap = dependencies.makeTap(engine)
        guard tap.install() else {
            log.error("The event tap couldn't be installed")
            return
        }
        self.engine = engine
        self.tap = tap
        settings.armedSession = true
        generation += 1
        let outputs = context.services.audioOutputs
        outputs.acquire()
        lastOutputID = outputs.current?.id
        trustToken = context.scheduler.register("hud.trust", every: .seconds(2)) { [weak self] in self?.checkTrust() }
        engine.send(.trust(true))
        engine.send(.visible(context.services.presence?.canShowHUD ?? true))
        engine.send(.armed(true))
        followPresence(generation)
        followOutput(generation)
    }

    /// Keys go to macOS from the first line on, even if the teardown is slow.
    private func disarm() {
        guard let engine, let tap else { return }
        engine.send(.armed(false))
        tap.setEnabled(false)
        tap.remove()
        self.engine = nil
        self.tap = nil
        generation += 1
        if let trustToken { context.scheduler.unregister(trustToken) }
        trustToken = nil
        context.services.audioOutputs.release()
        verifyTimer.schedule(at: nil)
        settings.armedSession = false
    }

    // MARK: Following the system

    /// Whether the island can show a HUD, and whether the tap should be on
    /// at all (not while paused, locked or asleep: macOS's HUD shows then).
    private func followPresence(_ generation: Int) {
        guard generation == self.generation, tap != nil else { return }
        let presence = context.services.presence
        let (canShow, suspended, paused) = withObservationTracking {
            (presence?.canShowHUD ?? true, presence?.isSuspended ?? false, presence?.isPaused ?? false)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followPresence(generation) }
        }
        engine?.send(.visible(canShow))
        tap?.setEnabled(!(suspended || paused))
    }

    /// A new output device starts the pending and failure counts afresh.
    private func followOutput(_ generation: Int) {
        guard generation == self.generation, tap != nil else { return }
        let outputs = context.services.audioOutputs
        let id = withObservationTracking {
            outputs.current?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.followOutput(generation) }
        }
        if id != lastOutputID {
            lastOutputID = id
            engine?.send(.targetChanged(.volume))
        }
    }

    /// Re-reads the permission (every 2 s while armed, on app activation, and
    /// when System Settings changes it): revoked removes the tap, granted arms it.
    func checkTrust() {
        guard isRunning else { return }
        let trusted = dependencies.isTrusted()
        if tap != nil {
            engine?.send(.trust(trusted))
        } else if trusted {
            arm()
        }
        refreshStatus()
    }

    // MARK: What the engine delivers

    private func handle(_ effects: [HUDKeyReducer.Effect]) {
        guard isRunning else { return }
        for effect in effects {
            switch effect {
            case .show(let reading, let modifiers):
                show(reading, modifiers: modifiers)
            case .wake(let date):
                verifyTimer.schedule(at: date)
            case .removeTap(let reason):
                log.error("HUD tap removed: \(reason.rawValue, privacy: .public)")
                disarm()
            case .latch(let reason):
                settings.latch = HUDLatch(reason: reason, date: Date())
                context.activities.show(Self.latchedBanner)
            case .apply, .pass, .swallow, .reapply, .reEnableTap:
                break
            }
        }
        refreshStatus()
    }

    /// The banner for a swallowed key, and the click a volume change makes.
    private func show(_ reading: HUDReading, modifiers: MediaKeyEvent.Modifiers) {
        showSerial += 1
        let device = reading.kind == .volume ? context.services.audioOutputs.current : nil
        context.activities.show(HUDBanner.make(reading: reading, device: device, serial: showSerial))
        // A mute press keeps the level and flips the mute; macOS doesn't click for it, or at a limit.
        let previous = lastReading[reading.kind]
        let isMuteToggle = previous.map { $0.level == reading.level && $0.isMuted != reading.isMuted } ?? false
        lastReading[reading.kind] = reading
        guard reading.kind == .volume, !reading.atLimit, !isMuteToggle,
              HUDFeedback.shouldPlay(preference: dependencies.feedbackEnabled(), modifiers: modifiers) else { return }
        dependencies.playFeedback()
    }

    static var latchedBanner: TransientBanner {
        .standard(id: "hud.latched", moduleID: descriptor.id,
                  content: BannerContent(symbol: "speaker.slash.fill", symbolTint: .yellow, label: "HUD paused"),
                  priority: .high, accessibilityLabel: "HUD replacement paused")
    }

    // MARK: Off switches

    /// Pause HUD Replacement. Unpausing also clears a latch (design §6).
    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        if paused {
            disarm()
        } else {
            settings.latch = nil
            settings.uncleanStreak = 0
            arm()
        }
        refreshStatus()
    }

    /// The pane's Turn Back On after the HUD turned itself off.
    func turnBackOn() {
        setPaused(false)
    }

    private func refreshStatus() {
        if let latch = settings.latch {
            status = .latched(latch)
        } else if settings.isPaused {
            status = .paused
        } else if tap != nil {
            status = .running
        } else {
            status = .notAllowed
        }
    }

    func menuItems() -> [NSMenuItem] {
        let item = ClosureMenuItem(title: "Pause HUD Replacement") { [weak self] in
            guard let self else { return }
            setPaused(!settings.isPaused)
        }
        item.state = settings.isPaused ? .on : .off
        return [item]
    }
}

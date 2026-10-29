// SPDX-License-Identifier: GPL-3.0-or-later
//
// The pattern (an active tap on system-defined events, re-enabled on timeout,
// with the key only swallowed once the change took effect) follows
// dannystewart/volumeHUD (MIT); this is a fresh implementation around the
// safety design in docs/superpowers/specs/2026-10-29-m3b-hud-tap-safety-design.md.

import AppKit
import ApplicationServices
import CoreGraphics
import os

/// The only file that touches `CGEventTap` (the safety design §1 and §2).
///
/// An active session tap whose mask is `NX_SYSDEFINED` and nothing else, so
/// typing, shortcuts and the mouse never pass through it. It runs on its own
/// thread with its own run loop: a busy UI can't delay a key, and a stuck tap
/// can't freeze the menu bar. The callback never waits on the main actor.
///
/// Every decision lives in `HUDKeyEngine`; this class creates the tap, turns
/// events into `MediaKeyEvent`s, returns the verdict, and tears down.
final class MediaKeyTap: @unchecked Sendable {
    /// What the callback needs. Retained for as long as the thread runs.
    private final class Context: @unchecked Sendable {
        let engine: HUDKeyEngine
        weak var tap: MediaKeyTap?
        init(engine: HUDKeyEngine, tap: MediaKeyTap) {
            self.engine = engine
            self.tap = tap
        }
    }

    private static let log = Logger(subsystem: Log.root, category: "hud.tap")

    private let engine: HUDKeyEngine
    private let lock = NSLock()
    /// All guarded by `lock`.
    private var port: CFMachPort?
    private var loop: CFRunLoop?
    private var thread: Thread?
    private var exited: DispatchSemaphore?

    init(engine: HUDKeyEngine) {
        self.engine = engine
    }

    var isInstalled: Bool { lock.withLock { port != nil } }

    /// Starts the thread and creates the tap on it. False, with nothing left
    /// running, if Accessibility isn't granted or the system refuses the tap.
    func install() -> Bool {
        guard AXIsProcessTrusted() else {
            Self.log.notice("Not installing the tap: Accessibility isn't granted")
            return false
        }
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let started: Bool = lock.withLock {
            guard thread == nil else { return false }
            let thread = Thread { [self] in threadMain(ready: ready, done: done) }
            thread.name = "me.rkck.Notched.media-key-tap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            exited = done
            thread.start()
            return true
        }
        if started, ready.wait(timeout: .now() + 1) == .timedOut {
            Self.log.error("The tap thread didn't report in time")
        }
        return isInstalled
    }

    /// Pauses or resumes delivery without tearing the tap down.
    func setEnabled(_ enabled: Bool) {
        guard let port = lock.withLock({ self.port }) else { return }
        CGEvent.tapEnable(tap: port, enable: enabled)
    }

    /// Disables the tap at once, then stops the thread and waits for it to
    /// finish (up to a second). Safe to call twice, and from any thread.
    func remove() {
        let (port, loop, thread, done) = lock.withLock { (self.port, self.loop, self.thread, self.exited) }
        // Delivery stops now, even if the teardown below is slow.
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
        CFRunLoopWakeUp(loop)
        guard Thread.current !== thread, let done else { return }
        if done.wait(timeout: .now() + 1) == .timedOut {
            Self.log.error("The tap thread was slow to stop")
        }
    }

    // MARK: Tap thread

    private func threadMain(ready: DispatchSemaphore, done: DispatchSemaphore) {
        let context = Unmanaged.passRetained(Context(engine: engine, tap: self))
        defer {
            context.release()
            lock.withLock {
                port = nil
                loop = nil
                thread = nil
                exited = nil
            }
            done.signal()
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: 1 << 14, callback: Self.callback, userInfo: context.toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            Self.log.error("The system refused the event tap")
            ready.signal()
            return
        }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        lock.withLock {
            self.port = port
            self.loop = loop
        }
        CGEvent.tapEnable(tap: port, enable: true)
        Self.log.notice("Media-key tap installed")
        ready.signal()

        CFRunLoopRun()

        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        Self.log.notice("Media-key tap removed")
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        let pass = Unmanaged.passUnretained(event)
        guard let info else { return pass }
        let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let action = context.engine.tapDisabled(byTimeout: type == .tapDisabledByTimeout, trusted: AXIsProcessTrusted())
            context.tap?.perform(action)
            return pass
        }
        guard type.rawValue == 14 else { return pass }

        let started = ContinuousClock.now
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return pass }
        // The flags are read from the event, the NSEvent and the session, as
        // each has been seen to miss held modifiers on some macOS versions.
        let flags = event.flags.rawValue
            | UInt64(nsEvent.modifierFlags.rawValue)
            | CGEventSource.flagsState(.combinedSessionState).rawValue
        guard let key = MediaKeyEvent.parse(subtype: 8, data1: nsEvent.data1, flags: flags) else { return pass }

        let verdict = context.engine.handle(key)
        let took = started.duration(to: .now)
        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
        context.tap?.perform(context.engine.callbackTook(seconds))
        return verdict == .swallow ? nil : pass
    }

    /// Acts on the engine's verdict about the tap's own health, inside the
    /// callback. Removal can't wait for the thread it runs on, so it moves off it.
    private func perform(_ action: TapHealthAction) {
        switch action {
        case .none:
            break
        case .reEnable:
            if let port = lock.withLock({ self.port }) {
                CGEvent.tapEnable(tap: port, enable: true)
                Self.log.notice("Media-key tap re-enabled")
            }
        case .remove(let reason):
            Self.log.error("Removing the media-key tap: \(reason.rawValue, privacy: .public)")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.remove() }
        }
    }
}

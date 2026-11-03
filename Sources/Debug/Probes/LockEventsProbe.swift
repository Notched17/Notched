// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import CoreGraphics
import Foundation

/// M6 spike 6.3, Stage 1 research (ADR-0031). **Creates no windows.** It only
/// logs which lock, sleep and session signals macOS sends, in what order, and
/// what `CGSessionCopyCurrentDictionary()` says about the lock at each one (at
/// once, after 0.5 s and after 2 s), because the lock-screen design shows
/// nothing unless two of these signals agree.
///
///     open -g "notched://debug/probe?name=lockevents&action=start"
///     open -g "notched://debug/probe?name=lockevents&action=stop"
///
/// Results: `~/Library/Logs/Notched/spike-lockevents.txt`. No user names are written.
@MainActor
enum LockEventsProbe {
    private static var report: ProbeReport?
    private static let observers = NotificationTokens()
    private static var running = false
    private static var started = Date()

    static func handle(action: String) {
        let report = Self.report ?? ProbeReport(name: "lockevents")
        Self.report = report
        switch action {
        case "start": start(report)
        case "stop":
            observers.invalidate()
            running = false
            report.line("stopped")
        default: report.line("unknown action \(action)")
        }
    }

    private static func start(_ report: ProbeReport) {
        guard !running else { report.line("already running"); return }
        running = true
        started = Date()
        report.line("started; session now: \(sessionSummary())")
        for (index, screen) in NSScreen.screens.enumerated() {
            report.line("screen \(index): frame \(NSStringFromRect(screen.frame)), visible \(NSStringFromRect(screen.visibleFrame)), scale \(screen.backingScaleFactor)\(index == 0 ? " (primary)" : "")")
        }

        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
                     "com.apple.screensaver.didstart", "com.apple.screensaver.didstop",
                     "com.apple.sessionDidMoveOffConsole", "com.apple.sessionDidMoveOnConsole"] {
            observers.observe(Notification.Name(name), in: distributed) { record(name) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, String)] = [
            (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
            (NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (NSWorkspace.willSleepNotification, "willSleep"),
            (NSWorkspace.didWakeNotification, "didWake"),
            (NSWorkspace.sessionDidResignActiveNotification, "sessionDidResignActive"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
            (NSWorkspace.didActivateApplicationNotification, "didActivateApplication"),
        ]
        for (name, label) in workspaceEvents {
            observers.observe(name, in: workspace) { record(label) }
        }
        observers.observe(NSApplication.didChangeScreenParametersNotification) { record("didChangeScreenParameters (\(NSScreen.screens.count) screens)") }
    }

    /// Logs the event, then the lock state now, after 0.5 s and after 2 s.
    private static func record(_ event: String) {
        guard let report else { return }
        let at = String(format: "%.2f s", Date().timeIntervalSince(started))
        report.line("[\(at)] \(event): \(sessionSummary())")
        for delay in [0.5, 2.0] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard running else { return }
                report.line("    +\(delay) s after \(event): \(sessionSummary())")
            }
        }
    }

    /// The lock-related values only (never the user name).
    static func sessionSummary() -> String {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return "no session dictionary" }
        let locked = dictionary["CGSSessionScreenIsLocked"].map { "\($0)" } ?? "key absent"
        let onConsole = dictionary["kCGSSessionOnConsoleKey"].map { "\($0)" } ?? "?"
        let loginDone = dictionary["kCGSessionLoginDoneKey"].map { "\($0)" } ?? "?"
        return "locked=\(locked) onConsole=\(onConsole) loginDone=\(loginDone)"
    }
}
#endif

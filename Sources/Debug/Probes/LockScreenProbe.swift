// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import SwiftUI

/// M6 spike 6.3, Stage 2 (ADR-0031): a **plain grey label** on the lock screen
/// through the real wrapper, reducer and controller, with every safety rule on
/// and one more: it **destroys itself 60 s after appearing**, whatever happens.
/// Armed only by hand, for this app session; never at launch.
///
///     open -g "notched://debug/probe?name=lockscreen&action=status"
///     open -g "notched://debug/probe?name=lockscreen&action=arm"                 (primary display only)
///     open -g "notched://debug/probe?name=lockscreen&action=arm&secondary=1"     (also other displays)
///     open -g "notched://debug/probe?name=lockscreen&action=arm&others=1"        (even with other accounts)
///     open -g "notched://debug/probe?name=lockscreen&action=disarm"
///     open -g "notched://debug/probe?name=lockscreen&action=desktop"            (unlocked only: 5 s red label over the menu bar)
///     open -g "notched://debug/probe?name=lockscreen&action=desktop&join=0&order=front-first&level=400"
///
/// Results: `~/Library/Logs/Notched/spike-lockscreen.txt`.
@MainActor
enum LockScreenProbe {
    private static var report: ProbeReport?
    private static var controller: LockScreenController?
    private static var armedAt = Date()

    /// The running desktop test, if any.
    private static var desktopRun: (skyLight: SkyLightLockScreen, panel: LockScreenPanel)?

    static func handle(action: String, secondary: Bool, others: Bool, desktop variant: DesktopVariant = DesktopVariant()) {
        let report = Self.report ?? ProbeReport(name: "lockscreen")
        Self.report = report
        switch action {
        case "status": status(report)
        case "arm": arm(report, secondary: secondary, others: others)
        case "desktop": desktop(report, variant)
        case "disarm":
            disarm()
            report.line("disarmed")
        default: report.line("unknown action \(action)")
        }
    }

    private static func status(_ report: ProbeReport) {
        let killSwitch = LockScreenKillSwitch.isActive(arguments: ProcessInfo.processInfo.arguments, defaults: .standard)
        let others = LocalAccounts.otherLoginAccounts(in: LocalAccounts.systemEntries(), current: NSUserName())
        report.line("status: SkyLight symbols \(SkyLightLockScreen.isAvailable ? "found" : "MISSING"), kill switch \(killSwitch ? "ON" : "off"), lock state \(LockStateReader.current()), other login accounts \(others.count), shown flag \(UserDefaults.standard.bool(forKey: LockScreenController.shownFlagKey)), armed \(controller != nil)")
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = LockScreenGeometry.cardFrame(in: screen.frame).map(NSStringFromRect) ?? "none fits"
            report.line("status: screen \(index) \(NSStringFromRect(screen.frame)) → card \(frame)")
        }
    }

    private static func arm(_ report: ProbeReport, secondary: Bool, others: Bool) {
        disarm()
        let killSwitch = LockScreenKillSwitch.isActive(arguments: ProcessInfo.processInfo.arguments, defaults: .standard)
        guard !killSwitch else {
            report.line("arm refused: a kill switch is on (--no-lock-screen or \(LockScreenKillSwitch.defaultsKey))")
            return
        }
        armedAt = Date()
        let controller = LockScreenController { index in AnyView(TestLabel(screenIndex: index)) }
        controller.trace = { message in
            report.line(String(format: "[%6.2f s] ", Date().timeIntervalSince(armedAt)) + message)
        }
        controller.onTurnOff = { reason in
            report.line("TURNED OFF: \(reason). In the product the setting goes off and Settings says why. Arm again to continue.")
            Task { @MainActor in disarm() }
        }
        Self.controller = controller
        var config = LockScreenReducer.Config()
        config.enabled = true
        config.includeSecondaryScreens = secondary
        config.allowWithOtherAccounts = others
        config.otherAccountsExist = LocalAccounts.otherLoginAccountsExist()
        config.maximumLifetime = 60
        controller.apply(config)
        // The crash rule: a card left showing by a killed session turns the feature off now.
        controller.launch(previousSessionCrashed: false)
        report.line("armed: secondary displays \(secondary), other accounts exist \(config.otherAccountsExist), show anyway \(others). Lock with ⌃⌘Q.")
    }

    /// Spike round 2: how the desktop test sets up its window.
    struct DesktopVariant {
        /// Keep `.canJoinAllSpaces` (the card's setting); off tries without it.
        var joinAllSpaces = true
        /// Add to the Space before ordering front (the controller's order).
        var addBeforeOrderingFront = true
        var level = SkyLightLockScreen.levelAboveLockScreen
        /// The control run: no Space at all, so the label should stay hidden behind app windows.
        var control = false
    }

    /// **Unlocked only.** The same Space, holding a window at *desktop level*
    /// (normally behind every app window) for 5 s, below the menu bar where an
    /// app window usually is. It can only show in front of app windows if its
    /// Space really sits above them, so a screenshot shows whether macOS 27
    /// honours the Space without anyone locking the Mac. `control` runs the same
    /// window with no Space, which should stay hidden. The window never takes
    /// focus or clicks, and it always goes after 5 s.
    private static func desktop(_ report: ProbeReport, _ variant: DesktopVariant) {
        guard LockStateReader.current() == .unlocked else {
            report.line("desktop test refused: only while unlocked (lock state \(LockStateReader.current()))")
            return
        }
        guard !LockScreenKillSwitch.isActive(arguments: ProcessInfo.processInfo.arguments, defaults: .standard) else {
            report.line("desktop test refused: a kill switch is on")
            return
        }
        guard desktopRun == nil else {
            report.line("desktop test refused: one is already running")
            return
        }
        guard let skyLight = SkyLightLockScreen.make(), let screen = NSScreen.screens.first else {
            report.line("desktop test: SkyLight or a screen is missing")
            return
        }
        // Top-left, just below the menu bar, where an app window usually is.
        let frame = CGRect(x: screen.frame.minX + 150, y: screen.frame.maxY - 160, width: 360, height: 60)
        let description = variant.control
            ? "CONTROL: no Space (should be hidden behind app windows)"
            : "level \(variant.level), join all Spaces \(variant.joinAllSpaces ? "on" : "off"), \(variant.addBeforeOrderingFront ? "add then order front" : "order front then add")"
        let panel = LockScreenPanel(frame: frame, content: AnyView(DesktopLabel(text: description)))
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        if !variant.joinAllSpaces { panel.collectionBehavior.remove(.canJoinAllSpaces) }
        do {
            if variant.control {
                panel.orderFrontRegardless()
            } else if variant.addBeforeOrderingFront {
                try skyLight.createSpace(level: variant.level)
                try skyLight.add(panel)
                panel.orderFrontRegardless()
            } else {
                try skyLight.createSpace(level: variant.level)
                panel.orderFrontRegardless()
                try skyLight.add(panel)
            }
        } catch {
            report.line("desktop test failed: \(error)")
            skyLight.tearDown(closing: [panel])
            return
        }
        desktopRun = (skyLight, panel)
        let number = panel.windowNumber
        report.line("desktop test: Space \(skyLight.spaceID), \(description); desktop-level label at \(NSStringFromRect(frame)) for 5 s")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            report.line("desktop test after 0.6 s: \(skyLight.state(windowNumber: number))")
            try? await Task.sleep(for: .milliseconds(4400))
            skyLight.tearDown(closing: [panel])
            desktopRun = nil
            try? await Task.sleep(for: .milliseconds(500))
            report.line("desktop test 0.5 s after tear-down: \(skyLight.state(windowNumber: number))")
        }
    }

    private static func disarm() {
        guard let controller else { return }
        controller.apply(LockScreenReducer.Config())   // off: destroys anything and stops listening
        Self.controller = nil
    }
}

/// The desktop test's label (unlocked only, 5 s).
private struct DesktopLabel: View {
    let text: String

    var body: some View {
        VStack(spacing: 2) {
            Text("Notched desktop test")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The lock-screen test label.
private struct TestLabel: View {
    let screenIndex: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("Notched lock-screen test")
                .font(.system(size: 15, weight: .semibold))
            Text("Screen \(screenIndex). Disappears by itself within 60 s.")
                .font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif

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
///
/// Results: `~/Library/Logs/Notched/spike-lockscreen.txt`.
@MainActor
enum LockScreenProbe {
    private static var report: ProbeReport?
    private static var controller: LockScreenController?
    private static var armedAt = Date()

    static func handle(action: String, secondary: Bool, others: Bool) {
        let report = Self.report ?? ProbeReport(name: "lockscreen")
        Self.report = report
        switch action {
        case "status": status(report)
        case "arm": arm(report, secondary: secondary, others: others)
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

    private static func disarm() {
        guard let controller else { return }
        controller.apply(LockScreenReducer.Config())   // off: destroys anything and stops listening
        Self.controller = nil
    }
}

/// The only thing the spike ever shows.
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

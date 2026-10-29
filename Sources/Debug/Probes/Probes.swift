// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import os

/// Throwaway M3b research probes (spikes S1–S4). They run inside the signed,
/// installed app so macOS judges Notched's own permissions, not Terminal's.
/// Each logs to `me.rkck.Notched.probe` and is removed once its ADR is written:
///
///     log stream --level debug --predicate 'subsystem == "me.rkck.Notched.probe"'
///
/// Each probe adds its `name=` case below while its spike runs.
@MainActor
enum Probes {
    static func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = { (name: String) in items.first { $0.name == name }?.value }
        switch query("name") {
        case "sensors": SensorsProbe.setRunning(query("on") != "0")
        default: probeLog.error("Unknown probe \(query("name") ?? "-", privacy: .public)")
        }
    }
}

let probeLog = Logger(subsystem: "\(Log.root).probe", category: "probe")
#endif

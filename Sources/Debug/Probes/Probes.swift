// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import os

/// Throwaway research probes (M3b spikes S1–S4, M6 spikes 6.1–6.3). They run
/// inside the signed, installed app so macOS judges Notched's own permissions,
/// not Terminal's. Each logs to `me.rkck.Notched.probe` and is removed once its
/// ADR is written:
///
///     log stream --level debug --predicate 'subsystem == "me.rkck.Notched.probe"'
///
/// Started with `open -g "notched://debug/probe?name=<probe>&…"`. Each probe
/// adds its `name=` case below while its spike runs.
@MainActor
enum Probes {
    static func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = { (name: String) in items.first { $0.name == name }?.value }
        switch query("name") {
        case "sensors": SensorsProbe.setRunning(query("on") != "0")
        case "audiotap":
            AudioTapProbe.handle(action: query("action") ?? "list", app: query("app"), gain: query("gain").flatMap(Double.init))
        case "battery-accessory":
            AccessoryBatteryProbe.handle(action: query("action") ?? "run", seconds: query("seconds").flatMap(Double.init))
        case "lockevents":
            LockEventsProbe.handle(action: query("action") ?? "start")
        case "lockscreen":
            LockScreenProbe.handle(action: query("action") ?? "status", secondary: query("secondary") == "1", others: query("others") == "1")
        default: probeLog.error("Unknown probe \(query("name") ?? "-", privacy: .public)")
        }
    }
}

let probeLog = Logger(subsystem: "\(Log.root).probe", category: "probe")

/// A spike's findings, written to `~/Library/Logs/Notched/spike-<name>.txt` as
/// well as to the probe log, so the results go back as one plain-text file.
/// Never holds clipboard, calendar or other personal content; Bluetooth
/// addresses are left out.
@MainActor
final class ProbeReport {
    let url: URL

    init(name: String) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Notched", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("spike-\(name).txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        line("=== \(name) probe, \(Self.machine()), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    func line(_ text: String) {
        probeLog.notice("\(text, privacy: .public)")
        let stamped = "[\(Date().formatted(.iso8601))] \(text)\n"
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(stamped.utf8))
    }

    /// The Mac's model identifier, e.g. "Mac16,13".
    static func machine() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
#endif

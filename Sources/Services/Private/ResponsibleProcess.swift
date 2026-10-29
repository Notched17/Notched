// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// A private-API wrapper around libquarantine's
/// `responsibility_get_pid_responsible_for_pid`, which tells which process
/// macOS holds responsible for another (WebKit's GPU process → Safari). It's
/// the only route that can name the browser behind a web page's microphone.
///
/// If the symbol ever disappears, `isAvailable` is false, the failure is
/// logged once, and attribution falls back to the app's bundle or "An app".
/// Safe to call from any thread.
enum ResponsibleProcess {
    private typealias Lookup = @convention(c) (Int32) -> Int32

    private static let lookup: Lookup? = {
        guard let handle = dlopen("/usr/lib/system/libquarantine.dylib", RTLD_LAZY),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
            Log.privateAPI.error("The responsible-process lookup is unavailable; helper processes are named by their app bundle, or not at all")
            return nil
        }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()

    #if DEBUG
    /// Pretends the symbol is missing, to check the fallback.
    nonisolated(unsafe) static var forceUnavailable = false
    #endif

    static var isAvailable: Bool { effectiveLookup != nil }

    /// The pid macOS holds responsible for `pid`, or nil if unknown or unavailable.
    static func pid(responsibleFor pid: Int32) -> Int32? {
        guard let effectiveLookup else { return nil }
        let responsible = effectiveLookup(pid)
        return responsible > 1 ? responsible : nil
    }

    private static var effectiveLookup: Lookup? {
        #if DEBUG
        if forceUnavailable { return nil }
        #endif
        return lookup
    }
}

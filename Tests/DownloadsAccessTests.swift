// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The Downloads folder permission is a Files & Folders grant. Reading the
/// folder is what makes macOS ask, and the read blocks until the user answers,
/// so the status probe must never read it: it reports the last result of a
/// read made off the main thread.
@Suite("DownloadsAccess")
struct DownloadsAccessTests {
    private func defaults() -> UserDefaults {
        let suite = "DownloadsAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Before any read, the status is not determined, and the probe has no way to read the folder")
    func unknownBeforeAnyRead() {
        #expect(DownloadsAccess.status(defaults: defaults()) == .notDetermined)
    }

    @Test("A stored result maps to the status; anything else is not determined")
    func storedResults() {
        let defaults = defaults()
        defaults.set("granted", forKey: DownloadsAccess.defaultsKey)
        #expect(DownloadsAccess.status(defaults: defaults) == .granted)
        defaults.set("denied", forKey: DownloadsAccess.defaultsKey)
        #expect(DownloadsAccess.status(defaults: defaults) == .denied)
        defaults.set("garbage", forKey: DownloadsAccess.defaultsKey)
        #expect(DownloadsAccess.status(defaults: defaults) == .notDetermined)
    }

    @Test("A successful open is granted; EPERM and EACCES are denied; other errors say nothing")
    func classifiesOpenResults() {
        #expect(DownloadsAccess.result(forOpenError: 0) == .granted)
        #expect(DownloadsAccess.result(forOpenError: EPERM) == .denied)
        #expect(DownloadsAccess.result(forOpenError: EACCES) == .denied)
        #expect(DownloadsAccess.result(forOpenError: ENOENT) == nil)
    }

    @Test("Checking reads once through the opener and remembers the answer")
    func checkStoresResult() {
        let defaults = defaults()
        var opened: [String] = []
        let result = DownloadsAccess.check(defaults: defaults, directory: "/fake/Downloads") { path in
            opened.append(path)
            return EPERM
        }
        #expect(result == .denied)
        #expect(opened == ["/fake/Downloads"])
        #expect(DownloadsAccess.status(defaults: defaults) == .denied)
    }

    @Test("A read that fails for another reason leaves the stored answer alone")
    func unrelatedErrorKeepsAnswer() {
        let defaults = defaults()
        defaults.set("granted", forKey: DownloadsAccess.defaultsKey)
        let result = DownloadsAccess.check(defaults: defaults, directory: "/missing") { _ in ENOENT }
        #expect(result == nil)
        #expect(DownloadsAccess.status(defaults: defaults) == .granted)
    }

    @Test("Granting later in System Settings is picked up by the next read")
    func laterGrantIsSeen() {
        let defaults = defaults()
        _ = DownloadsAccess.check(defaults: defaults, directory: "/d") { _ in EPERM }
        #expect(DownloadsAccess.status(defaults: defaults) == .denied)
        _ = DownloadsAccess.check(defaults: defaults, directory: "/d") { _ in 0 }
        #expect(DownloadsAccess.status(defaults: defaults) == .granted)
    }
}

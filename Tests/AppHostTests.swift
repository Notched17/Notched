// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("App host")
struct AppHostTests {
    @Test("Tests run inside the Notched app bundle")
    func hostBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "me.rkck.Notched")
    }

    @Test("The host app knows it is running tests and skips bootstrapping")
    @MainActor
    func detectsTestHost() {
        #expect(AppDelegate.isRunningTests)
    }
}

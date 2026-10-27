// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import DynamicNotch

@Suite("App host")
struct AppHostTests {
    @Test("Tests run inside the DynamicNotch app bundle")
    func hostBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "me.rkck.DynamicNotch")
    }

    @Test("The host app knows it is running tests and skips bootstrapping")
    @MainActor
    func detectsTestHost() {
        #expect(AppDelegate.isRunningTests)
    }
}

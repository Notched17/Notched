// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@MainActor
@Suite("MediaSettings")
struct MediaSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "MediaSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The cover's glow is on unless the user turns it off")
    func glowDefaultsOn() {
        #expect(MediaSettings(defaults: freshDefaults()).showGlow)
    }

    @Test("Turning the glow off is remembered")
    func glowPersists() {
        let defaults = freshDefaults()
        let settings = MediaSettings(defaults: defaults)
        settings.showGlow = false
        #expect(MediaSettings(defaults: defaults).showGlow == false)
        settings.showGlow = true
        #expect(MediaSettings(defaults: defaults).showGlow)
    }
}

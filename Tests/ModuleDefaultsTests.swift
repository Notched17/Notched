// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

@Suite("ModuleDefaults")
struct ModuleDefaultsTests {
    private func descriptor(_ id: ModuleID, on: Bool) -> ModuleDescriptor {
        ModuleDescriptor(id: id, name: id.rawValue, symbol: "circle", summary: "", permissions: [], isDebugOnly: false, isOnByDefault: on)
    }

    @Test("A default-on module the user has never seen turns on once")
    func unseenDefaultOnModulesTurnOnOnce() {
        let result = ModuleDefaults.apply([descriptor("timers", on: true)], enabled: [], seen: [])
        #expect(result.enabled == ["timers"])
        #expect(result.seen == ["timers"])
    }

    @Test("A module the user turned off stays off")
    func userTurnedOffStaysOff() {
        let result = ModuleDefaults.apply([descriptor("timers", on: true)], enabled: [], seen: ["timers"])
        #expect(result.enabled.isEmpty)
    }

    @Test("A default-off module stays off, and modules already on stay on")
    func defaultOffStaysOff() {
        let result = ModuleDefaults.apply([descriptor("capslock", on: false), descriptor("media", on: false)],
                                          enabled: ["media"], seen: [])
        #expect(result.enabled == ["media"])
    }

    @Test("Every module becomes seen, on or off")
    func everyDescriptorBecomesSeen() {
        let result = ModuleDefaults.apply([descriptor("a", on: true), descriptor("b", on: false)], enabled: [], seen: ["old"])
        #expect(result.seen == ["a", "b", "old"])
    }
}

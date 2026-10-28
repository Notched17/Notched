// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

@Suite("ModuleLifecyclePlan")
struct ModuleLifecyclePlanTests {
    let catalog: [ModuleID] = ["a", "b", "c", "d"]

    @Test("Stops come first, newest first; then starts")
    func stopsBeforeStartsInOrder() {
        let plan = ModuleLifecyclePlan.make(running: ["a", "b", "c"], enabled: ["a", "d"], catalogOrder: catalog, blocked: [])
        #expect(plan.stop == ["c", "b"])
        #expect(plan.start == ["d"])
    }

    @Test("Modules start in catalogue order, whatever order they were enabled in")
    func startsInCatalogOrder() {
        let plan = ModuleLifecyclePlan.make(running: [], enabled: ["d", "b", "a"], catalogOrder: catalog, blocked: [])
        #expect(plan.start == ["a", "b", "d"])
        #expect(plan.stop.isEmpty)
    }

    @Test("A blocked module stops if running and never starts")
    func blockedModulesStopAndNeverStart() {
        let plan = ModuleLifecyclePlan.make(running: ["a", "b"], enabled: ["a", "b", "c"], catalogOrder: catalog, blocked: ["b", "c"])
        #expect(plan.stop == ["b"])
        #expect(plan.start.isEmpty)
    }

    @Test("Nothing to do when the running set already matches")
    func noChangeIsEmpty() {
        let plan = ModuleLifecyclePlan.make(running: ["a", "c"], enabled: ["a", "c"], catalogOrder: catalog, blocked: [])
        #expect(plan.isEmpty)
    }

    @Test("Unknown ids in the enabled set are ignored")
    func unknownIDsIgnored() {
        let plan = ModuleLifecyclePlan.make(running: [], enabled: ["zz"], catalogOrder: catalog, blocked: [])
        #expect(plan.isEmpty)
    }
}

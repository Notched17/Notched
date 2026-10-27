// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Testing
@testable import Notched

/// Records what happens to test modules.
@MainActor
final class ModuleEventLog {
    static let shared = ModuleEventLog()
    var events: [String] = []
}

@MainActor
final class AlphaTestModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "alpha", name: "Alpha", symbol: "a.circle", summary: "Test module A.", permissions: [], isDebugOnly: false
    )
    private let context: ModuleContext
    init(context: ModuleContext) {
        self.context = context
        ModuleEventLog.shared.events.append("alpha.init")
    }
    func start() {
        ModuleEventLog.shared.events.append("alpha.start")
        context.activities.post(LiveActivity(
            id: "alpha.live", moduleID: "alpha", kind: .live, title: "Alpha",
            accessibilityLabel: "alpha", presentation: .text("A")
        ))
    }
    func stop() { ModuleEventLog.shared.events.append("alpha.stop") }
}

@MainActor
final class BetaTestModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "beta", name: "Beta", symbol: "b.circle", summary: "Test module B.", permissions: [], isDebugOnly: false
    )
    init(context: ModuleContext) { ModuleEventLog.shared.events.append("beta.init") }
    func start() { ModuleEventLog.shared.events.append("beta.start") }
    func stop() { ModuleEventLog.shared.events.append("beta.stop") }
}

@Suite("ModuleRegistry", .serialized)
@MainActor
struct ModuleRegistryTests {
    let coordinator = ActivityCoordinator()

    private func makeRegistry() -> ModuleRegistry {
        ModuleEventLog.shared.events.removeAll()
        return ModuleRegistry(moduleTypes: [AlphaTestModule.self, BetaTestModule.self], coordinator: coordinator)
    }

    @Test("Descriptors are listed in registration order")
    func descriptors() {
        #expect(makeRegistry().descriptors.map(\.id) == ["alpha", "beta"])
    }

    @Test("A disabled module is never even created, so it costs nothing")
    func disabledNeverInstantiated() {
        let sut = makeRegistry()
        sut.reconcile(enabled: ["alpha"])
        #expect(ModuleEventLog.shared.events == ["alpha.init", "alpha.start"])
        #expect(sut.isRunning("alpha"))
        #expect(!sut.isRunning("beta"))
    }

    @Test("Reconciling again with the same set doesn't restart running modules")
    func idempotent() {
        let sut = makeRegistry()
        sut.reconcile(enabled: ["alpha"])
        sut.reconcile(enabled: ["alpha"])
        #expect(ModuleEventLog.shared.events == ["alpha.init", "alpha.start"])
    }

    @Test("Disabling a module stops it, releases it and removes its activities without Recent entries")
    func disableStopsAndCleansUp() {
        let sut = makeRegistry()
        sut.reconcile(enabled: ["alpha", "beta"])
        #expect(coordinator.live.map(\.id) == ["alpha.live"])
        sut.reconcile(enabled: ["beta"])
        #expect(ModuleEventLog.shared.events.suffix(1) == ["alpha.stop"])
        #expect(!sut.isRunning("alpha"))
        #expect(coordinator.live.isEmpty)
        #expect(coordinator.recent.isEmpty)
    }

    @Test("Unknown module ids in the enabled set are ignored")
    func unknownIDsIgnored() {
        let sut = makeRegistry()
        sut.reconcile(enabled: ["gamma"])
        #expect(ModuleEventLog.shared.events.isEmpty)
    }

    @Test("A module can only post activities under its own id")
    func sinkIsScoped() {
        let sink = ActivitySink(moduleID: "alpha", coordinator: coordinator)
        sink.post(LiveActivity(id: "spoof", moduleID: "beta", kind: .system, title: "Spoof", accessibilityLabel: "spoof", presentation: .text("spoof")))
        sink.show(TransientBanner(id: "spoof", moduleID: "beta", leading: IslandRegion { Text("spoof") }, accessibilityLabel: "spoof"))
        #expect(coordinator.live.isEmpty)
        #expect(coordinator.banner == nil)
    }

    @Test("A module can only end its own activities")
    func sinkEndIsScoped() {
        coordinator.post(LiveActivity(id: "beta.live", moduleID: "beta", kind: .live, title: "Beta", accessibilityLabel: "beta", presentation: .text("B")))
        ActivitySink(moduleID: "alpha", coordinator: coordinator).end("beta.live")
        #expect(coordinator.live.map(\.id) == ["beta.live"])
    }
}

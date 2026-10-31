// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Answers the eyedropper with a chosen colour (or a cancel) instead of showing the loupe.
@MainActor
final class FakeColorSampler: ColorSampling {
    var result: ColorSample?
    private(set) var requests = 0
    /// Hold the answer until `finish()`, like a user still choosing.
    var holds = false
    private var pending: (@MainActor @Sendable (ColorSample?) -> Void)?

    func sample(_ completion: @escaping @MainActor @Sendable (ColorSample?) -> Void) {
        requests += 1
        if holds { pending = completion } else { completion(result) }
    }

    func finish() {
        pending?(result)
        pending = nil
    }
}

/// The colour picker's shell and saved colours (#55).
@MainActor
@Suite("ColorPickerModule")
struct ColorPickerModuleTests {
    private func rig() -> (module: ColorPickerModule, sampler: FakeColorSampler, coordinator: ActivityCoordinator, settings: SettingsStore) {
        let coordinator = ActivityCoordinator()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "ColorPickerModuleTests.\(UUID().uuidString)")!)
        let context = ModuleContext(activities: ActivitySink(moduleID: ColorPickerModule.descriptor.id, coordinator: coordinator),
                                    scheduler: RefreshScheduler(), settings: settings, services: ModuleServices(), previousSessionCrashed: false)
        let sampler = FakeColorSampler()
        return (ColorPickerModule(context: context, sampler: sampler), sampler, coordinator, settings)
    }

    private let teal = ColorSample(color: ColorValue(red: 0, green: 128, blue: 128), outsideGamut: false)

    @Test("Starting adds the Home button and nothing else; stopping removes it")
    func startStop() {
        let (module, _, coordinator, _) = rig()
        module.start()
        #expect(coordinator.homeActions.map(\.id) == ["colorpicker"])
        #expect(coordinator.live.isEmpty)
        module.stop()
        #expect(coordinator.homeActions.isEmpty)
    }

    @Test("A pick shows the colour and saves it")
    func pickSaves() {
        let (module, sampler, _, settings) = rig()
        sampler.result = teal
        module.start()
        module.pick()
        #expect(module.model.current == teal.color)
        #expect(settings.colorPicker.recents == [teal.color])
        module.stop()
    }

    @Test("Esc in the eyedropper changes nothing")
    func cancelled() {
        let (module, sampler, _, settings) = rig()
        sampler.result = nil
        module.start()
        module.pick()
        #expect(module.model.current == nil)
        #expect(settings.colorPicker.recents.isEmpty)
        module.stop()
    }

    @Test("A second click while the loupe is up doesn't start a second one")
    func oneAtATime() {
        let (module, sampler, _, _) = rig()
        sampler.holds = true
        sampler.result = teal
        module.start()
        module.pick()
        module.pick()
        #expect(sampler.requests == 1)
        sampler.finish()
        module.pick()
        #expect(sampler.requests == 2)
        module.stop()
    }

    @Test("An answer that arrives after stopping is ignored")
    func lateAnswer() {
        let (module, sampler, _, settings) = rig()
        sampler.holds = true
        sampler.result = teal
        module.start()
        module.pick()
        module.stop()
        sampler.finish()
        #expect(module.model.current == nil)
        #expect(settings.colorPicker.recents.isEmpty)
    }

    @Test("Saved colours come back after a restart, and clearing empties them")
    func recentsPersist() {
        let (module, sampler, _, settings) = rig()
        sampler.result = teal
        module.start()
        module.pick()
        module.stop()
        module.start()
        #expect(module.model.recents == [teal.color])
        #expect(module.model.current == nil)
        module.clearRecents()
        #expect(settings.colorPicker.recents.isEmpty)
        module.stop()
    }

    @Test("Switching it on and off five times leaves nothing behind")
    func neverLeaks() {
        let (module, sampler, coordinator, _) = rig()
        sampler.result = teal
        for _ in 0..<5 {
            module.start()
            module.pick()
            module.stop()
            #expect(coordinator.homeActions.isEmpty)
            #expect(coordinator.live.isEmpty)
            #expect(module.model.copied == nil)
        }
    }

    @Test("Bad saved data is dropped, good entries kept, and the row capped")
    func settingsReadsDefensively() {
        let defaults = UserDefaults(suiteName: "ColorPickerSettingsTests.\(UUID().uuidString)")!
        defaults.set(["#FF0000", "nonsense", "#00ff00"] + (0..<30).map { String(format: "#0000%02X", $0) }, forKey: ColorPickerSettings.Key.recents)
        let settings = ColorPickerSettings(defaults: defaults)
        #expect(Array(settings.recents.prefix(2)) == [ColorValue(red: 255, green: 0, blue: 0), ColorValue(red: 0, green: 255, blue: 0)])
        #expect(settings.recents.count == ColorPickerReducer.recentLimit)
        defaults.set(42, forKey: ColorPickerSettings.Key.recents)
        #expect(ColorPickerSettings(defaults: defaults).recents.isEmpty)
    }
}

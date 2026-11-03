// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import Notched

/// Searching for a city in the island and in Settings, and the Today tab
/// capturing the keyboard while the search is open.
@Suite("CitySearch")
@MainActor
struct CitySearchTests {
    let bristol = GeocodeResult(id: 1, name: "Bristol", region: "England", country: "United Kingdom", latitude: 51.45, longitude: -2.59)
    let bristolUS = GeocodeResult(id: 2, name: "Bristol", region: "Tennessee", country: "United States", latitude: 36.6, longitude: -82.2)

    @Test("A search fills the results, and the label names region and country")
    func finds() async {
        let model = CitySearchModel { _ in [self.bristol, self.bristolUS] }
        model.query = "Bristol"
        await model.search()
        #expect(model.results.count == 2)
        #expect(model.results[0].label == "Bristol, England, United Kingdom")
        #expect(model.message == nil)
        #expect(!model.isSearching)
    }

    @Test("Too short a search does nothing and clears the results")
    func tooShort() async {
        let model = CitySearchModel { _ in [self.bristol] }
        model.query = "Br"
        await model.search()
        #expect(model.results.count == 1)
        model.query = "B"
        await model.search()
        #expect(model.results.isEmpty)
        #expect(!model.canSearch)
    }

    @Test("No match and a failure each say so")
    func messages() async {
        let none = CitySearchModel { _ in [] }
        none.query = "Zzzzz"
        await none.search()
        #expect(none.message == "No cities found.")

        struct Offline: Error {}
        let failing = CitySearchModel { _ in throw Offline() }
        failing.query = "Bristol"
        await failing.search()
        #expect(failing.message == "Couldn't search. Check your connection.")
        #expect(failing.results.isEmpty)
    }

    @Test("An answer that arrives after a newer search is thrown away")
    func staleAnswer() async {
        // The first search is slow; the second, started meanwhile, is quick.
        let model = CitySearchModel { text in
            if text == "Bris" { try await Task.sleep(for: .milliseconds(150)); return [self.bristolUS] }
            return [self.bristol]
        }
        model.query = "Bris"
        let slow = Task { await model.search() }
        try? await Task.sleep(for: .milliseconds(30))
        model.query = "Bristol"
        await model.search()
        await slow.value
        #expect(model.results == [bristol])
    }

    @Test("Reset empties the field, the results and the message")
    func reset() async {
        let model = CitySearchModel { _ in [self.bristol] }
        model.query = "Bristol"
        await model.search()
        model.reset()
        #expect(model.query.isEmpty && model.results.isEmpty && model.message == nil && !model.isSearching)
    }

    @Test("Typing pauses before searching, and typing again cancels the wait")
    func debounce() async {
        var searches: [String] = []
        let model = CitySearchModel { text in searches.append(text); return [] }
        model.query = "Bri"
        let first = Task { await model.searchAfterPause() }
        try? await Task.sleep(for: .milliseconds(100))
        model.query = "Bristol"
        first.cancel()
        await first.value
        #expect(searches.isEmpty)
        await model.searchAfterPause()
        #expect(searches == ["Bristol"])
    }

    @Test("The Today tab captures the keyboard only while a section is being typed into")
    func todayClaim() {
        let hub = TodayHub()
        var published: [IslandTab] = []
        hub.publishTabs = { published = $0 }
        hub.set(TodaySection(id: "weather", moduleID: ModuleID("weather"), slot: .header, content: IslandRegion { Text("weather") }))
        #expect(published.first?.capturesKeyboard == false)

        hub.claimKeyboard("weather", true)
        #expect(published.first?.capturesKeyboard == true)
        hub.claimKeyboard("weather", false)
        #expect(published.first?.capturesKeyboard == false)
    }

    @Test("A module that stops gives up its claim")
    func claimEndsWithModule() {
        let hub = TodayHub()
        var published: [IslandTab] = []
        hub.publishTabs = { published = $0 }
        hub.set(TodaySection(id: "weather", moduleID: ModuleID("weather"), slot: .header, content: IslandRegion { Text("weather") }))
        hub.set(TodaySection(id: "calendar", moduleID: ModuleID("calendar"), slot: .leading, content: IslandRegion { Text("calendar") }))
        hub.claimKeyboard("weather", true)
        hub.remove(moduleID: ModuleID("weather"))
        #expect(hub.keyboardClaims.isEmpty)
        #expect(published.first?.capturesKeyboard == false)
    }
}

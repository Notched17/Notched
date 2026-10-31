// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The colour picker's recents (#55).
@Suite("ColorPickerReducer")
struct ColorPickerReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 90_000)
    let red = ColorValue(red: 255, green: 0, blue: 0)
    let green = ColorValue(red: 0, green: 255, blue: 0)
    let blue = ColorValue(red: 0, green: 0, blue: 255)

    private func shade(_ index: Int) -> ColorValue {
        ColorValue(red: UInt8(index), green: 0, blue: 0)
    }

    @Test("Loading the saved row is silent and shows nothing")
    func loadIsSilent() {
        var sut = ColorPickerReducer()
        #expect(sut.reduce(.loaded([red, green]), now: t0).isEmpty)
        #expect(sut.state.recents == [red, green])
        #expect(sut.state.current == nil)
    }

    @Test("A pick shows the colour and saves it at the front")
    func pickSaves() {
        var sut = ColorPickerReducer()
        _ = sut.reduce(.loaded([red]), now: t0)
        #expect(sut.reduce(.picked(green, outsideGamut: false), now: t0) == [.persist([green, red])])
        #expect(sut.state.current == green)
    }

    @Test("Picking a colour already in the row moves it to the front once")
    func noRepeats() {
        var sut = ColorPickerReducer()
        _ = sut.reduce(.loaded([red, green, blue]), now: t0)
        #expect(sut.reduce(.picked(blue, outsideGamut: false), now: t0) == [.persist([blue, red, green])])
        #expect(sut.state.recents == [blue, red, green])
    }

    @Test("The row is capped, and the oldest colour drops off")
    func capped() {
        var sut = ColorPickerReducer()
        for index in 1...(ColorPickerReducer.recentLimit + 5) {
            _ = sut.reduce(.picked(shade(index), outsideGamut: false), now: t0)
        }
        #expect(sut.state.recents.count == ColorPickerReducer.recentLimit)
        #expect(sut.state.recents.first == shade(ColorPickerReducer.recentLimit + 5))
        #expect(!sut.state.recents.contains(shade(1)))
    }

    @Test("A saved row that is too long or has repeats is tidied on load")
    func loadTidies() {
        var sut = ColorPickerReducer()
        let long = (1...30).map(shade) + [shade(1)]
        _ = sut.reduce(.loaded(long), now: t0)
        #expect(sut.state.recents == Array(long.prefix(ColorPickerReducer.recentLimit)))
        _ = sut.reduce(.loaded([red, red, green]), now: t0)
        #expect(sut.state.recents == [red, green])
    }

    @Test("Choosing a recent colour shows it but keeps the row's order and saves nothing")
    func selectKeepsOrder() {
        var sut = ColorPickerReducer()
        _ = sut.reduce(.loaded([red, green, blue]), now: t0)
        #expect(sut.reduce(.selected(blue), now: t0).isEmpty)
        #expect(sut.state.current == blue)
        #expect(sut.state.recents == [red, green, blue])
    }

    @Test("The out-of-gamut note belongs to the pick, not to a recent colour")
    func gamutNote() {
        var sut = ColorPickerReducer()
        _ = sut.reduce(.picked(red, outsideGamut: true), now: t0)
        #expect(sut.state.outsideGamut)
        _ = sut.reduce(.selected(red), now: t0)
        #expect(!sut.state.outsideGamut)
    }

    @Test("Clearing empties and saves once, and does nothing when already empty")
    func clearing() {
        var sut = ColorPickerReducer()
        #expect(sut.reduce(.clearRecents, now: t0).isEmpty)
        _ = sut.reduce(.picked(red, outsideGamut: false), now: t0)
        #expect(sut.reduce(.clearRecents, now: t0) == [.persist([])])
        #expect(sut.state.recents.isEmpty)
        #expect(sut.reduce(.clearRecents, now: t0).isEmpty)
    }

    @Test("Random events keep the row unique, capped and newest-first")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        var sut = ColorPickerReducer()
        var lastPicked: ColorValue?
        for _ in 0..<500 {
            let color = shade(Int.random(in: 1...20, using: &generator))
            switch Int.random(in: 0..<10, using: &generator) {
            case 0: _ = sut.reduce(.clearRecents, now: t0); lastPicked = nil
            case 1: _ = sut.reduce(.selected(color), now: t0)
            default: _ = sut.reduce(.picked(color, outsideGamut: false), now: t0); lastPicked = color
            }
            let row = sut.state.recents
            #expect(row.count <= ColorPickerReducer.recentLimit)
            #expect(Set(row).count == row.count)
            if let lastPicked { #expect(row.first == lastPicked) }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The weather's look: the sky colour, where now sits in the day's range, and the rain mention.
@Suite("WeatherLook")
struct WeatherLookTests {
    private func hour(_ chance: Int?) -> HourlyWeather {
        HourlyWeather(time: Date(timeIntervalSinceReferenceDate: 0), celsius: 10, code: 3, isDay: true, precipitationChance: chance)
    }

    @Test("Clear sky is warm by day and indigo at night; rain is blue, snow icy, storms purple")
    func tints() {
        let sun = WeatherLook.tint(code: 0, isDay: true)
        let night = WeatherLook.tint(code: 0, isDay: false)
        #expect(sun.r > sun.b)
        #expect(night.b > night.r)
        #expect(WeatherLook.tint(code: 63, isDay: true).b > WeatherLook.tint(code: 63, isDay: true).r)
        #expect(WeatherLook.tint(code: 73, isDay: true).b > 0.9)
        #expect(WeatherLook.tint(code: 95, isDay: true).b > 0.9 && WeatherLook.tint(code: 95, isDay: true).g < 0.5)
        #expect(WeatherLook.tint(code: 999, isDay: true) == WeatherLook.tint(code: 3, isDay: true))
    }

    @Test("The dot sits where the temperature does between low and high")
    func range() {
        #expect(WeatherLook.rangeFraction(current: 9, low: 9, high: 18) == 0)
        #expect(WeatherLook.rangeFraction(current: 18, low: 9, high: 18) == 1)
        #expect(WeatherLook.rangeFraction(current: 13.5, low: 9, high: 18) == 0.5)
        #expect(WeatherLook.rangeFraction(current: 25, low: 9, high: 18) == 1)
        #expect(WeatherLook.rangeFraction(current: 2, low: 9, high: 18) == 0)
        #expect(WeatherLook.rangeFraction(current: 10, low: 10, high: 10) == 0.5)
    }

    @Test("Rain is mentioned at 20 % or more, with the best chance")
    func rain() {
        #expect(WeatherLook.rainChance(in: [hour(nil), hour(10), hour(19)]) == nil)
        #expect(WeatherLook.rainChance(in: [hour(5), hour(20)]) == 20)
        #expect(WeatherLook.rainChance(in: [hour(30), hour(70), hour(40)]) == 70)
        #expect(WeatherLook.rainChance(in: []) == nil)
    }
}

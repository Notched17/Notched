// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// The visualiser's bar motion: alive, not random, and the same every time (#12).
@Suite("VisualizerKeyframes")
struct VisualizerKeyframesTests {
    @Test func sameSeedSameLevels() {
        #expect(VisualizerKeyframes.levels(bar: 2, count: 40) == VisualizerKeyframes.levels(bar: 2, count: 40))
    }

    @Test func barsDiffer() {
        let first = VisualizerKeyframes.levels(bar: 0, count: 40)
        let second = VisualizerKeyframes.levels(bar: 1, count: 40)
        let different = zip(first, second).filter { abs($0 - $1) > 0.05 }.count
        #expect(different >= 20)
    }

    @Test func withinRange() {
        for bar in 0..<5 {
            for level in VisualizerKeyframes.levels(bar: bar, count: 40) {
                #expect(level >= VisualizerKeyframes.minimumLevel && level <= 1)
            }
        }
    }

    @Test func loopIsSeamless() {
        let levels = VisualizerKeyframes.levels(bar: 3, count: 40)
        #expect(levels.count == 41)
        #expect(levels.first == levels.last)
    }

    @Test func periodsDifferPerBar() {
        let periods = (0..<5).map { VisualizerKeyframes.period(bar: $0) }
        #expect(Set(periods).count == 5)
        #expect(periods.allSatisfy { (2.0...3.6).contains($0) })
    }
}

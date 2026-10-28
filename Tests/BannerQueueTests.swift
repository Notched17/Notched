// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Banners waiting for the island (ADR-0012).
@Suite("BannerQueue")
struct BannerQueueTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 30_000)

    private func drain(_ queue: inout BannerQueue<String>, at date: Date) -> [String] {
        var shown: [String] = []
        while let next = queue.next(at: date) { shown.append(next.payload) }
        return shown
    }

    @Test("Waiting banners show by priority, then in arrival order")
    func priorityThenArrival() {
        var sut = BannerQueue<String>()
        sut.enqueue(id: "a", priority: .normal, payload: "a", at: t0)
        sut.enqueue(id: "b", priority: .high, payload: "b", at: t0 + 1)
        sut.enqueue(id: "c", priority: .normal, payload: "c", at: t0 + 2)
        #expect(drain(&sut, at: t0 + 3) == ["b", "a", "c"])
        #expect(sut.isEmpty)
    }

    @Test("A banner with the same id replaces its queued copy")
    func sameIdReplaces() {
        var sut = BannerQueue<String>()
        sut.enqueue(id: "network", priority: .normal, payload: "offline", at: t0)
        sut.enqueue(id: "capslock", priority: .normal, payload: "caps on", at: t0 + 1)
        sut.enqueue(id: "network", priority: .normal, payload: "wifi", at: t0 + 2)
        #expect(sut.count == 2)
        #expect(drain(&sut, at: t0 + 3) == ["caps on", "wifi"])
    }

    @Test("Waiting too long drops a banner: 5 s, or 30 s for high priority")
    func expiredDropped() {
        var sut = BannerQueue<String>()
        sut.enqueue(id: "a", priority: .normal, payload: "a", at: t0)
        sut.enqueue(id: "b", priority: .high, payload: "b", at: t0)
        #expect(drain(&sut, at: t0 + 6) == ["b"])

        sut.enqueue(id: "c", priority: .high, payload: "c", at: t0)
        #expect(sut.next(at: t0 + 31) == nil)
        #expect(BannerQueue<String>.maxWait(.low) == 5)
    }

    @Test("Over capacity, the oldest of the least important goes")
    func capacityDropsLowestOldest() {
        var sut = BannerQueue<String>()
        for (index, id) in ["n1", "n2", "n3"].enumerated() {
            sut.enqueue(id: id, priority: .normal, payload: id, at: t0 + Double(index))
        }
        sut.enqueue(id: "h", priority: .high, payload: "h", at: t0 + 3)
        #expect(sut.count == BannerQueue<String>.capacity)
        sut.enqueue(id: "l", priority: .low, payload: "l", at: t0 + 4)
        #expect(drain(&sut, at: t0 + 4) == ["h", "n2", "n3"])
    }

    @Test("A module's banners can be removed (the module was turned off)")
    func removeAll() {
        var sut = BannerQueue<String>()
        sut.enqueue(id: "battery.power", priority: .normal, payload: "battery", at: t0)
        sut.enqueue(id: "network", priority: .normal, payload: "network", at: t0)
        sut.removeAll { id, _ in id.hasPrefix("battery") }
        #expect(drain(&sut, at: t0) == ["network"])
    }
}

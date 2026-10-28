// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Wi-Fi, Ethernet and offline banners, without spam (#29).
@Suite("NetworkReducer")
struct NetworkReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 70_000)
    let home = NetworkState.wifi(name: "Home")

    private func seeded(_ state: NetworkState) -> NetworkReducer {
        var sut = NetworkReducer()
        _ = sut.reduce(.path(state), now: t0 - 100)
        return sut
    }

    @Test("The path at start is silent")
    func firstPathIsSilent() {
        var sut = NetworkReducer()
        #expect(sut.reduce(.path(home), now: t0).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 5).isEmpty)
    }

    @Test("Going offline is announced once it has lasted two seconds")
    func offlineAfterSettle() {
        var sut = seeded(home)
        #expect(sut.reduce(.path(.offline), now: t0) == [.wake(t0 + 2)])
        #expect(sut.reduce(.tick, now: t0 + 2) == [.banner(.offline)])
    }

    @Test("A drop shorter than two seconds says nothing")
    func briefDropIsSilent() {
        var sut = seeded(home)
        _ = sut.reduce(.path(.offline), now: t0)
        #expect(sut.reduce(.path(home), now: t0 + 1).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 2).isEmpty)
    }

    @Test("Flapping for a minute shows at most three banners a minute, ending on the real state")
    func flappingIsRateLimitedToFinalState() {
        var sut = seeded(home)
        var banners: [(Date, NetworkState)] = []
        var wake: Date?
        func collect(_ effects: [NetworkReducer.Effect], at date: Date) {
            for effect in effects {
                switch effect {
                case .banner(let state): banners.append((date, state))
                case .wake(let next): wake = next
                }
            }
        }
        func runTicks(until date: Date) {
            while let due = wake, due <= date {
                wake = nil
                collect(sut.reduce(.tick, now: due), at: due)
            }
        }
        // Offline and back every 3 s for a minute, each state outlasting the settle time.
        for step in 0..<20 {
            let date = t0 + Double(step) * 3
            runTicks(until: date)
            collect(sut.reduce(.path(step.isMultiple(of: 2) ? .offline : home), now: date), at: date)
        }
        runTicks(until: t0 + 600)
        for (date, _) in banners {
            #expect(banners.filter { $0.0 >= date && $0.0 < date + 60 }.count <= 3)
        }
        #expect(banners.last?.1 == home)
    }

    @Test("Switching from Wi-Fi to Ethernet is announced")
    func wifiToEthernet() {
        var sut = seeded(home)
        _ = sut.reduce(.path(.ethernet), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 2) == [.banner(.ethernet)])
    }

    @Test("Joining another Wi-Fi network is announced with its name")
    func joiningAnotherNetwork() {
        var sut = seeded(home)
        _ = sut.reduce(.path(.wifi(name: "Café")), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 2) == [.banner(.wifi(name: "Café"))])
    }

    @Test("Learning the current network's name (Location just allowed) is silent")
    func learningTheNameIsSilent() {
        var sut = seeded(.wifi(name: nil))
        #expect(sut.reduce(.path(home), now: t0).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 2).isEmpty)
        _ = sut.reduce(.path(.offline), now: t0 + 10)
        #expect(sut.reduce(.tick, now: t0 + 12) == [.banner(.offline)])
    }

    @Test("Losing the name (Location turned off) is silent too")
    func losingTheNameIsSilent() {
        var sut = seeded(home)
        #expect(sut.reduce(.path(.wifi(name: nil)), now: t0).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 2).isEmpty)
    }

    @Test("Connecting through an iPhone's hotspot is announced as Personal Hotspot")
    func hotspot() {
        var sut = seeded(.offline)
        _ = sut.reduce(.path(.hotspot), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 2) == [.banner(.hotspot)])
    }
}

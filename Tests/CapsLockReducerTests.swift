// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// The Caps Lock banner (#25).
@Suite("CapsLockReducer")
struct CapsLockReducerTests {
    @Test("The state at start is silent")
    func seedIsSilent() {
        var sut = CapsLockReducer()
        #expect(sut.reduce(capsLock: true).isEmpty)
        #expect(sut.isOn == true)
    }

    @Test("Each toggle is announced")
    func toggleAnnounces() {
        var sut = CapsLockReducer()
        sut.seed(false)
        #expect(sut.reduce(capsLock: true) == [.banner(isOn: true)])
        #expect(sut.reduce(capsLock: false) == [.banner(isOn: false)])
    }

    @Test("Other modifier keys (Shift, Command) report the same Caps Lock state and say nothing")
    func sameStateIgnored() {
        var sut = CapsLockReducer()
        sut.seed(false)
        #expect(sut.reduce(capsLock: false).isEmpty)
        _ = sut.reduce(capsLock: true)
        #expect(sut.reduce(capsLock: true).isEmpty)
    }
}

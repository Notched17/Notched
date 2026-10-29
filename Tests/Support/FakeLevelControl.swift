// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import Notched

/// A scriptable output: what it reads, whether it can be set, and what the
/// read-back looks like after a set. Records every call.
final class FakeLevelControl: LevelControl, MuteControl, @unchecked Sendable {
    var target: UInt32? = 7
    var settable = true
    /// What `level(_:)` reads; nil is a failed read.
    var levelValue: Double? = 0.5
    var setSucceeds = true
    /// The value the device reports after a set: (requested, previous) -> new.
    var afterSet: (Double, Double?) -> Double? = { requested, _ in requested }
    var muted: Bool? = false
    var muteSetSucceeds = true
    var muteApplies = true
    /// Runs at the start of every `setLevel`, e.g. to call back into the engine.
    var onSet: (() -> Void)?

    private(set) var setCalls: [Double] = []
    private(set) var muteCalls: [Bool] = []
    private(set) var readCount = 0

    func currentTarget() -> UInt32? { target }
    func isSettable(_ id: UInt32) -> Bool { settable }
    func level(_ id: UInt32) -> Double? {
        readCount += 1
        return levelValue
    }
    func setLevel(_ value: Double, on id: UInt32) -> Bool {
        onSet?()
        setCalls.append(value)
        guard setSucceeds else { return false }
        levelValue = afterSet(value, levelValue)
        return true
    }
    func isMuted(_ id: UInt32) -> Bool? { muted }
    func setMuted(_ newValue: Bool, on id: UInt32) -> Bool {
        muteCalls.append(newValue)
        guard muteSetSucceeds else { return false }
        if muteApplies { muted = newValue }
        return true
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit.pwr_mgt

/// Holds at most one power assertion (#38). A protocol so tests can count
/// acquires and releases without touching the real power manager.
@MainActor
protocol PowerAssertionClient: AnyObject {
    var isHeld: Bool { get }
    /// False when macOS refused it.
    func acquire(reason: String) -> Bool
    func release()
}

/// Keeps the display (and so the Mac) from idle sleep with
/// `PreventUserIdleDisplaySleep`, the assertion `caffeinate -d` uses. It
/// shows in `pmset -g assertions` under Notched. A crash releases it in
/// the kernel.
@MainActor
final class IOPMPowerAssertionClient: PowerAssertionClient {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHeld = false
    private let log = Log.module("keepawake")

    func acquire(reason: String) -> Bool {
        guard !isHeld else { return true }
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        guard status == kIOReturnSuccess else {
            log.error("macOS refused the keep-awake assertion: \(status)")
            return false
        }
        assertionID = id
        isHeld = true
        return true
    }

    func release() {
        guard isHeld else { return }
        let status = IOPMAssertionRelease(assertionID)
        if status != kIOReturnSuccess { log.error("Couldn't release the keep-awake assertion: \(status)") }
        isHeld = false
        assertionID = 0
    }

    isolated deinit {
        release()
    }
}

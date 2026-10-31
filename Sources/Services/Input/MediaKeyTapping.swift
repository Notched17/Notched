// SPDX-License-Identifier: GPL-3.0-or-later

/// The few things the HUD module asks of the event tap, so tests can stand
/// in a fake that records them.
protocol MediaKeyTapping: AnyObject, Sendable {
    /// False, with nothing left running, if the tap can't be made.
    func install() -> Bool
    /// Pauses or resumes delivery without removing the tap.
    func setEnabled(_ enabled: Bool)
    /// Disables the tap at once, then tears it down. Safe to call twice.
    func remove()
    var isInstalled: Bool { get }
}

extension MediaKeyTap: MediaKeyTapping {}

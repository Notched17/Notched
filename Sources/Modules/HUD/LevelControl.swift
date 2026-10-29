// SPDX-License-Identifier: GPL-3.0-or-later

/// What the HUD shows a level for.
enum HUDKind: Sendable, Hashable {
    case volume, brightness
}

/// What one key asks for.
enum HUDStep: Equatable, Sendable {
    /// Move a level by `delta` (negative to lower it).
    case level(HUDKind, delta: Double)
    case toggleMute
}

/// The logical target of a change whose read-back hadn't caught up (a
/// Bluetooth output taking a moment to report). The next step builds on it,
/// and applying it again can't add a second step.
struct PendingTarget: Equatable, Sendable {
    let kind: HUDKind
    /// The output device or display it was set on.
    let targetID: UInt32
    let level: Double
}

/// What the HUD shows after a key.
struct HUDReading: Equatable, Sendable {
    let kind: HUDKind
    let targetID: UInt32
    let level: Double
    let isMuted: Bool
    /// The key pushed against the top or bottom; there was nothing left to change.
    let atLimit: Bool
}

/// What applying one key did. Anything but `changed`, `atLimit` and
/// `unconfirmed` means macOS should handle the key.
enum ApplyOutcome: Equatable, Sendable {
    case changed(HUDReading)
    /// At 100% going up or 0% going down, on an output that was read and can be set.
    case atLimit(HUDReading)
    /// The set was accepted but the read-back hasn't moved yet.
    case unconfirmed(HUDReading, PendingTarget)
    case notSettable(HUDKind)
    case failed(HUDKind)
    /// This output is in pass-through after two unconfirmed presses.
    case skipped(HUDKind)
}

/// A level that can be read and set: the default output's volume, or the
/// built-in display's brightness. Called on the tap thread, so it never
/// touches the main actor.
protocol LevelControl: Sendable {
    /// The default output device, or the display to adjust.
    func currentTarget() -> UInt32?
    func isSettable(_ id: UInt32) -> Bool
    /// 0...1.
    func level(_ id: UInt32) -> Double?
    func setLevel(_ value: Double, on id: UInt32) -> Bool
}

protocol MuteControl: Sendable {
    func isMuted(_ id: UInt32) -> Bool?
    func setMuted(_ muted: Bool, on id: UInt32) -> Bool
}

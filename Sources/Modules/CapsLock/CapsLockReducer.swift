// SPDX-License-Identifier: GPL-3.0-or-later

/// The Caps Lock banner (#25). Pure. Every modifier key sends a
/// flags-changed event, so only a real change of the Caps Lock state is
/// announced; the state at start is silent. Rapid toggles reuse one banner
/// id, so the island shows one banner with the latest state.
struct CapsLockReducer: Sendable {
    enum Effect: Equatable, Sendable {
        case banner(isOn: Bool)
    }

    private(set) var isOn: Bool?

    mutating func seed(_ isOn: Bool) {
        self.isOn = isOn
    }

    mutating func reduce(capsLock: Bool) -> [Effect] {
        guard let isOn else {
            seed(capsLock)
            return []
        }
        guard capsLock != isOn else { return [] }
        self.isOn = capsLock
        return [.banner(isOn: capsLock)]
    }
}

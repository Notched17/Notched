// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the Calls module tells the Camera & Microphone module, so a call is
/// one item on the island and not a call plus a microphone dot beside it.
/// Keyed by app identity (`InputUser.identity`), not pid: a call's helper
/// processes come and go, and a pid can be reused.
struct CallClaims: Equatable, Sendable {
    /// Apps in a call. The microphone indicator leaves these out; any other
    /// app using the microphone still shows.
    var identities: Set<String> = []
    /// A call is on screen, so the camera indicator is merged into it.
    var isCallActive = false
}

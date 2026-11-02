// SPDX-License-Identifier: GPL-3.0-or-later

import Observation

/// Where the Now Playing module puts what it shows, so another module (the
/// lock-screen card) can mirror it without a second `NowPlayingService`.
/// `model` is set while the Now Playing module runs and nil otherwise.
@MainActor
@Observable
final class NowPlayingShelf {
    private(set) var model: MediaModel?

    func publish(_ model: MediaModel) { self.model = model }
    func withdraw() { model = nil }
}

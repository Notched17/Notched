// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Fixes from the M2 final review.
@Suite("MediaReviewFixes")
struct MediaReviewFixTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    private func episode(elapsed: TimeInterval, duration: TimeInterval = 3600, skips: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: "Episode", artist: nil, album: nil,
            timeline: PlaybackTimeline(elapsed: elapsed, timestamp: t0, rate: 1, duration: duration),
            isPlaying: true, sourceBundleID: "com.google.Chrome", supportsSkip15: skips
        )
    }

    // ±15 s on long content from a source without native skip (YouTube) must
    // seek, which every scrubbable source supports, or nothing would happen.
    @Test func skipUsesNativeCommandWhenSupported() {
        #expect(MediaControlsRow.skipCommand(forward: true, snapshot: episode(elapsed: 100, skips: true), at: t0) == .skipForward15)
        #expect(MediaControlsRow.skipCommand(forward: false, snapshot: episode(elapsed: 100, skips: true), at: t0) == .skipBackward15)
    }

    @Test func skipSeeksWhenNotSupported() {
        #expect(MediaControlsRow.skipCommand(forward: true, snapshot: episode(elapsed: 100, skips: false), at: t0) == .seek(115))
        #expect(MediaControlsRow.skipCommand(forward: false, snapshot: episode(elapsed: 10, skips: false), at: t0) == .seek(0))
        #expect(MediaControlsRow.skipCommand(forward: true, snapshot: episode(elapsed: 3590, skips: false), at: t0) == .seek(3600))
    }

    // Automation is granted per app when first used; asking up front only
    // opens an empty System Settings list.
    @Test func automationIsNeverRequestedUpFront() {
        let media = ModuleDescriptor(id: "media", name: "Now Playing", symbol: "music.note", summary: "",
                                     permissions: [.automation], isDebugOnly: false)
        let calendar = ModuleDescriptor(id: "calendar", name: "Calendar", symbol: "calendar", summary: "",
                                        permissions: [.automation, .calendars], isDebugOnly: false)
        #expect(Permission.requestedUpFront(by: [media]).isEmpty)
        #expect(Permission.requestedUpFront(by: [media, calendar]) == [.calendars])
    }
}

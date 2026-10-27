// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Music's and Spotify's own playback notifications (#10 fallback).
@Suite("PlayerNotificationInfo")
struct PlayerNotificationInfoTests {
    @Test func musicUsesTotalTimeInMilliseconds() throws {
        let info = try #require(PlayerNotificationInfo(player: .music, userInfo: [
            "Name": "Golden Hour", "Artist": "JVKE", "Album": "this is what ____ feels like",
            "Player State": "Playing", "Total Time": 209_000,
        ]))
        #expect(info.state == .playing)
        #expect(info.title == "Golden Hour")
        #expect(info.duration == 209)
        #expect(info.position == nil)
    }

    @Test func spotifyIncludesPosition() throws {
        let info = try #require(PlayerNotificationInfo(player: .spotify, userInfo: [
            "Name": "The Box", "Artist": "Roddy Ricch", "Album": "Please Excuse Me for Being Antisocial",
            "Player State": "Paused", "Duration": 196_652, "Playback Position": 114.8,
        ]))
        #expect(info.state == .paused)
        #expect(info.duration == 196.652)
        #expect(info.position == 114.8)
    }

    @Test func stoppedHasNoTrack() throws {
        let info = try #require(PlayerNotificationInfo(player: .music, userInfo: ["Player State": "Stopped"]))
        #expect(info.state == .stopped)
        #expect(info.title == nil)
    }

    @Test func unknownStateIsIgnored() {
        #expect(PlayerNotificationInfo(player: .music, userInfo: ["Player State": "Rewinding"]) == nil)
        #expect(PlayerNotificationInfo(player: .music, userInfo: nil) == nil)
    }
}

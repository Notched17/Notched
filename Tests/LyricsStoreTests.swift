// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The lyrics privacy rule (ADR-0009) and the disk cache (#13).
@Suite("LyricsStore")
@MainActor
struct LyricsStoreTests {
    /// Counts lookups instead of going to the network.
    actor SpyFetcher: LyricsFetching {
        private(set) var queries: [LyricsQuery] = []
        let result: LyricsFetchResult

        init(_ result: LyricsFetchResult) { self.result = result }

        func fetch(_ query: LyricsQuery) async throws -> LyricsFetchResult {
            queries.append(query)
            return result
        }
    }

    let directory = FileManager.default.temporaryDirectory.appending(path: "LyricsStoreTests-\(UUID().uuidString)")
    let song = NowPlayingSnapshot(
        title: "The Box", artist: "Roddy Ricch", album: "Please Excuse Me for Being Antisocial",
        timeline: PlaybackTimeline(elapsed: 0, timestamp: Date(), rate: 1, duration: 196.65),
        isPlaying: true, sourceBundleID: "com.spotify.client"
    )

    @Test func disabledNeverFetches() async {
        let spy = SpyFetcher(.synced("[00:01.00]Hi"))
        let store = LyricsStore(fetcher: spy, cacheDirectory: directory)
        store.isEnabled = false
        #expect(await store.lyrics(for: song) == nil)
        #expect(await spy.queries.isEmpty)
    }

    @Test func fetchesWithTrackDetails() async throws {
        let spy = SpyFetcher(.synced("[00:01.00]Hi"))
        let store = LyricsStore(fetcher: spy, cacheDirectory: directory)
        store.isEnabled = true
        let lyrics = await store.lyrics(for: song)
        #expect(lyrics?.lines.first?.text == "Hi")
        let query = try #require(await spy.queries.first)
        #expect(query == LyricsQuery(title: "The Box", artist: "Roddy Ricch", album: "Please Excuse Me for Being Antisocial", duration: 197))
    }

    @Test func cachesHit() async {
        let spy = SpyFetcher(.synced("[00:01.00]Hi"))
        let store = LyricsStore(fetcher: spy, cacheDirectory: directory)
        store.isEnabled = true
        _ = await store.lyrics(for: song)
        _ = await store.lyrics(for: song)
        // A new store (e.g. after a relaunch) reads the disk cache.
        let relaunched = LyricsStore(fetcher: spy, cacheDirectory: directory)
        relaunched.isEnabled = true
        #expect(await relaunched.lyrics(for: song)?.lines.count == 1)
        #expect(await spy.queries.count == 1)
    }

    @Test func cachesNotFound() async {
        let spy = SpyFetcher(.notFound)
        let store = LyricsStore(fetcher: spy, cacheDirectory: directory)
        store.isEnabled = true
        #expect(await store.lyrics(for: song) == nil)
        #expect(await store.lyrics(for: song) == nil)
        #expect(await spy.queries.count == 1)
    }

    @Test func keyNormalises() {
        let messy = LyricsCacheKey(title: "  The Box ", artist: "RODDY  Ricch", album: "Please Excuse Me", duration: 196.65)
        let clean = LyricsCacheKey(title: "the box", artist: "roddy ricch", album: "please excuse me", duration: 197.2)
        #expect(messy == clean)
        #expect(messy.fileName == clean.fileName)
        #expect(messy.fileName.hasSuffix(".json"))
        #expect(LyricsCacheKey(title: "The Box", artist: "Roddy Ricch", album: "", duration: 196) != clean)
    }
}

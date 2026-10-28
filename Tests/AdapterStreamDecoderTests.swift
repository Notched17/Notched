// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Decodes `mediaremote-adapter stream --micros` output (#10). The fixture is
/// a real line captured on macOS 27.2.
@Suite("AdapterStreamDecoder")
struct AdapterStreamDecoderTests {
    static let full = #"{"type":"data","diff":false,"payload":{"album":"Please Excuse Me for Being Antisocial","title":"The Box","artist":"Roddy Ricch","bundleIdentifier":"com.spotify.client","processIdentifier":18294,"durationMicros":196652000,"elapsedTimeMicros":114802000,"timestampEpochMicros":1793060214116265,"contentItemIdentifier":"B510E3C0","playing":false,"playbackRate":0}}"#

    private func decodeAll(_ lines: String...) -> [NowPlayingSnapshot?] {
        var decoder = AdapterStreamDecoder()
        return lines.flatMap { decoder.feed(Data(($0 + "\n").utf8)) }
    }

    @Test func fullPayloadDecodes() throws {
        let events = decodeAll(Self.full)
        #expect(events.count == 1)
        let snapshot = try #require(events.first ?? nil)
        #expect(snapshot.title == "The Box")
        #expect(snapshot.artist == "Roddy Ricch")
        #expect(snapshot.album == "Please Excuse Me for Being Antisocial")
        #expect(snapshot.sourceBundleID == "com.spotify.client")
        #expect(snapshot.isPlaying == false)
        #expect(abs((snapshot.timeline.duration ?? 0) - 196.652) < 0.0001)
        #expect(abs(snapshot.timeline.elapsed - 114.802) < 0.0001)
        #expect(snapshot.timeline.rate == 0)
        #expect(abs(snapshot.timeline.timestamp.timeIntervalSince1970 - 1_793_060_214.116265) < 0.001)
    }

    @Test func diffUpdatesPlaying() throws {
        let events = decodeAll(Self.full, #"{"type":"data","diff":true,"payload":{"playing":true,"playbackRate":1}}"#)
        #expect(events.count == 2)
        let snapshot = try #require(events.last ?? nil)
        #expect(snapshot.isPlaying)
        #expect(snapshot.timeline.rate == 1)
        #expect(snapshot.title == "The Box")
    }

    @Test func playingWithoutRateMovesAtNormalSpeed() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Song","bundleIdentifier":"com.apple.Music","playing":true,"elapsedTimeMicros":1000000,"timestampEpochMicros":1793060214000000}}"#
        let snapshot = try #require(decodeAll(line).first ?? nil)
        #expect(snapshot.timeline.rate == 1)
        #expect(snapshot.timeline.duration == nil)
    }

    @Test func nullRemovesKey() throws {
        let events = decodeAll(Self.full, #"{"type":"data","diff":true,"payload":{"artist":null}}"#)
        let snapshot = try #require(events.last ?? nil)
        #expect(snapshot.artist == nil)
    }

    @Test func fullPayloadReplacesState() throws {
        let replacement = #"{"type":"data","diff":false,"payload":{"title":"Other","bundleIdentifier":"com.apple.Music","playing":true}}"#
        let snapshot = try #require(decodeAll(Self.full, replacement).last ?? nil)
        #expect(snapshot.title == "Other")
        #expect(snapshot.artist == nil)
        #expect(snapshot.album == nil)
    }

    @Test func partialLinesAreBuffered() {
        var decoder = AdapterStreamDecoder()
        let data = Data((Self.full + "\n").utf8)
        let split = data.count / 2
        #expect(decoder.feed(data.prefix(split)).isEmpty)
        #expect(decoder.feed(data.suffix(from: split)).count == 1)
    }

    @Test func severalLinesInOneRead() {
        var decoder = AdapterStreamDecoder()
        let chunk = Self.full + "\n" + #"{"type":"data","diff":true,"payload":{"playing":true}}"# + "\n"
        #expect(decoder.feed(Data(chunk.utf8)).count == 2)
    }

    @Test func malformedLineIsSkipped() {
        let events = decodeAll("{oops", Self.full)
        #expect(events.count == 1)
        #expect(events.first??.title == "The Box")
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        let events = decodeAll(Self.full, #"{"type":"data","diff":false,"payload":{}}"#)
        #expect(events.count == 2)
        #expect(events.last! == nil)
    }

    @Test func missingTitleMeansNothingPlaying() {
        let events = decodeAll(Self.full, #"{"type":"data","diff":true,"payload":{"title":null}}"#)
        #expect(events.last! == nil)
    }

    @Test func parentBundleWins() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Video","bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":true}}"#
        let snapshot = try #require(decodeAll(line).first ?? nil)
        #expect(snapshot.sourceBundleID == "com.apple.Safari")
    }

    @Test func artworkDecodes() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
        let line = #"{"type":"data","diff":false,"payload":{"title":"Song","bundleIdentifier":"com.apple.Music","playing":true,"artworkMimeType":"image/jpeg","artworkData":""# + bytes.base64EncodedString() + #""}}"#
        let snapshot = try #require(decodeAll(line).first ?? nil)
        #expect(snapshot.artwork == bytes)
    }

    @Test func skipAndLikeCapabilities() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Episode","bundleIdentifier":"com.apple.podcasts","playing":true,"supportsFastForward15Seconds":true,"supportsRewind15Seconds":true,"supportsIsLiked":true,"isLiked":true}}"#
        let snapshot = try #require(decodeAll(line).first ?? nil)
        #expect(snapshot.supportsSkip15)
        #expect(snapshot.liked == true)
    }
}

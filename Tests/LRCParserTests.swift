// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Synced lyrics in LRC format, as LRCLIB returns them (#13).
@Suite("LRCParser")
struct LRCParserTests {
    @Test func parsesTimestamps() {
        let lyrics = LRCParser.parse("[01:02.50]Hi there\n[01:05.00]Second")
        #expect(lyrics.lines == [.init(time: 62.5, text: "Hi there"), .init(time: 65, text: "Second")])
    }

    @Test func acceptsMillisecondsAndNoFraction() {
        let lyrics = LRCParser.parse("[00:01.234]A\n[00:02]B")
        #expect(lyrics.lines.map(\.time) == [1.234, 2])
    }

    @Test func multipleStampsOneLine() {
        let lyrics = LRCParser.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse")
        #expect(lyrics.lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
        #expect(lyrics.lines.map(\.time) == [10, 20, 30])
    }

    @Test func ignoresMetadataTags() {
        let lyrics = LRCParser.parse("[ar:Roddy Ricch]\n[ti:The Box]\n[length:03:16]\n[00:01.00]Line")
        #expect(lyrics.lines == [.init(time: 1, text: "Line")])
    }

    @Test func appliesOffset() {
        // A positive offset shows lyrics earlier (LRC convention).
        let lyrics = LRCParser.parse("[offset:+500]\n[00:10.00]Line")
        #expect(lyrics.lines.first?.time == 9.5)
    }

    @Test func sortsLines() {
        let lyrics = LRCParser.parse("[00:20.00]B\n[00:10.00]A")
        #expect(lyrics.lines.map(\.text) == ["A", "B"])
    }

    @Test func blankLinesKeptAsBreaks() {
        let lyrics = LRCParser.parse("[00:10.00]Words\n[00:15.00]\n[00:20.00]More")
        #expect(lyrics.lines.map(\.text) == ["Words", "", "More"])
    }

    @Test func trimsTextAndSkipsGarbage() {
        let lyrics = LRCParser.parse("not a lyric\n[00:10.00]  Spaced  \r\n[xx:yy]bad")
        #expect(lyrics.lines == [.init(time: 10, text: "Spaced")])
    }

    @Test func lineIndexBinarySearch() {
        let lyrics = LRCParser.parse("[00:10.00]A\n[00:20.00]B\n[00:30.00]C")
        #expect(lyrics.lineIndex(at: 5) == nil)
        #expect(lyrics.lineIndex(at: 10) == 0)
        #expect(lyrics.lineIndex(at: 19.99) == 0)
        #expect(lyrics.lineIndex(at: 20) == 1)
        #expect(lyrics.lineIndex(at: 400) == 2)
        #expect(SyncedLyrics(lines: []).lineIndex(at: 3) == nil)
    }
}

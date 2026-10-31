// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("DownloadNaming")
struct DownloadNamingTests {
    @Test("Each browser's partial file maps to the final name")
    func conventions() {
        #expect(DownloadNaming.partial("archive.zip.crdownload")?.finalName == "archive.zip")
        #expect(DownloadNaming.partial("archive.zip.download")?.finalName == "archive.zip")
        #expect(DownloadNaming.partial("archive.zip.part")?.finalName == "archive.zip")
        #expect(DownloadNaming.partial("archive.zip.opdownload")?.finalName == "archive.zip")
        #expect(DownloadNaming.partial("ARCHIVE.ZIP.CRDOWNLOAD")?.finalName == "ARCHIVE.ZIP")
    }

    @Test("Chrome's Unconfirmed name is a download whose name isn't known yet")
    func unconfirmed() {
        let partial = DownloadNaming.partial("Unconfirmed 481516.crdownload")
        #expect(partial?.isUnconfirmed == true)
        #expect(partial?.displayName == "Download")
        #expect(DownloadNaming.partial("report.pdf.crdownload")?.isUnconfirmed == false)
    }

    @Test("A duplicate keeps its number, so two downloads are two")
    func duplicates() {
        #expect(DownloadNaming.partial("photo (1).jpg.crdownload")?.finalName == "photo (1).jpg")
    }

    @Test("Ordinary files, hidden files and a bare extension aren't partial downloads")
    func notPartial() {
        #expect(DownloadNaming.partial("archive.zip") == nil)
        #expect(DownloadNaming.partial(".DS_Store") == nil)
        #expect(DownloadNaming.partial(".crdownload") == nil)
        #expect(DownloadNaming.partial("download") == nil)
        #expect(DownloadNaming.partial("notes.partial.txt") == nil)
    }

    @Test("The progress attribute is read with either decimal separator, and rejects nonsense")
    func fractionParsing() {
        #expect(DownloadNaming.parseFraction("0.42") == 0.42)
        #expect(DownloadNaming.parseFraction("0,42") == 0.42)
        #expect(DownloadNaming.parseFraction(" 1 ") == 1)
        #expect(DownloadNaming.parseFraction("0") == 0)
        #expect(DownloadNaming.parseFraction("1.5") == nil)
        #expect(DownloadNaming.parseFraction("-0.1") == nil)
        #expect(DownloadNaming.parseFraction("abc") == nil)
        #expect(DownloadNaming.parseFraction("") == nil)
    }
}

@Suite("DownloadsReducer")
struct DownloadsReducerTests {
    typealias Reducer = DownloadsReducer
    let t0 = Date(timeIntervalSinceReferenceDate: 70_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func entry(_ finalName: String, bytes: Int64, fraction: Double? = nil, partial: String? = nil, unconfirmed: Bool = false) -> DownloadsScan.Entry {
        DownloadsScan.Entry(key: finalName, name: unconfirmed ? "Download" : finalName, partialName: partial ?? "\(finalName).crdownload",
                            bytes: bytes, fraction: fraction, isUnconfirmed: unconfirmed)
    }

    private func scan(_ entries: [DownloadsScan.Entry] = [], finals: [String: DownloadsScan.Final] = [:]) -> DownloadsScan {
        DownloadsScan(entries: entries, finals: finals)
    }

    private func final(size: Int64 = 1000, modified: TimeInterval) -> DownloadsScan.Final {
        DownloadsScan.Final(size: size, modified: at(modified))
    }

    private func posts(_ effects: [Reducer.Effect]) -> [Reducer.Model] {
        effects.compactMap { if case .post(let model, _) = $0 { model } else { nil } }
    }

    private func completions(_ effects: [Reducer.Effect]) -> [[String]] {
        effects.compactMap { if case .completed(let names) = $0 { names } else { nil } }
    }

    private func ended(_ effects: [Reducer.Effect]) -> Bool { effects.contains(.end) }

    /// A reducer past its first (empty) scan.
    private func running() -> Reducer {
        var reducer = Reducer()
        _ = reducer.reduce(.scan(scan()), now: t0)
        return reducer
    }

    // MARK: Showing

    @Test("Nothing partial shows nothing")
    func idle() {
        var reducer = Reducer()
        #expect(reducer.reduce(.scan(scan()), now: t0).isEmpty)
    }

    @Test("Three downloads at once are three rows in start order, and the ring has no total without progress")
    func threeAtOnce() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 200), entry("b.zip", bytes: 50)])), now: at(2))
        let effects = reducer.reduce(.scan(scan([entry("a.zip", bytes: 300), entry("b.zip", bytes: 90), entry("c.zip", bytes: 10)])), now: at(3))
        let model = posts(effects).last
        #expect(model?.items.map(\.name) == ["a.zip", "b.zip", "c.zip"])
        #expect(model?.overall == nil)
    }

    @Test("With progress for every download, the ring is the combined progress")
    func combinedProgress() {
        var reducer = running()
        let effects = reducer.reduce(.scan(scan([entry("a.zip", bytes: 500, fraction: 0.5), entry("b.zip", bytes: 100, fraction: 0.1)])), now: at(1))
        // 600 bytes of an estimated 1000 + 1000.
        #expect(abs((posts(effects).last?.overall ?? -1) - 0.3) < 1e-9)
    }

    @Test("A download with no progress makes the combined ring indeterminate")
    func oneUnknownTotal() {
        var reducer = running()
        let effects = reducer.reduce(.scan(scan([entry("a.zip", bytes: 500, fraction: 0.5), entry("b.zip", bytes: 100)])), now: at(1))
        #expect(posts(effects).last?.overall == nil)
    }

    @Test("Downloads already in progress when the module starts are shown, with no announcement")
    func seededAtStart() {
        var reducer = Reducer()
        let effects = reducer.reduce(.scan(scan([entry("big.iso", bytes: 4_000)])), now: t0)
        #expect(posts(effects).count == 1)
        #expect(completions(effects).isEmpty)
        let later = reducer.reduce(.scan(scan(finals: ["big.iso": final(modified: 30)])), now: at(31))
        #expect(completions(later) == [["big.iso"]])
    }

    // MARK: Finishing

    @Test("A finished download ends the activity and announces itself once")
    func completes() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        let effects = reducer.reduce(.scan(scan(finals: ["a.zip": final(modified: 5)])), now: at(5))
        #expect(completions(effects) == [["a.zip"]])
        #expect(ended(effects))
        #expect(reducer.reduce(.scan(scan(finals: ["a.zip": final(modified: 5)])), now: at(6)).isEmpty)
    }

    @Test("Safari's .download bundle finishes the same way")
    func safariBundle() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("photo.jpg", bytes: 10, partial: "photo.jpg.download")])), now: at(1))
        let effects = reducer.reduce(.scan(scan(finals: ["photo.jpg": final(modified: 3)])), now: at(3))
        #expect(completions(effects) == [["photo.jpg"]])
    }

    @Test("A rename seen a moment late still counts as finished")
    func renameSeenLate() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        let gone = reducer.reduce(.scan(scan()), now: at(4))
        #expect(completions(gone).isEmpty)
        #expect(ended(gone))
        let appeared = reducer.reduce(.scan(scan(finals: ["a.zip": final(modified: 4.2)])), now: at(4.5))
        #expect(completions(appeared) == [["a.zip"]])
    }

    @Test("A cancelled download disappears quietly after two seconds")
    func cancelled() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        let gone = reducer.reduce(.scan(scan()), now: at(4))
        #expect(gone.contains(.schedule(at(6))))
        let expired = reducer.reduce(.tick, now: at(6))
        #expect(completions(expired).isEmpty)
        #expect(expired == [.schedule(nil)])
        // Nothing is tracked any more: a later scan is quiet.
        #expect(reducer.reduce(.scan(scan()), now: at(7)).isEmpty)
    }

    @Test("Firefox's empty placeholder is not a finished file, and the real file is")
    func firefoxPlaceholder() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100, partial: "a.zip.part")], finals: ["a.zip": final(size: 0, modified: 0.5)])), now: at(1))
        let cancelled = reducer.reduce(.scan(scan(finals: ["a.zip": final(size: 0, modified: 0.5)])), now: at(4))
        #expect(completions(cancelled).isEmpty)
        var second = running()
        _ = second.reduce(.scan(scan([entry("b.zip", bytes: 100, partial: "b.zip.part")], finals: ["b.zip": final(size: 0, modified: 0.5)])), now: at(1))
        let done = second.reduce(.scan(scan(finals: ["b.zip": final(size: 5000, modified: 4)])), now: at(4))
        #expect(completions(done) == [["b.zip"]])
    }

    @Test("A file that was there before the download started doesn't count as it finishing")
    func oldFileDoesNotCount() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(100))
        let effects = reducer.reduce(.scan(scan(finals: ["a.zip": final(modified: 10)])), now: at(110))
        #expect(completions(effects).isEmpty)
    }

    @Test("Several finishing in one look are one announcement; no more than three a minute")
    func announcementsAreLimited() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a", bytes: 1), entry("b", bytes: 1)])), now: at(1))
        let both = reducer.reduce(.scan(scan(finals: ["a": final(modified: 2), "b": final(modified: 2)])), now: at(2))
        #expect(completions(both) == [["a", "b"]])
        var fired = 1
        for index in 0..<5 {
            let name = "n\(index)"
            let start = 10 + Double(index) * 5
            _ = reducer.reduce(.scan(scan([entry(name, bytes: 1)])), now: at(start))
            let done = reducer.reduce(.scan(scan(finals: [name: final(modified: start + 1)])), now: at(start + 1))
            fired += completions(done).count
        }
        #expect(fired == 3)
    }

    // MARK: Chrome, duplicates, scale

    @Test("Chrome's Unconfirmed download carries on under its real name, keeping its start and speed")
    func unconfirmedMigrates() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("Unconfirmed 1.crdownload", bytes: 1_000, partial: "Unconfirmed 1.crdownload", unconfirmed: true)])), now: at(1))
        _ = reducer.reduce(.scan(scan([entry("Unconfirmed 1.crdownload", bytes: 3_000, partial: "Unconfirmed 1.crdownload", unconfirmed: true)])), now: at(3))
        let effects = reducer.reduce(.scan(scan([entry("report.pdf", bytes: 4_000)])), now: at(4))
        let model = posts(effects).last
        #expect(model?.items.map(\.name) == ["report.pdf"])
        #expect(model?.items.first?.speed != nil)
        #expect(!ended(effects))
        // Still one download: finishing it announces the real name once.
        let done = reducer.reduce(.scan(scan(finals: ["report.pdf": final(modified: 6)])), now: at(6))
        #expect(completions(done) == [["report.pdf"]])
    }

    @Test("Two downloads with a duplicate's numbered name are two downloads")
    func duplicateNames() {
        var reducer = running()
        let effects = reducer.reduce(.scan(scan([entry("photo.jpg", bytes: 1), entry("photo (1).jpg", bytes: 1)])), now: at(1))
        #expect(posts(effects).last?.items.count == 2)
    }

    @Test("Thousands of partial files in one look are bounded to twenty tracked")
    func hugeScanIsBounded() {
        var reducer = running()
        let many = (0..<5_000).map { entry("file\($0).bin", bytes: Int64($0)) }
        let effects = reducer.reduce(.scan(scan(many)), now: at(1))
        #expect(posts(effects).count == 1)
        #expect(posts(effects).last?.items.count == DownloadsReducer.maxTracked)
    }

    // MARK: Speed, sleep, stale

    @Test("Speed is smoothed from growth between looks")
    func speedFromGrowth() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 0)])), now: at(1))
        let effects = reducer.reduce(.scan(scan([entry("a.zip", bytes: 2_000_000)])), now: at(3))
        #expect(posts(effects).last?.items.first?.speed == 1_000_000)
    }

    @Test("A long gap between looks (sleep) doesn't make a speed spike or a false cancel")
    func sleepGap() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        _ = reducer.reduce(.wake, now: at(5000))
        let effects = reducer.reduce(.scan(scan([entry("a.zip", bytes: 900_000_000)])), now: at(5001))
        #expect(posts(effects).last?.items.first?.speed == nil)
        #expect(!ended(effects))
    }

    @Test("A download that stops growing goes stale a minute after its last progress")
    func staleDate() {
        var reducer = running()
        let first = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        let second = reducer.reduce(.scan(scan([entry("a.zip", bytes: 200)])), now: at(5))
        #expect(stale(first) == at(61))
        #expect(stale(second) == at(65))
        let still = reducer.reduce(.scan(scan([entry("a.zip", bytes: 200)])), now: at(20))
        #expect(stale(still) == at(65))
    }

    private func stale(_ effects: [Reducer.Effect]) -> Date? {
        effects.compactMap { if case .post(_, let date) = $0 { date } else { nil } }.last
    }

    @Test("A download that reappears after seeming to vanish carries on")
    func reappears() {
        var reducer = running()
        _ = reducer.reduce(.scan(scan([entry("a.zip", bytes: 100)])), now: at(1))
        _ = reducer.reduce(.scan(scan()), now: at(2))
        let back = reducer.reduce(.scan(scan([entry("a.zip", bytes: 150)])), now: at(3))
        #expect(posts(back).last?.items.map(\.name) == ["a.zip"])
        #expect(reducer.reduce(.tick, now: at(5)).isEmpty)
    }

    @Test("However scans arrive, nothing ends without being posted, and everything settles")
    func fuzz() {
        var generator = SplitMix(seed: 0xD0D0)
        let names = ["a.zip", "b.zip", "c (1).zip"]
        for _ in 0..<300 {
            var reducer = Reducer()
            var clock = t0
            var live = false
            var deadline: Date?
            func apply(_ effects: [Reducer.Effect]) {
                for effect in effects {
                    switch effect {
                    case .post: live = true
                    case .end: #expect(live, "ended an activity that wasn't posted"); live = false
                    case .completed: break
                    case .schedule(let date): deadline = date
                    }
                }
            }
            for _ in 0..<40 {
                clock += Double(generator.next() % 4000) / 1000
                switch generator.next() % 5 {
                case 0: apply(reducer.reduce(.wake, now: clock))
                case 1: apply(reducer.reduce(.tick, now: clock))
                default:
                    let present = names.filter { _ in generator.next() % 2 == 0 }
                    let entries = present.map { entry($0, bytes: Int64(generator.next() % 10_000)) }
                    var finals: [String: DownloadsScan.Final] = [:]
                    for name in names where !present.contains(name) && generator.next() % 3 == 0 {
                        finals[name] = DownloadsScan.Final(size: 100, modified: clock)
                    }
                    apply(reducer.reduce(.scan(DownloadsScan(entries: entries, finals: finals)), now: clock))
                }
            }
            apply(reducer.reduce(.scan(scan()), now: clock))
            for _ in 0..<3 {
                clock += 3
                apply(reducer.reduce(.tick, now: clock))
            }
            #expect(!live, "an activity outlived every download")
            #expect(deadline == nil, "a deadline was left behind")
        }
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

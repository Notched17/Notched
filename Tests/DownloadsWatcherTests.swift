// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The scan and the FSEvents stream run against real temporary folders (which
/// need no permission), never ~/Downloads.
@Suite("DownloadsScanner")
struct DownloadsScannerTests {
    /// A fresh empty folder, removed after the test.
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchedDownloadsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 0x2A, count: bytes).write(to: url)
    }

    private func setFraction(_ text: String, on url: URL) {
        _ = text.withCString { setxattr(url.path, DownloadsScanner.fractionAttribute, $0, strlen($0), 0, 0) }
    }

    @Test("Partial files are found with their sizes, and ordinary files are left out")
    func findsPartials() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(100, to: dir.appendingPathComponent("a.zip.crdownload"))
        try write(40, to: dir.appendingPathComponent("b.zip.part"))
        try write(10, to: dir.appendingPathComponent("notes.txt"))
        let scan = DownloadsScanner.scan(directory: dir.path, watching: [])
        #expect(scan.entries.map(\.key).sorted() == ["a.zip", "b.zip"])
        #expect(scan.entries.first { $0.key == "a.zip" }?.bytes == 100)
        #expect(scan.finals.isEmpty)
    }

    @Test("Safari's .download bundle is sized by what's inside it")
    func bundleSize() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = dir.appendingPathComponent("photo.jpg.download")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try write(300, to: bundle.appendingPathComponent("photo.jpg"))
        try write(50, to: bundle.appendingPathComponent("Info.plist"))
        let scan = DownloadsScanner.scan(directory: dir.path, watching: [])
        #expect(scan.entries.map(\.key) == ["photo.jpg"])
        #expect(scan.entries.first?.bytes == 350)
    }

    @Test("The progress attribute is read, with a comma or a point")
    func readsFraction() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let point = dir.appendingPathComponent("a.zip.crdownload")
        let comma = dir.appendingPathComponent("b.zip.crdownload")
        let none = dir.appendingPathComponent("c.zip.crdownload")
        for url in [point, comma, none] { try write(1, to: url) }
        setFraction("0.25", on: point)
        setFraction("0,75", on: comma)
        let scan = DownloadsScanner.scan(directory: dir.path, watching: [])
        #expect(scan.entries.first { $0.key == "a.zip" }?.fraction == 0.25)
        #expect(scan.entries.first { $0.key == "b.zip" }?.fraction == 0.75)
        #expect(scan.entries.first { $0.key == "c.zip" }?.fraction == nil)
    }

    @Test("Finished files are only reported for names being watched")
    func finalsOnlyForWatched() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(500, to: dir.appendingPathComponent("a.zip"))
        try write(500, to: dir.appendingPathComponent("other.zip"))
        let scan = DownloadsScanner.scan(directory: dir.path, watching: ["a.zip", "missing.zip"])
        #expect(Set(scan.finals.keys) == ["a.zip"])
        #expect(scan.finals["a.zip"]?.size == 500)
    }

    @Test("A folder that can't be read is an empty scan, not a crash")
    func unreadable() {
        #expect(DownloadsScanner.scan(directory: "/definitely/not/here", watching: ["x"]) == DownloadsScan(entries: [], finals: [:]))
    }

    @Test("Many partial files in one folder are capped")
    func capped() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<(DownloadsScanner.maxEntries + 40) { try write(1, to: dir.appendingPathComponent("f\(index).bin.part")) }
        #expect(DownloadsScanner.scan(directory: dir.path, watching: []).entries.count == DownloadsScanner.maxEntries)
    }
}

@Suite("DownloadsWatcher", .serialized)
@MainActor
struct DownloadsWatcherTests {
    /// Scans delivered so far, on the main queue like the app.
    @MainActor final class Scans {
        var all: [DownloadsScan] = []
        var latest: DownloadsScan? { all.last }
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchedWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 0x2A, count: bytes).write(to: url)
    }

    /// Lets the main queue run until `condition` holds, for up to five seconds.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func makeWatcher(_ dir: URL, scans: Scans) -> DownloadsWatcher {
        DownloadsWatcher(directory: dir.path) { scan in
            MainActor.assumeIsolated { scans.all.append(scan) }
        }
    }

    @Test("The watched path is the real one FSEvents reports, not a symlinked alias")
    func canonicalPath() {
        #expect(DownloadsWatcher.canonicalPath("/var").hasPrefix("/private/"))
        #expect(DownloadsWatcher.canonicalPath("/definitely/not/here") == "/definitely/not/here")
    }

    @Test("Starting reads what's already there")
    func initialScan() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(100, to: dir.appendingPathComponent("a.zip.crdownload"))
        let scans = Scans()
        let watcher = makeWatcher(dir, scans: scans)
        watcher.start()
        #expect(await waitUntil { scans.latest?.entries.map(\.key) == ["a.zip"] })
        watcher.stop()
        watcher.flush()
    }

    @Test("A download that starts, grows and finishes is seen, and its final file is found once it is watched")
    func followsADownload() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scans = Scans()
        let watcher = makeWatcher(dir, scans: scans)
        watcher.start()
        #expect(await waitUntil { !scans.all.isEmpty })
        // FSEvents can miss changes made in the first moments after a stream starts.
        try await Task.sleep(for: .seconds(1))

        let partial = dir.appendingPathComponent("movie.mp4.crdownload")
        try write(1_000, to: partial)
        #expect(await waitUntil { scans.latest?.entries.first?.bytes == 1_000 })
        try write(5_000, to: partial)
        #expect(await waitUntil { scans.latest?.entries.first?.bytes == 5_000 })

        watcher.setWatchedNames(["movie.mp4"])
        try FileManager.default.moveItem(at: partial, to: dir.appendingPathComponent("movie.mp4"))
        #expect(await waitUntil { scans.latest?.entries.isEmpty == true && scans.latest?.finals["movie.mp4"]?.size == 5_000 })
        watcher.stop()
        watcher.flush()
    }

    @Test("Thousands of files appearing deep in a subfolder don't cause a scan each")
    func deepEventsAreIgnored() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scans = Scans()
        let watcher = makeWatcher(dir, scans: scans)
        watcher.start()
        #expect(await waitUntil { !scans.all.isEmpty })
        let sub = dir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try await Task.sleep(for: .seconds(1))
        let before = scans.all.count
        for index in 0..<2_000 { try write(1, to: sub.appendingPathComponent("file\(index).txt")) }
        try await Task.sleep(for: .seconds(2))
        #expect(scans.all.count - before <= 1, "\(scans.all.count - before) scans for 2000 deep files")
        watcher.stop()
        watcher.flush()
    }

    @Test("Starting and stopping five times leaves no stream behind")
    func startStopNeverLeaks() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scans = Scans()
        let watcher = makeWatcher(dir, scans: scans)
        #expect(watcher.streamCount == 0)
        for _ in 0..<5 {
            watcher.start()
            watcher.flush()
            #expect(watcher.streamCount == 1)
            watcher.stop()
            watcher.flush()
            #expect(watcher.streamCount == 0)
        }
    }

    @Test("Nothing is delivered after stop")
    func silentAfterStop() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scans = Scans()
        let watcher = makeWatcher(dir, scans: scans)
        watcher.start()
        #expect(await waitUntil { !scans.all.isEmpty })
        watcher.stop()
        watcher.flush()
        try await Task.sleep(for: .milliseconds(300))
        let count = scans.all.count
        try write(10, to: dir.appendingPathComponent("late.bin.part"))
        try await Task.sleep(for: .seconds(1.5))
        #expect(scans.all.count == count)
    }
}

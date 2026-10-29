// SPDX-License-Identifier: GPL-3.0-or-later

import CoreServices
import Darwin
import Foundation
import os

/// Reads a downloads folder into a `DownloadsScan`: which partial files are
/// there, how big, and how far along if the browser says. One directory
/// listing plus a `stat` per partial file, however many events led here.
enum DownloadsScanner {
    static let fractionAttribute = "com.apple.progress.fractionCompleted"
    /// More partial files than this in one folder are ignored.
    static let maxEntries = 200

    static func scan(directory: String, watching watched: Set<String>) -> DownloadsScan {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return DownloadsScan(entries: [], finals: [:])
        }
        var entries: [DownloadsScan.Entry] = []
        var finals: [String: DownloadsScan.Final] = [:]
        for name in names {
            let path = directory + "/" + name
            if let partial = DownloadNaming.partial(name) {
                guard entries.count < maxEntries, let info = stat(path) else { continue }
                let bytes = info.isDirectory ? bundleSize(path) : info.size
                entries.append(DownloadsScan.Entry(key: partial.finalName, name: partial.displayName, partialName: name,
                                                   bytes: bytes, fraction: fraction(at: path), isUnconfirmed: partial.isUnconfirmed))
            } else if watched.contains(name), let info = stat(path) {
                finals[name] = DownloadsScan.Final(size: info.size, modified: info.modified)
            }
        }
        return DownloadsScan(entries: entries.sorted { $0.key < $1.key }, finals: finals)
    }

    private struct FileInfo {
        var size: Int64
        var modified: Date
        var isDirectory: Bool
    }

    private static func stat(_ path: String) -> FileInfo? {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        return FileInfo(size: Int64(info.st_size), modified: modified, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR)
    }

    /// A Safari `.download` bundle holds the partial data and a plist.
    private static func bundleSize(_ path: String) -> Int64 {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.reduce(0) { total, name in
            guard let info = stat(path + "/" + name), !info.isDirectory else { return total }
            return total + info.size
        }
    }

    private static func fraction(at path: String) -> Double? {
        let size = getxattr(path, fractionAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size < 64 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, fractionAttribute, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
        return DownloadNaming.parseFraction(String(decoding: buffer, as: UTF8.self))
    }
}

/// Watches a folder with FSEvents, on its own queue, and delivers a fresh
/// `DownloadsScan` (on the main queue, in order) after changes to what's *directly*
/// in it. Events deeper down (an archive unzipping into a subfolder) are
/// dropped without a look, except inside a Safari `.download` bundle, so a
/// flood of events is a handful of scans: the work depends on the folder,
/// not on how many events there were.
///
/// Reading the real Downloads folder needs the Files & Folders permission;
/// the module only starts this once it's granted.
final class DownloadsWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "me.rkck.Notched.downloads", qos: .utility)
    private let directory: String
    private let root: String
    private let onScan: @Sendable (DownloadsScan) -> Void
    private let watched = OSAllocatedUnfairLock(initialState: Set<String>())
    private let streams = OSAllocatedUnfairLock(initialState: 0)

    // Confined to `queue`.
    private var stream: FSEventStreamRef?
    private var pendingScan: DispatchWorkItem?

    /// - Parameter onScan: called on the main queue, in order.
    init(directory: String, onScan: @escaping @Sendable (DownloadsScan) -> Void) {
        self.directory = directory
        self.root = Self.canonicalPath(directory)
        self.onScan = onScan
    }

    /// The folder's real path, which is what FSEvents reports (`/var/…` is
    /// `/private/var/…`). Not `URL.resolvingSymlinksInPath()`, which strips a
    /// leading `/private` and so never matches.
    static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// FSEvents streams running now (tests check none leak).
    var streamCount: Int { streams.withLock { $0 } }

    func start() {
        queue.async { self.begin() }
    }

    func stop() {
        queue.async { self.end() }
    }

    /// The finished names to look for (the downloads being followed).
    func setWatchedNames(_ names: Set<String>) {
        let changed = watched.withLock { current -> Bool in
            guard current != names else { return false }
            current = names
            return true
        }
        if changed { queue.async { self.scheduleScan() } }
    }

    /// Waits for everything queued so far (tests, and a clean quit).
    func flush() {
        queue.sync {}
    }

    private func begin() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passRetained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, Self.callback, &context, [root] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else {
            Unmanaged<DownloadsWatcher>.passUnretained(self).release()
            Log.module("downloads").error("The Downloads folder couldn't be watched")
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        streams.withLock { $0 += 1 }
        scanNow()
    }

    private func end() {
        pendingScan?.cancel()
        pendingScan = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        streams.withLock { $0 -= 1 }
        // Balances the retain made for the stream's context.
        Unmanaged<DownloadsWatcher>.passUnretained(self).release()
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<DownloadsWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
        watcher.handle(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
    }

    /// Runs on `queue`. Cheap string checks only; the scan reads the folder once.
    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard stream != nil else { return }
        let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                                           | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
        for (index, path) in paths.enumerated() {
            if index < flags.count, flags[index] & lost != 0 || isRelevant(path) {
                scheduleScan()
                return
            }
        }
    }

    /// A direct child of the folder, or something inside a direct child `.download` bundle.
    private func isRelevant(_ path: String) -> Bool {
        guard path.hasPrefix(root + "/") else { return path == root }
        let relative = path.dropFirst(root.count + 1)
        guard let slash = relative.firstIndex(of: "/") else { return true }
        return relative[..<slash].lowercased().hasSuffix(".download")
    }

    private func scheduleScan() {
        guard stream != nil, pendingScan == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingScan = nil
            self?.scanNow()
        }
        pendingScan = item
        queue.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    private func scanNow() {
        guard stream != nil else { return }
        let names = watched.withLock { $0 }
        let scan = DownloadsScanner.scan(directory: directory, watching: names)
        let onScan = onScan
        DispatchQueue.main.async { onScan(scan) }
    }
}

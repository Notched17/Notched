// SPDX-License-Identifier: GPL-3.0-or-later

import CoreServices
import Foundation

/// What the AI tab shows.
struct ClaudeUsageSnapshot: Equatable, Sendable {
    struct ActiveSession: Equatable, Sendable, Identifiable {
        var id: String
        var project: String
        var lastActivity: Date
    }

    var today = UsageTotals()
    var week = UsageTotals()
    var days: [DayTotal] = []
    var models: [ModelTotal] = []
    var activeSessions: [ActiveSession] = []
    var pricingUpdated: String?
    /// Lines that looked like usage but couldn't be read, so format changes are visible.
    var skippedLines = 0
    var updatedAt = Date.distantPast
}

/// Watches directories with FSEvents and says only that something changed.
/// It reads nothing itself; the usage service does that when asked.
final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "me.rkck.Notched.usage-fsevents", qos: .utility)
    private let onChange: @Sendable () -> Void

    init(paths: [String], latency: TimeInterval = 2, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

/// Reads Claude Code's session logs incrementally: it remembers each file's
/// inode and byte offset, reads only what was appended, and parses only
/// complete lines. A 100 MB log is streamed in 1 MB chunks, never loaded whole.
actor ClaudeUsageService {
    private struct FileState {
        var inode: UInt64
        var offset: UInt64
        var partial: Data
        var modified: Date
        /// The file's first bytes when it was first read: if they change, it's a different file.
        var head: Data = Data()
    }

    private static let headLength = 128

    private let rootsProvider: @Sendable () -> [URL]
    private let calendar: Calendar
    private var pricing: ClaudePricing
    private var aggregator: ClaudeUsageAggregator
    private var files: [String: FileState] = [:]
    private var sessions: [String: (project: String, last: Date)] = [:]
    private var skipped = 0
    private var clock = Date()
    private static let chunk = 1 << 20
    private static let window: TimeInterval = Double(ClaudeUsageAggregator.keptDays) * 86_400
    private static let activeWithin: TimeInterval = 5 * 60

    init(roots: @escaping @Sendable () -> [URL] = { ClaudeUsageService.defaultRoots() }, calendar: Calendar = .current, pricing: ClaudePricing = .load()) {
        rootsProvider = roots
        self.calendar = calendar
        self.pricing = pricing
        aggregator = ClaudeUsageAggregator(calendar: calendar)
    }

    /// `~/.claude/projects` and `~/.config/claude/projects`, where they exist.
    static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func reloadPricing() {
        pricing = .load()
    }

    /// Reads anything new and returns the numbers.
    func refresh(now: Date = Date()) -> ClaudeUsageSnapshot {
        clock = now
        for file in logFiles(modifiedAfter: now.addingTimeInterval(-Self.window)) { read(file) }
        aggregator.prune(now: now)
        let active = sessions
            .filter { now.timeIntervalSince($0.value.last) <= Self.activeWithin }
            .map { ClaudeUsageSnapshot.ActiveSession(id: $0.key, project: $0.value.project, lastActivity: $0.value.last) }
            .sorted { $0.lastActivity > $1.lastActivity }
        // Forget sessions that finished long ago so the table stays small.
        sessions = sessions.filter { now.timeIntervalSince($0.value.last) < Self.window }
        return ClaudeUsageSnapshot(
            today: aggregator.today(now: now, pricing: pricing),
            week: aggregator.week(now: now, pricing: pricing),
            days: aggregator.daily(now: now, pricing: pricing),
            models: aggregator.models(now: now, pricing: pricing),
            activeSessions: active,
            pricingUpdated: pricing.updated,
            skippedLines: skipped,
            updatedAt: now
        )
    }

    private struct LogFile {
        let url: URL
        let inode: UInt64
        let size: UInt64
        let modified: Date
    }

    private func logFiles(modifiedAfter cutoff: Date) -> [LogFile] {
        var result: [LogFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        for root in rootsProvider() {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                      let size = (attributes[.size] as? NSNumber)?.uint64Value else { continue }
                result.append(LogFile(url: url, inode: inode, size: size, modified: modified))
            }
        }
        return result
    }

    private func read(_ file: LogFile) {
        let path = file.url.path
        var state = files[path] ?? FileState(inode: file.inode, offset: 0, partial: Data(), modified: .distantPast)
        // Nothing new since the last look.
        if file.size == state.offset, file.modified == state.modified, state.modified != .distantPast { return }
        // Replaced, truncated, or rewritten without growing: start again (the dedupe set absorbs repeats).
        let rewritten = file.size <= state.offset && file.modified != state.modified && state.modified != .distantPast
        if state.inode != file.inode || file.size < state.offset || rewritten { state = FileState(inode: file.inode, offset: 0, partial: Data(), modified: .distantPast) }
        guard file.size > 0, let handle = try? FileHandle(forReadingFrom: file.url) else {
            state.modified = file.modified
            files[path] = state
            return
        }
        defer { try? handle.close() }
        do {
            // A different start means a different file, even if it grew.
            let head = try handle.read(upToCount: Self.headLength) ?? Data()
            if !state.head.isEmpty, head.prefix(state.head.count) != state.head {
                state = FileState(inode: file.inode, offset: 0, partial: Data(), modified: .distantPast)
            }
            if state.head.count < head.count { state.head = head }
            let project = Self.projectName(from: file.url)
            try handle.seek(toOffset: state.offset)
            while true {
                guard let data = try handle.read(upToCount: Self.chunk), !data.isEmpty else { break }
                state.offset += UInt64(data.count)
                var buffer = state.partial + data
                var start = buffer.startIndex
                while let newline = buffer[start...].firstIndex(of: 0x0A) {
                    consume(buffer[start..<newline], project: project)
                    start = buffer.index(after: newline)
                }
                buffer = Data(buffer[start...])
                // A single line this long isn't a log line; drop it rather than grow without bound.
                state.partial = buffer.count > 8 << 20 ? Data() : buffer
            }
        } catch {
            skipped += 1
        }
        state.modified = file.modified
        files[path] = state
    }

    private func consume(_ line: Data, project: String) {
        guard !line.isEmpty else { return }
        switch ClaudeUsageParser.decode(line: Data(line)) {
        case .ignored:
            return
        case .unreadable:
            skipped += 1
        case .record(let record):
            guard record.timestamp > clock.addingTimeInterval(-Self.window) else { return }
            aggregator.add(record)
            if let id = record.sessionID {
                let name = record.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? project
                if (sessions[id]?.last ?? .distantPast) < record.timestamp { sessions[id] = (name, record.timestamp) }
            }
        }
    }

    /// The project folder name Claude Code uses is the path with `/` turned
    /// into `-`; the last piece after the final `-` is the best short name.
    static func projectName(from file: URL) -> String {
        var folder = file.deletingLastPathComponent()
        while folder.deletingLastPathComponent().lastPathComponent != "projects", folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        let name = folder.lastPathComponent
        return name.split(separator: "-").last.map(String.init) ?? name
    }
}

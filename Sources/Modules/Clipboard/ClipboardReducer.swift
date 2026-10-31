// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Clipboard history's rules (#45). The shell polls `NSPasteboard.changeCount`
/// and reads the pasteboard only when this asks it to; this decides what is
/// kept. Nothing here touches the system or logs content.
///
/// - The first change count seen is silent: what was on the clipboard when
///   the module started isn't a new copy.
/// - Our own copy-backs (`wrote`) are not recorded again.
/// - Private items and excluded apps are never kept.
/// - The same content twice is one entry, moved to the top.
/// - Pinned items never count toward the length and are never dropped.
struct ClipboardReducer: Sendable {
    struct Config: Equatable, Sendable {
        var limit = 200
        var excludedApps: Set<String> = Set(ClipboardPolicy.defaultExcludedApps)
        var clearOnQuit = false
    }

    struct State: Equatable, Sendable {
        var entries: [ClipboardEntry] = []
        var config = Config()
        /// The last change count dealt with. Nil until the first tick.
        var lastChangeCount: Int?
    }

    enum Event: Equatable, Sendable {
        /// The saved history, read once at start.
        case loaded([ClipboardEntry])
        case configure(Config)
        /// The poll: the pasteboard's current change count.
        case tick(changeCount: Int)
        /// The answer to `.read`.
        case captured(ClipboardCapture)
        /// A copy-back happened; this is the change count it produced.
        case wrote(changeCount: Int)
        case copyBack(UUID)
        case togglePin(UUID)
        case delete(UUID)
        /// Clears the history. Pinned items stay unless `includingPinned`.
        case clear(includingPinned: Bool)
        case quit
    }

    enum Effect: Equatable, Sendable {
        /// Look at the pasteboard now and answer with `.captured`.
        case read(changeCount: Int)
        /// Save this history.
        case persist([ClipboardEntry])
        /// No entry uses this image any more.
        case deleteImage(contentHash: String)
        /// Put this entry back on the pasteboard, then answer with `.wrote`.
        case writeToPasteboard(ClipboardEntry)
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .loaded(let saved):
            state.entries = saved
            return persistingIfTrimmed()
        case .configure(let config):
            state.config = config
            return persistingIfTrimmed()
        case .tick(let count):
            guard let last = state.lastChangeCount else {
                state.lastChangeCount = count
                return []
            }
            guard count != last else { return [] }
            state.lastChangeCount = count
            return [.read(changeCount: count)]
        case .captured(let capture):
            return record(capture, now: now)
        case .wrote(let count):
            state.lastChangeCount = count
            return []
        case .copyBack(let id):
            guard let entry = state.entries.first(where: { $0.id == id }) else { return [] }
            return [.writeToPasteboard(entry)]
        case .togglePin(let id):
            guard let index = state.entries.firstIndex(where: { $0.id == id }) else { return [] }
            state.entries[index].isPinned.toggle()
            // Unpinning can leave more unpinned items than the length allows.
            let removed = trim()
            return [.persist(state.entries)] + imageEffects(for: removed)
        case .delete(let id):
            guard let index = state.entries.firstIndex(where: { $0.id == id }) else { return [] }
            let removed = state.entries.remove(at: index)
            return [.persist(state.entries)] + imageEffects(for: [removed])
        case .clear(let includingPinned):
            let removed = state.entries.filter { includingPinned || !$0.isPinned }
            guard !removed.isEmpty else { return [] }
            state.entries.removeAll { includingPinned || !$0.isPinned }
            return [.persist(state.entries)] + imageEffects(for: removed)
        case .quit:
            guard state.config.clearOnQuit else { return [] }
            return reduce(.clear(includingPinned: false), now: now)
        }
    }

    // MARK: Recording

    private mutating func record(_ capture: ClipboardCapture, now: Date) -> [Effect] {
        if ClipboardPolicy.skipReason(types: capture.typeIdentifiers, sourceBundleID: capture.sourceBundleID, excludedApps: state.config.excludedApps) != nil {
            return []
        }
        guard let candidate = capture.candidate else { return [] }

        if let index = state.entries.firstIndex(where: { $0.contentHash == candidate.contentHash && $0.kind == candidate.kind }) {
            // Copied again: it moves to the top and keeps its pin.
            var entry = state.entries.remove(at: index)
            entry.createdAt = now
            entry.sourceBundleID = capture.sourceBundleID ?? entry.sourceBundleID
            entry.sourceName = capture.sourceName ?? entry.sourceName
            state.entries.insert(entry, at: 0)
            return [.persist(state.entries)]
        }

        state.entries.insert(ClipboardEntry(
            id: capture.newID, kind: candidate.kind, text: candidate.text, contentHash: candidate.contentHash, createdAt: now,
            sourceBundleID: capture.sourceBundleID, sourceName: capture.sourceName
        ), at: 0)
        let removed = trim()
        return [.persist(state.entries)] + imageEffects(for: removed)
    }

    /// Drops the oldest unpinned items past the limit and returns them.
    private mutating func trim() -> [ClipboardEntry] {
        var removed: [ClipboardEntry] = []
        while state.entries.filter({ !$0.isPinned }).count > state.config.limit,
              let index = state.entries.lastIndex(where: { !$0.isPinned }) {
            removed.append(state.entries.remove(at: index))
        }
        return removed
    }

    /// For changes that only matter if they dropped something (a shorter limit, a long saved list).
    private mutating func persistingIfTrimmed() -> [Effect] {
        let removed = trim()
        guard !removed.isEmpty else { return [] }
        return [.persist(state.entries)] + imageEffects(for: removed)
    }

    /// Image files go only when no remaining entry shares the content.
    private func imageEffects(for removed: [ClipboardEntry]) -> [Effect] {
        var hashes: [String] = []
        for entry in removed where entry.kind == .image {
            let stillUsed = state.entries.contains { $0.kind == .image && $0.contentHash == entry.contentHash }
            if !stillUsed, !hashes.contains(entry.contentHash) { hashes.append(entry.contentHash) }
        }
        return hashes.map { .deleteImage(contentHash: $0) }
    }
}

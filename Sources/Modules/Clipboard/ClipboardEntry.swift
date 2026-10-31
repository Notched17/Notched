// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What kind of thing was copied (#45).
enum ClipboardKind: String, Codable, Sendable {
    case text, url, file, image

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .file: "doc"
        case .image: "photo"
        }
    }
}

/// One item of clipboard history.
///
/// `text` is the text itself, the URL, the file paths (references only; the
/// files are never copied), or a short description of an image. An image's
/// pixels live in a file named after `contentHash`.
struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var kind: ClipboardKind
    var text: String
    /// SHA-256 of the content: the same copy twice is one entry.
    var contentHash: String
    var createdAt: Date
    var isPinned: Bool = false
    var sourceBundleID: String?
    var sourceName: String?

    /// One line for the list: whitespace collapsed, cut at 200 characters.
    var preview: String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 200 ? String(collapsed.prefix(200)) + "…" : collapsed
    }
}

/// What the shell found on the pasteboard, before it becomes an entry.
struct ClipboardCandidate: Equatable, Sendable {
    var kind: ClipboardKind
    var text: String
    var contentHash: String
}

/// One look at the pasteboard after its change count moved.
struct ClipboardCapture: Equatable, Sendable {
    /// Every type on the pasteboard item, e.g. `public.utf8-plain-text`.
    var typeIdentifiers: [String]
    var sourceBundleID: String?
    var sourceName: String?
    /// Nil when nothing usable was found, or the shell left it unread.
    var candidate: ClipboardCandidate?
    /// Made by the shell so the reducer needs no randomness.
    var newID: UUID
}

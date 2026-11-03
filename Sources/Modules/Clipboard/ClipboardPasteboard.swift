// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO

/// The system pasteboard as clipboard history needs it. A protocol so tests
/// can stand in for it with a pasteboard they control.
@MainActor
protocol ClipboardPasteboard: AnyObject {
    /// Reading this never shows macOS's pasteboard prompt; reading contents may.
    var changeCount: Int { get }
    /// Every type on the pasteboard's items. Types only, never contents.
    var typeIdentifiers: [String] { get }
    var frontmostApp: (bundleID: String?, name: String?) { get }
    /// Reads the contents and, for an image, saves it into `store`. Called only
    /// for copies the policy allows. Nil when there is nothing usable.
    func readCandidate(store: ClipboardStore) -> ClipboardCandidate?
    /// When the copy is a picture, its raw bytes, read now. The slow part (decoding,
    /// shrinking, saving the PNG and thumbnail) then runs off the main thread
    /// through `ClipboardImageIngest`, so copying a big screenshot never stalls the island.
    /// Nil for anything else; fakes that don't do pictures can leave the default.
    func pendingImage() -> Data?
    /// Puts the entry back. False when it couldn't (an image file went missing).
    func write(_ entry: ClipboardEntry, store: ClipboardStore) -> Bool
}

extension ClipboardPasteboard {
    func pendingImage() -> Data? { nil }
}

/// Turns raw picture bytes into a candidate, saving the PNG and thumbnail in
/// `store`. Pure work on its inputs, so it can run on any thread.
enum ClipboardImageIngest {
    static let maxRawBytes = 50_000_000

    static func candidate(raw: Data, store: ClipboardStore) -> ClipboardCandidate? {
        guard raw.count <= maxRawBytes else { return nil }
        let hash = ClipboardHash.hash(kind: .image, data: raw)
        if !store.hasImage(hash: hash) {
            guard let encoded = ClipboardImageCodec.encode(raw) else { return nil }
            do { try store.saveImage(hash: hash, png: encoded.png, thumbnail: encoded.thumbnail) } catch { return nil }
        }
        let size = ClipboardImageCodec.pixelSize(of: raw)
        let text = size.map { "Image \($0.width) × \($0.height)" } ?? "Image"
        return ClipboardCandidate(kind: .image, text: text, contentHash: hash)
    }
}

/// `NSPasteboard.general`.
@MainActor
final class SystemClipboardPasteboard: ClipboardPasteboard {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    var typeIdentifiers: [String] {
        var seen = Set<String>()
        return (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }.filter { seen.insert($0).inserted }
    }

    var frontmostApp: (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    private enum Pick {
        case files([URL])
        case image
        case text
    }

    /// Files first (Finder also puts the file's name on as text), then text, and a
    /// picture only when there is no text (spreadsheets and word processors put a
    /// picture of the selection beside the text), or when the text is empty.
    private func pick() -> Pick {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        let hasText = Set(typeIdentifiers).contains(NSPasteboard.PasteboardType.string.rawValue)
        return hasText ? .text : .image
    }

    private func rawImage() -> Data? {
        pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    func pendingImage() -> Data? {
        guard case .image = pick() else { return nil }
        return rawImage()
    }

    func readCandidate(store: ClipboardStore) -> ClipboardCandidate? {
        switch pick() {
        case .files(let urls):
            let text = urls.map(\.path).joined(separator: "\n")
            guard text.utf8.count <= ClipboardPolicy.maxTextBytes else { return nil }
            return ClipboardCandidate(kind: .file, text: text, contentHash: ClipboardHash.hash(kind: .file, text: text))
        case .image:
            return rawImage().flatMap { ClipboardImageIngest.candidate(raw: $0, store: store) }
        case .text:
            if let string = pasteboard.string(forType: .string) {
                guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      string.utf8.count <= ClipboardPolicy.maxTextBytes else { return nil }
                let kind: ClipboardKind = Self.isLink(string) ? .url : .text
                return ClipboardCandidate(kind: kind, text: string, contentHash: ClipboardHash.hash(kind: kind, text: string))
            }
            return rawImage().flatMap { ClipboardImageIngest.candidate(raw: $0, store: store) }
        }
    }

    /// One line that is a web or mail link and nothing else.
    nonisolated static func isLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "mailto"].contains(scheme) && (url.host != nil || scheme == "mailto")
    }

    func write(_ entry: ClipboardEntry, store: ClipboardStore) -> Bool {
        switch entry.kind {
        case .text, .url:
            pasteboard.clearContents()
            return pasteboard.setString(entry.text, forType: .string)
        case .file:
            let urls = entry.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls)
        case .image:
            guard let data = try? Data(contentsOf: store.imageURL(hash: entry.contentHash)) else { return false }
            pasteboard.clearContents()
            return pasteboard.setData(data, forType: .png)
        }
    }
}

extension ClipboardImageCodec {
    /// The picture's size from its header, without decoding it.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

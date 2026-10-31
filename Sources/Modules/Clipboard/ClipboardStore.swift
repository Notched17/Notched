// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Clipboard history on disk (#45): a JSON index plus one file per image, in a
/// private folder. No database and nothing running in the background; the
/// module writes after a change, a couple of seconds later.
///
/// The files are readable only by the user but are **not encrypted**, so what
/// was copied sits on disk as plain text until it is cleared or evicted.
struct ClipboardStore: Sendable {
    let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var imagesURL: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notched/Clipboard", isDirectory: true)
    }

    // MARK: Index

    /// The saved history, newest first. A missing or damaged file is an empty history.
    func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ClipboardEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ClipboardEntry]) throws {
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: indexURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }

    // MARK: Images

    func imageURL(hash: String) -> URL { imagesURL.appendingPathComponent("\(hash).png") }
    func thumbnailURL(hash: String) -> URL { imagesURL.appendingPathComponent("\(hash)-thumb.png") }

    func hasImage(hash: String) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(hash: hash).path)
    }

    func saveImage(hash: String, png: Data, thumbnail: Data) throws {
        try prepareDirectories()
        for (url, data) in [(imageURL(hash: hash), png), (thumbnailURL(hash: hash), thumbnail)] {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func deleteImage(hash: String) {
        try? FileManager.default.removeItem(at: imageURL(hash: hash))
        try? FileManager.default.removeItem(at: thumbnailURL(hash: hash))
    }

    /// Removes image files no entry refers to (after a crash between an
    /// eviction and its save, say).
    func removeOrphanImages(keeping entries: [ClipboardEntry]) {
        let keep = Set(entries.filter { $0.kind == .image }.flatMap { ["\($0.contentHash).png", "\($0.contentHash)-thumb.png"] })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path)) ?? []
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(file))
        }
    }

    private func prepareDirectories() throws {
        let manager = FileManager.default
        for url in [directory, imagesURL] {
            try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
}

/// Hashing for the same-content check.
enum ClipboardHash {
    static func hash(kind: ClipboardKind, data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hash(kind: ClipboardKind, text: String) -> String {
        hash(kind: kind, data: Data(text.utf8))
    }
}

/// Shrinks and re-encodes copied images with ImageIO: no AppKit, and a
/// downscaled decode that never holds the full-size bitmap.
enum ClipboardImageCodec {
    struct Encoded: Sendable {
        var png: Data
        var thumbnail: Data
        var pixelWidth: Int
        var pixelHeight: Int
    }

    static let maxEdge = 2048
    static let thumbnailEdge = 128

    /// Nil when the data isn't an image, or the result would pass `maxBytes`.
    static func encode(_ data: Data, maxBytes: Int = ClipboardPolicy.maxImageBytes) -> Encoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = scaled(source, maxEdge: maxEdge),
              let png = png(image), png.count <= maxBytes,
              let thumb = scaled(source, maxEdge: thumbnailEdge).flatMap(Self.png) else { return nil }
        return Encoded(png: png, thumbnail: thumb, pixelWidth: image.width, pixelHeight: image.height)
    }

    private static func scaled(_ source: CGImageSource, maxEdge: Int) -> CGImage? {
        // A picture already small enough is used as it is; ImageIO's thumbnail
        // call is for shrinking, and may enlarge.
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxEdge {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func png(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

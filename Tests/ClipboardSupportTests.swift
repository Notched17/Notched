// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Notched

/// Clipboard history's policy, search, storage and image handling (#45).
@Suite("Clipboard support")
struct ClipboardSupportTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 100_000)

    private func entry(_ text: String, source: String? = nil, pinned: Bool = false, kind: ClipboardKind = .text) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), kind: kind, text: text, contentHash: "h-\(text)", createdAt: t0, isPinned: pinned, sourceBundleID: nil, sourceName: source)
    }

    // MARK: Policy

    @Test("Private types and excluded apps are skipped; ordinary copies aren't")
    func skipReasons() {
        #expect(ClipboardPolicy.skipReason(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari", excludedApps: []) == nil)
        #expect(ClipboardPolicy.skipReason(types: ["org.nspasteboard.ConcealedType"], sourceBundleID: nil, excludedApps: []) == .privateType)
        #expect(ClipboardPolicy.skipReason(types: [], sourceBundleID: "a.b", excludedApps: ["a.b"]) == .excludedApp)
        #expect(ClipboardPolicy.skipReason(types: [], sourceBundleID: nil, excludedApps: ["a.b"]) == nil)
    }

    // MARK: Search and order

    @Test("Every word must match, ignoring case and accents, in the text or the app name")
    func searching() {
        let entries = [entry("Café menu", source: "Notes"), entry("invoice 2026", source: "Mail"), entry("https://example.com", source: "Safari")]
        #expect(ClipboardSearch.filter(entries, query: "").count == 3)
        #expect(ClipboardSearch.filter(entries, query: "cafe").map(\.text) == ["Café menu"])
        #expect(ClipboardSearch.filter(entries, query: "INVOICE mail").map(\.text) == ["invoice 2026"])
        #expect(ClipboardSearch.filter(entries, query: "invoice notes").isEmpty)
        #expect(ClipboardSearch.filter(entries, query: "  safari  ").map(\.text) == ["https://example.com"])
    }

    @Test("Pinned items come first and each group keeps its order")
    func displayOrder() {
        let a = entry("a"), b = entry("b", pinned: true), c = entry("c"), d = entry("d", pinned: true)
        #expect(ClipboardSearch.displayOrder([a, b, c, d]).map(\.text) == ["b", "d", "a", "c"])
    }

    @Test("The preview is one line, trimmed to 200 characters")
    func preview() {
        #expect(entry("a\n\n  b\tc").preview == "a b c")
        let long = entry(String(repeating: "x", count: 500)).preview
        #expect(long.count == 201 && long.hasSuffix("…"))
    }

    @Test("Links are recognised only when the whole copy is one link")
    func links() {
        #expect(SystemClipboardPasteboard.isLink("https://example.com/a?b=1"))
        #expect(SystemClipboardPasteboard.isLink("  mailto:me@example.com\n"))
        #expect(!SystemClipboardPasteboard.isLink("see https://example.com"))
        #expect(!SystemClipboardPasteboard.isLink("example.com"))
        #expect(!SystemClipboardPasteboard.isLink("note: later"))
        #expect(!SystemClipboardPasteboard.isLink(""))
    }

    // MARK: Hashing

    @Test("The same content hashes the same, and a different kind doesn't")
    func hashing() {
        #expect(ClipboardHash.hash(kind: .text, text: "a") == ClipboardHash.hash(kind: .text, text: "a"))
        #expect(ClipboardHash.hash(kind: .text, text: "a") != ClipboardHash.hash(kind: .url, text: "a"))
        #expect(ClipboardHash.hash(kind: .text, text: "a") != ClipboardHash.hash(kind: .text, text: "b"))
        #expect(ClipboardHash.hash(kind: .text, text: "a").count == 64)
    }

    // MARK: Store

    private func tempStore() -> ClipboardStore {
        ClipboardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardTests-\(UUID().uuidString)"))
    }

    @Test("History round-trips through the file, with private permissions")
    func storeRoundTrip() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let saved = [entry("one", source: "Safari", pinned: true), entry("two")]
        try store.save(saved)
        #expect(store.load() == saved)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.directory.appendingPathComponent("history.json").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
    }

    @Test("A missing or damaged history file is an empty history")
    func storeTolerates() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.load().isEmpty)
        try store.save([entry("x")])
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("history.json"))
        #expect(store.load().isEmpty)
    }

    @Test("Image files are saved, found, deleted, and orphans are swept")
    func storeImages() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.saveImage(hash: "aaa", png: Data([1]), thumbnail: Data([2]))
        try store.saveImage(hash: "bbb", png: Data([3]), thumbnail: Data([4]))
        #expect(store.hasImage(hash: "aaa"))
        store.deleteImage(hash: "aaa")
        #expect(!store.hasImage(hash: "aaa"))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(hash: "aaa").path))
        store.removeOrphanImages(keeping: [])
        #expect(!store.hasImage(hash: "bbb"))
        try store.saveImage(hash: "ccc", png: Data([5]), thumbnail: Data([6]))
        store.removeOrphanImages(keeping: [ClipboardEntry(id: UUID(), kind: .image, text: "Image", contentHash: "ccc", createdAt: t0)])
        #expect(store.hasImage(hash: "ccc"))
    }

    // MARK: Images

    private func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    @Test("A big image is scaled down to 2048 and gets a 128 thumbnail")
    func imageScaling() throws {
        let encoded = try #require(ClipboardImageCodec.encode(png(width: 4000, height: 1000)))
        #expect(encoded.pixelWidth == 2048)
        #expect(encoded.pixelHeight == 512)
        let thumb = try #require(ClipboardImageCodec.pixelSize(of: encoded.thumbnail))
        #expect(max(thumb.width, thumb.height) == 128)
    }

    @Test("A small image is not enlarged beyond its size")
    func smallImage() throws {
        let data = png(width: 40, height: 30)
        let size = try #require(ClipboardImageCodec.pixelSize(of: data))
        #expect(size.width == 40 && size.height == 30)
        let encoded = try #require(ClipboardImageCodec.encode(data))
        #expect(encoded.pixelWidth == 40 && encoded.pixelHeight == 30)
        let thumb = try #require(ClipboardImageCodec.pixelSize(of: encoded.thumbnail))
        #expect(thumb.width == 40 && thumb.height == 30)
    }

    @Test("Data that isn't an image, or is over the size cap, is refused")
    func imageRefusals() {
        #expect(ClipboardImageCodec.encode(Data("hello".utf8)) == nil)
        #expect(ClipboardImageCodec.encode(png(width: 300, height: 300), maxBytes: 10) == nil)
        #expect(ClipboardImageCodec.pixelSize(of: Data("hello".utf8)) == nil)
    }

    // MARK: Settings

    @MainActor
    @Test("Settings default sensibly and ignore bad saved values")
    func settingsDefaults() {
        let defaults = UserDefaults(suiteName: "ClipboardSettingsTests.\(UUID().uuidString)")!
        let settings = ClipboardSettings(defaults: defaults)
        #expect(settings.historyLength == 200)
        #expect(!settings.clearOnQuit)
        #expect(settings.hotkeyEnabled)
        #expect(settings.excludedApps == ClipboardPolicy.defaultExcludedApps)
        defaults.set(7, forKey: ClipboardSettings.Key.historyLength)
        #expect(ClipboardSettings(defaults: defaults).historyLength == 200)
        settings.historyLength = 50
        settings.excludedApps = ["a.b"]
        let reloaded = ClipboardSettings(defaults: defaults)
        #expect(reloaded.historyLength == 50)
        #expect(reloaded.reducerConfig.excludedApps == ["a.b"])
    }
}

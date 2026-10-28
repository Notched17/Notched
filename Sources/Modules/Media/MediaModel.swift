// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// What the media regions draw. The module keeps it current; views read it
/// directly so a tick of new data never rebuilds the whole activity.
@MainActor
@Observable
final class MediaModel {
    private(set) var snapshot: NowPlayingSnapshot?
    /// Artwork downsampled for the island, decoded once per track.
    private(set) var artwork: NSImage?
    /// The artwork's accent, legible on black (white without artwork).
    private(set) var tint: Color = .white
    private(set) var tintRGB: ArtworkColor.RGB = .white
    private(set) var sourceIcon: NSImage?
    private(set) var sourceName: String?
    /// Whether the track is a favourite; nil hides the heart.
    var liked: Bool?
    var canLike = false
    var visualizer: VisualizerStyle = .animated
    /// Synced lyrics for this track, while lyrics are on (#13).
    var lyrics: SyncedLyrics?
    /// Show the current lyric line beside the notch instead of the bars.
    var lyricsTicker = false
    @ObservationIgnored var actions = MediaActions()
    /// The Mac's audio outputs, for the output button (#16). Set while the module runs.
    @ObservationIgnored var outputs: AudioOutputService?
    /// Called when decoded artwork (and its tint) arrives, after the snapshot it belongs to.
    @ObservationIgnored var onArtworkChange: () -> Void = {}
    @ObservationIgnored private var artworkData: Data?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    var isPlaying: Bool { snapshot?.isPlaying ?? false }
    var trackKey: TrackKey? { snapshot?.trackKey }

    func update(_ snapshot: NowPlayingSnapshot) {
        if snapshot.sourceBundleID != self.snapshot?.sourceBundleID { loadSource(snapshot.sourceBundleID) }
        if snapshot.artwork != artworkData {
            artworkData = snapshot.artwork
            decodeArtwork(snapshot.artwork)
        }
        if snapshot != self.snapshot { self.snapshot = snapshot }
    }

    func clear() {
        artworkTask?.cancel()
        snapshot = nil
        artworkData = nil
        artwork = nil
        tint = .white
        tintRGB = .white
        liked = nil
        canLike = false
        lyrics = nil
    }

    /// Music sends 1 MB+ originals, so they're cut down and measured off the
    /// main thread (CLAUDE.md: no main-thread work over 16 ms during animations).
    private func decodeArtwork(_ data: Data?) {
        artworkTask?.cancel()
        guard let data else {
            // Synchronous, inside the module's own update: no callback needed.
            apply(nil, notify: false)
            return
        }
        artworkTask = Task { [weak self] in
            let decoded = await Self.decode(data)
            guard !Task.isCancelled, let self else { return }
            self.apply(decoded, notify: true)
        }
    }

    private func apply(_ decoded: DecodedArtwork?, notify: Bool) {
        let rgb = decoded?.tint ?? .white
        artwork = decoded.map { NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height)) }
        tintRGB = rgb
        tint = decoded == nil ? .white : Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
        if notify { onArtworkChange() }
    }

    @concurrent
    private nonisolated static func decode(_ data: Data) async -> DecodedArtwork? {
        guard let image = thumbnail(data) else { return nil }
        return DecodedArtwork(image: image, tint: ArtworkColor.accent(of: image))
    }

    private func loadSource(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            sourceIcon = nil
            sourceName = nil
            return
        }
        sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        sourceName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Big artwork (Music sends originals of 1 MB+) is cut down to what the
    /// island draws, to keep memory low.
    private nonisolated static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Artwork cut down for the island, with its accent. A `CGImage` is immutable.
private struct DecodedArtwork: @unchecked Sendable {
    let image: CGImage
    let tint: ArtworkColor.RGB
}

/// What the media controls do; set by the module.
@MainActor
struct MediaActions {
    var send: (MediaCommand) -> Void = { _ in }
    var toggleLike: () -> Void = {}
    var openSource: () -> Void = {}
}

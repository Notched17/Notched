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
    @ObservationIgnored private var artworkData: Data?

    var isPlaying: Bool { snapshot?.isPlaying ?? false }
    var trackKey: TrackKey? { snapshot?.trackKey }

    func update(_ snapshot: NowPlayingSnapshot) {
        if snapshot.sourceBundleID != self.snapshot?.sourceBundleID { loadSource(snapshot.sourceBundleID) }
        if snapshot.artwork != artworkData {
            artworkData = snapshot.artwork
            applyArtwork(snapshot.artwork)
        }
        if snapshot != self.snapshot { self.snapshot = snapshot }
    }

    func clear() {
        snapshot = nil
        artworkData = nil
        artwork = nil
        tint = .white
        tintRGB = .white
        liked = nil
        canLike = false
        lyrics = nil
    }

    private func applyArtwork(_ data: Data?) {
        guard let data, let image = Self.thumbnail(data) else {
            artwork = nil
            tintRGB = .white
            tint = .white
            return
        }
        artwork = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let rgb = ArtworkColor.accent(of: image)
        tintRGB = rgb
        tint = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
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
    private static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// What the media controls do; set by the module.
@MainActor
struct MediaActions {
    var send: (MediaCommand) -> Void = { _ in }
    var toggleLike: () -> Void = {}
    var openSource: () -> Void = {}
}

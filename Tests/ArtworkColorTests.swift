// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

/// The accent colour that tints the visualiser and keyline (#9, #12).
@Suite("ArtworkColor")
struct ArtworkColorTests {
    /// A test image made of horizontal bands, each a fraction of the height.
    private func image(_ bands: [(r: CGFloat, g: CGFloat, b: CGFloat, share: CGFloat)], size: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var y: CGFloat = 0
        for band in bands {
            let height = CGFloat(size) * band.share
            context.setFillColor(red: band.r, green: band.g, blue: band.b, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: CGFloat(size), height: height))
            y += height
        }
        return context.makeImage()!
    }

    @Test func solidRedIsRed() {
        let accent = ArtworkColor.accent(of: image([(0.9, 0.1, 0.1, 1)]))
        #expect(accent.r > 0.8)
        #expect(accent.g < 0.25)
        #expect(accent.b < 0.25)
    }

    @Test func dominantHueWins() {
        let accent = ArtworkColor.accent(of: image([(0.1, 0.3, 0.9, 0.7), (0.95, 0.85, 0.1, 0.3)]))
        #expect(accent.b > accent.r)
        #expect(accent.b > accent.g)
    }

    @Test func greyscaleGivesWhite() {
        let accent = ArtworkColor.accent(of: image([(0.2, 0.2, 0.2, 0.5), (0.7, 0.7, 0.7, 0.5)]))
        #expect(accent == .white)
    }

    @Test func darkColourIsLifted() {
        let accent = ArtworkColor.accent(of: image([(0.05, 0.08, 0.3, 1)]))
        #expect(max(accent.r, accent.g, accent.b) >= 0.74)
        #expect(accent.b > accent.r)
    }

    @Test func deterministic() {
        let input = image([(0.6, 0.2, 0.5, 0.4), (0.2, 0.6, 0.4, 0.6)])
        #expect(ArtworkColor.accent(of: input) == ArtworkColor.accent(of: input))
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// The accent colour of a piece of artwork, for tinting the visualiser and
/// the island's keyline (#9, #12). Deterministic: the same image always
/// gives the same colour, and it is always legible on black.
enum ArtworkColor {
    struct RGB: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double

        static let white = RGB(r: 1, g: 1, b: 1)
    }

    private static let side = 24
    private static let hueBuckets = 12
    private static let minimumSaturation = 0.25
    private static let minimumBrightness = 0.15
    /// Lifted to at least this brightness so it reads on the black island.
    private static let legibleBrightness = 0.75
    private static let maximumSaturation = 0.85

    /// Downsamples to 24×24, groups saturated pixels into 12 hue buckets
    /// weighted by saturation, and returns the heaviest bucket's mean colour
    /// made legible on black. Artwork with no real colour gives white.
    static func accent(of image: CGImage) -> RGB {
        guard let pixels = sample(image) else { return .white }
        var weights = [Double](repeating: 0, count: hueBuckets)
        var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: hueBuckets)
        for pixel in pixels {
            let hsb = HSB(pixel)
            guard hsb.s >= minimumSaturation, hsb.b >= minimumBrightness else { continue }
            let bucket = min(Int(hsb.h * Double(hueBuckets)), hueBuckets - 1)
            weights[bucket] += hsb.s
            sums[bucket].r += pixel.r * hsb.s
            sums[bucket].g += pixel.g * hsb.s
            sums[bucket].b += pixel.b * hsb.s
        }
        // The first heaviest bucket wins ties, so the result is stable.
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] || (weights[$0] == weights[$1] && $0 > $1) }),
              weights[best] > 0 else { return .white }
        let weight = weights[best]
        var hsb = HSB(RGB(r: sums[best].r / weight, g: sums[best].g / weight, b: sums[best].b / weight))
        hsb.b = max(hsb.b, legibleBrightness)
        hsb.s = min(hsb.s, maximumSaturation)
        return hsb.rgb
    }

    /// The image drawn into a small sRGB bitmap, as 0…1 components.
    private static func sample(_ image: CGImage) -> [RGB]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return (0..<(side * side)).map { index in
            RGB(r: Double(bytes[index * 4]) / 255, g: Double(bytes[index * 4 + 1]) / 255, b: Double(bytes[index * 4 + 2]) / 255)
        }
    }

    /// Hue, saturation and brightness, each 0…1.
    private struct HSB {
        var h: Double
        var s: Double
        var b: Double

        init(_ rgb: RGB) {
            let maximum = max(rgb.r, rgb.g, rgb.b)
            let minimum = min(rgb.r, rgb.g, rgb.b)
            let delta = maximum - minimum
            b = maximum
            s = maximum > 0 ? delta / maximum : 0
            guard delta > 0 else { h = 0; return }
            var hue: Double = switch maximum {
            case rgb.r: (rgb.g - rgb.b) / delta
            case rgb.g: 2 + (rgb.b - rgb.r) / delta
            default: 4 + (rgb.r - rgb.g) / delta
            }
            hue /= 6
            h = hue < 0 ? hue + 1 : hue
        }

        var rgb: RGB {
            let sector = (h * 6).truncatingRemainder(dividingBy: 6)
            let index = Int(sector)
            let fraction = sector - Double(index)
            let p = b * (1 - s)
            let q = b * (1 - s * fraction)
            let t = b * (1 - s * (1 - fraction))
            return switch index {
            case 0: RGB(r: b, g: t, b: p)
            case 1: RGB(r: q, g: b, b: p)
            case 2: RGB(r: p, g: b, b: t)
            case 3: RGB(r: p, g: q, b: b)
            case 4: RGB(r: t, g: p, b: b)
            default: RGB(r: b, g: p, b: q)
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The island's opaque fill (#73): pure black, or with Reduce Transparency a
/// solid stand-in for a glass theme. Glass itself is applied by
/// `IslandView` around the content, so the content gets glass vibrancy.
///
/// On a notched display the compact island is always black so it merges with
/// the hardware notch; the theme fills the expanded island, blending from
/// black as it grows.
struct IslandSolidFill: View {
    let shape: IslandShape
    let model: IslandViewModel

    var body: some View {
        ZStack {
            shape
                .fill(fill)
                .opacity(model.surfaceIsGlass ? 0 : 1)
            // A dark wash inside the glass, so white content and the
            // activities' tints stay legible over light windows, like the
            // black island. (Glass.tint isn't drawn in a borderless
            // transparent panel on macOS 27.2, so it's a fill.)
            shape
                .fill(.black.opacity(IslandTheme.glassDarkening))
                .opacity(model.surfaceIsGlass ? 1 : 0)
            // Tinted Glass: an accent wash over it.
            shape
                .fill(Color.resolvedAccent.opacity(0.32))
                .opacity(model.surfaceIsGlass && model.theme == .tintedGlass ? 1 : 0)
        }
    }

    private var fill: Color {
        guard model.showsTheme, model.theme.isGlass, model.accessibility.reduceTransparency else { return .black }
        return model.theme == .tintedGlass ? Color.resolvedAccent.mix(with: .black, by: 0.7) : Color(white: 0.13)
    }
}

extension IslandTheme {
    /// The Liquid Glass variant for a glass theme. Tinted Glass adds its
    /// accent wash in `IslandSolidFill`.
    var glass: Glass { .regular }

    /// How dark the wash inside glass islands and bubbles is: enough that
    /// white text reads over a white window, while the glass's edge and
    /// refraction still show.
    static let glassDarkening = 0.5
}

extension Color {
    /// The system accent colour as a concrete sRGB colour, so it doesn't
    /// shift with the island's forced dark appearance.
    static var resolvedAccent: Color {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return Color(.sRGB, red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent)
    }
}

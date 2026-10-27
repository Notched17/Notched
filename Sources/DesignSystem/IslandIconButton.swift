// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A small circular control for the island. It uses interactive Liquid Glass
/// on the black island; on a glass island it uses a vibrant fill instead,
/// because glass must never sit on glass.
struct IslandIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 26
    var onGlassSurface = false
    let action: () -> Void
    @Environment(\.islandSurfaceIsGlass) private var islandIsGlass

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .modifier(IslandButtonSurface(onGlassSurface: onGlassSurface || islandIsGlass))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct IslandButtonSurface: ViewModifier {
    let onGlassSurface: Bool

    func body(content: Content) -> some View {
        if onGlassSurface {
            content.background(.fill.tertiary, in: Circle())
        } else {
            content.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

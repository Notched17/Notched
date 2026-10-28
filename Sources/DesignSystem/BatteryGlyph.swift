// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A small battery filled to its level, like the menu bar's: SF Symbols'
/// battery glyphs only come in quarter steps. A bolt is cut out of it while
/// charging, and a plug while plugged in but not charging.
struct BatteryGlyph: View {
    /// 0…100.
    let level: Int
    var isCharging = false
    var isPluggedIn = false
    var tint: Color = .white
    var width: CGFloat = 25
    var height: CGFloat = 12

    var body: some View {
        let fraction = CGFloat(min(max(level, 0), 100)) / 100
        let capWidth = max(1.5, width * 0.06)
        let bodyWidth = width - capWidth - 1
        let inset: CGFloat = 2
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.3 - inset / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max((bodyWidth - 2 * inset) * fraction, fraction > 0 ? 2 : 0))
                    .padding(inset)
                if isCharging || isPluggedIn {
                    // Cut out of the fill when the fill is under it; drawn in
                    // the tint over an emptier battery, where a cut-out would vanish.
                    let cutsOut = fraction >= 0.55
                    Image(systemName: isCharging ? "bolt.fill" : "powerplug.fill")
                        .font(.system(size: height * (isCharging ? 0.75 : 0.62), weight: .heavy))
                        .foregroundStyle(cutsOut ? .black : tint)
                        .frame(maxWidth: .infinity)
                        .blendMode(cutsOut ? .destinationOut : .normal)
                }
            }
            .compositingGroup()
            .frame(width: bodyWidth, height: height)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: capWidth, topTrailingRadius: capWidth, style: .continuous)
                .fill(.white.opacity(0.45))
                .frame(width: capWidth, height: height * 0.36)
        }
        .accessibilityHidden(true)
    }
}

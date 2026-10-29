// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// One look for every transient banner (ADR-0012), after iPhone's charging,
/// Silent and AirPods banners: a glyph or a short label leading, a value or
/// short text trailing (ISLAND-BEHAVIOR.md §1). Each side fits the banner's
/// share of the width budget; longer text scales down a little, then truncates.
@MainActor
struct BannerContent {
    /// A small glyph after the trailing value.
    enum Accessory {
        case symbol(String, tint: Color)
        /// A battery filled to `level` (0…100), with a bolt while charging
        /// and a plug while plugged in but not charging.
        case battery(level: Int, isCharging: Bool, isPluggedIn: Bool = false, tint: Color)
    }

    /// Leading glyph; bounces once when the banner appears.
    var symbol: String?
    var symbolTint: Color = .white
    /// Leading text, after the glyph.
    var label: String?
    var labelTint: Color = .white
    /// Trailing text, e.g. "82%" or "Connected".
    var value: String?
    var valueTint: Color = .white
    var accessory: Accessory?
    /// Something went away (a device disconnected): the whole banner is quieter.
    var isDimmed = false
}

extension TransientBanner {
    /// A banner in the standard look. `id` is the banner's category
    /// ("network", "battery.power"), so a newer one replaces a waiting one.
    static func standard(id: String, moduleID: ModuleID, content: BannerContent, priority: BannerPriority = .normal,
                         duration: Duration? = nil, accessibilityLabel: String,
                         openAction: (@MainActor () -> Void)? = nil) -> TransientBanner {
        let hasTrailing = content.value != nil || content.accessory != nil
        return TransientBanner(
            id: id,
            moduleID: moduleID,
            leading: IslandRegion { BannerLeading(content: content) },
            trailing: hasTrailing ? IslandRegion { BannerTrailing(content: content) } : nil,
            duration: duration,
            priority: priority,
            accessibilityLabel: accessibilityLabel,
            openAction: openAction
        )
    }
}

/// The widest one side of a banner can be: the width budget less the slot padding.
enum BannerMetrics {
    static let sideMaxWidth = IslandMetrics.compactWidthBudget - IslandMetrics.compactSlotPadding
    static let symbolSize: CGFloat = 14
    static let gap: CGFloat = 5
    static let minimumScale: CGFloat = 0.85
}

struct BannerLeading: View {
    let content: BannerContent
    @State private var appeared = false

    var body: some View {
        WidthCap(maxWidth: BannerMetrics.sideMaxWidth) {
            HStack(spacing: BannerMetrics.gap) {
                if let symbol = content.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: BannerMetrics.symbolSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(content.symbolTint)
                        .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
                }
                if let label = content.label {
                    BannerText(text: label, tint: content.labelTint)
                }
            }
        }
        .opacity(content.isDimmed ? 0.55 : 1)
        .onAppear { appeared = true }
    }
}

struct BannerTrailing: View {
    let content: BannerContent

    var body: some View {
        WidthCap(maxWidth: BannerMetrics.sideMaxWidth) {
            HStack(spacing: BannerMetrics.gap) {
                if let value = content.value {
                    BannerText(text: value, tint: content.valueTint)
                }
                switch content.accessory {
                case .symbol(let name, let tint):
                    Image(systemName: name)
                        .font(.system(size: BannerMetrics.symbolSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                case .battery(let level, let isCharging, let isPluggedIn, let tint):
                    BatteryGlyph(level: level, isCharging: isCharging, isPluggedIn: isPluggedIn, tint: tint)
                case nil:
                    EmptyView()
                }
            }
        }
        .opacity(content.isDimmed ? 0.55 : 1)
    }
}

private struct BannerText: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(IslandFont.compact)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(BannerMetrics.minimumScale)
            .truncationMode(.tail)
    }
}

/// Offers its content at most `maxWidth`, even when its parent asks for the
/// ideal size (compact regions are measured unconstrained), so long text
/// scales down or truncates instead of overflowing the island.
struct WidthCap: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        let ideal = content.sizeThatFits(.unspecified)
        let fitted = ideal.width <= width ? ideal : content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: min(fitted.width, width), height: fitted.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

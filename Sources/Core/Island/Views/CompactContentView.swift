// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The compact island's two sides, either side of the notch (or of the pill's
/// middle). One activity (or banner) owns both; side by side, the second
/// activity takes the trailing side. Content sits snug against the camera
/// housing (HIG: "snug against the TrueDepth camera").
struct CompactContentView: View {
    let model: IslandViewModel

    var body: some View {
        let layout = model.compactLayout
        let scene = model.compactScene
        HStack(spacing: 0) {
            side(width: layout.leadingSide, isLeading: true) {
                if layout.isSideBySide {
                    pair(scene.primary)
                } else if let primary = scene.primary {
                    region(primary.leading, of: primary, slot: "leading")
                }
            }
            .modifier(ActivityElement(content: layout.isSideBySide ? scene.primary : nil))
            Color.clear
                .frame(width: model.geometry.compactBaseSize.width)
            side(width: layout.trailingSide, isLeading: false) {
                if layout.isSideBySide {
                    pair(scene.secondary)
                } else if let primary = scene.primary, let trailing = primary.trailing {
                    region(trailing, of: primary, slot: "trailing")
                }
            }
            .modifier(ActivityElement(content: layout.isSideBySide ? scene.secondary : nil))
        }
        .frame(height: model.geometry.compactBaseSize.height)
        .foregroundStyle(.white)
        .environment(\.islandCompactWidthLimited, layout.isWidthLimited)
        .environment(\.islandMode, .compact)
        // One activity is one accessibility element: leading and trailing read together.
        .modifier(ActivityElement(content: layout.isSideBySide ? nil : scene.primary))
    }

    /// One side of the notch: the outer margin, the content against the
    /// housing, and a small gap before the housing.
    @ViewBuilder
    private func side<Content: View>(width: CGFloat, isLeading: Bool, @ViewBuilder content: () -> Content) -> some View {
        let inner = IslandMetrics.compactSlotInnerGap
        let outer = max(IslandMetrics.compactSlotPadding - inner, 0)
        if width > inner + outer {
            ZStack { content() }
                .frame(width: width - inner - outer, alignment: isLeading ? .trailing : .leading)
                .padding(isLeading ? .leading : .trailing, outer)
                .padding(isLeading ? .trailing : .leading, inner)
        } else {
            Color.clear.frame(width: max(width, 0))
        }
    }

    /// Side by side: one activity's leading and trailing content together.
    @ViewBuilder
    private func pair(_ content: IslandViewModel.CompactContent?) -> some View {
        if let content {
            HStack(spacing: IslandMetrics.sideBySideGap) {
                region(content.leading, of: content, slot: "leading")
                if let trailing = content.trailing {
                    region(trailing, of: content, slot: "trailing")
                }
            }
        }
    }

    private func region(_ region: IslandRegion, of content: IslandViewModel.CompactContent, slot: String) -> some View {
        let key = "\(content.key).\(slot)"
        return IslandRegionHost(revision: content.revision, isStale: content.isStale) {
            region.view()
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            model.reportWidth(width, for: key)
        }
        .id(content.key)
        .transition(AnyTransition(.blurReplace).combined(with: .opacity))
    }
}

/// Makes an activity's compact content one accessibility element, labelled
/// with the activity's own description (both sides together).
private struct ActivityElement: ViewModifier {
    let content: IslandViewModel.CompactContent?

    func body(content view: Content) -> some View {
        if let content {
            view
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(content.accessibilityLabel)
        } else {
            view
        }
    }
}

/// How an activity's region is being shown, so a module can adapt (like
/// WidgetKit's `DynamicIslandMode`).
enum IslandMode: Sendable {
    case compact, minimal, expanded
}

extension EnvironmentValues {
    /// Compact and minimal regions are narrower than usual (two or more
    /// activities are showing); show the reduced form. Like
    /// `isDynamicIslandLimitedInWidth` on iPhone.
    @Entry var islandCompactWidthLimited = false
    @Entry var islandMode: IslandMode = .expanded
}

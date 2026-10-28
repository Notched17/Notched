// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Home's quick actions (Keep Awake, Timer…): glass capsules in one
/// container so their glass blends, and the open one's panel below them.
struct HomeActionsView: View {
    let actions: [HomeAction]
    @Binding var openID: String?
    @Environment(\.islandReduceMotion) private var reduceMotion

    var body: some View {
        let open = actions.first { $0.id == openID }
        VStack(spacing: Spacing.s) {
            GlassEffectContainer(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    ForEach(actions) { action in
                        HomeActionButton(action: action, isOpen: action.id == openID) {
                            withAnimation(reduceMotion ? Motion.reduced : Motion.content) {
                                openID = openID == action.id ? nil : action.id
                            }
                        }
                    }
                }
            }
            if let open {
                open.panel.view()
                    .id(open.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    .environment(\.closeHomePanel, CloseHomePanelAction {
                        withAnimation(reduceMotion ? Motion.reduced : Motion.content) { openID = nil }
                    })
            }
        }
        .frame(maxWidth: .infinity)
        // An action that goes away (its module turned off) closes its panel.
        .onChange(of: actions.map(\.id)) { _, ids in
            if let openID, !ids.contains(openID) { self.openID = nil }
        }
    }
}

private struct HomeActionButton: View {
    let action: HomeAction
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: action.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                Text(action.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .opacity(0.6)
            }
        }
        .buttonStyle(action.isOn ? .island(prominent: action.tint) : .island)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.accessibilityValue ?? (action.isOn ? "On" : "Off"))
        .accessibilityHint(isOpen ? "Hides its options" : "Shows its options")
    }
}

/// A row of small choices inside a Home action panel or an expanded
/// activity, e.g. timer presets. Glass capsules grouped so they blend.
struct IslandChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                content()
            }
        }
    }
}

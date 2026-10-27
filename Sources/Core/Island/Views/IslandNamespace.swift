// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension EnvironmentValues {
    /// Shared by compact and expanded content, so a module's views can morph
    /// between the two with `islandMatchedGeometry(id:)`.
    @Entry var islandNamespace: Namespace.ID?
}

extension View {
    /// Links this view with the view of the same `id` in the other island state.
    func islandMatchedGeometry(id: String) -> some View {
        modifier(IslandMatchedGeometry(id: id))
    }
}

private struct IslandMatchedGeometry: ViewModifier {
    let id: String
    @Environment(\.islandNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

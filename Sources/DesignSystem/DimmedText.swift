// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Secondary text on the black island: white at `opacity`, raised when Increase
/// Contrast is on. Hard-coded `.foregroundStyle(.white.opacity(…))` is
/// forbidden by `AccessibilityLintTests`, because it ignores that setting.
struct DimmedText: ViewModifier {
    var opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast

    /// Increase Contrast lifts every level to at least 85 % white (about 15:1 on black).
    static func resolved(_ opacity: Double, increased: Bool) -> Double {
        increased ? max(opacity, 0.85) : opacity
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(.white.opacity(Self.resolved(opacity, increased: contrast == .increased)))
    }
}

extension View {
    func dimmedText(_ opacity: Double) -> some View { modifier(DimmedText(opacity: opacity)) }
}

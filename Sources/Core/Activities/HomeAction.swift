// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A quick action a module offers on the expanded island's Home page, such
/// as Keep Awake or a new timer. Clicking it opens its panel (presets and
/// the like) in place, because the island never takes keyboard focus.
@MainActor
struct HomeAction: Identifiable {
    let id: String
    let moduleID: ModuleID
    var title: String
    var symbol: String
    /// Shown as on (tinted), e.g. while keep-awake runs.
    var isOn: Bool = false
    var tint: Color = .accentColor
    /// Read after the title by VoiceOver, e.g. "On until 15:30".
    var accessibilityValue: String?
    /// The controls opened under the row. Its buttons call
    /// `\.closeHomePanel` once they've done their job.
    var panel: IslandRegion
}

/// Closes the Home action panel that's open, like SwiftUI's `DismissAction`.
@MainActor
struct CloseHomePanelAction {
    var action: @MainActor () -> Void = {}

    func callAsFunction() { action() }
}

extension EnvironmentValues {
    /// Closes the Home action panel that's open, if any.
    @Entry var closeHomePanel = CloseHomePanelAction()
}

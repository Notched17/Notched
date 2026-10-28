// SPDX-License-Identifier: GPL-3.0-or-later

/// What the app shows about a module before it is ever created.
struct ModuleDescriptor: Identifiable, Sendable {
    let id: ModuleID
    let name: String
    /// SF Symbol name.
    let symbol: String
    let summary: String
    /// Requested only when the user turns the module on.
    let permissions: [Permission]
    /// Shown only in DEBUG builds.
    let isDebugOnly: Bool
    /// Turned on once, the first time the app sees the module (`ModuleDefaults`).
    /// Modules that need a permission stay off by default.
    var isOnByDefault: Bool = false
}

// SPDX-License-Identifier: GPL-3.0-or-later

/// Turns on, exactly once, each default-on module the app has never seen,
/// for new installs and for existing ones when a module ships. After that,
/// what the user chose sticks: a module they turned off stays off.
enum ModuleDefaults {
    static func apply(_ descriptors: [ModuleDescriptor], enabled: Set<ModuleID>, seen: Set<ModuleID>)
        -> (enabled: Set<ModuleID>, seen: Set<ModuleID>) {
        var enabled = enabled
        var seen = seen
        for descriptor in descriptors where !seen.contains(descriptor.id) {
            if descriptor.isOnByDefault { enabled.insert(descriptor.id) }
            seen.insert(descriptor.id)
        }
        return (enabled, seen)
    }
}

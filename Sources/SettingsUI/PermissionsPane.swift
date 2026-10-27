// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Replaced with live TCC status in task 7.
struct PermissionsPane: View {
    let modules: [ModuleDescriptor]
    let settings: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    Label(permission.title, systemImage: permission.symbol)
                }
            }
        }
        .formStyle(.grouped)
    }
}

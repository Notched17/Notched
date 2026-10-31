// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Settings ▸ Modules ▸ Camera & Microphone.
struct SensorsSettingsPane: View {
    @Bindable var settings: SensorsSettings

    var body: some View {
        Form {
            Section {
                Toggle("Microphone (orange)", isOn: $settings.showMicrophone)
                Toggle("Camera (green)", isOn: $settings.showCamera)
            } header: {
                Text("Show")
            } footer: {
                Text("Notched says when an app is using the camera or microphone. It names an app only when macOS makes the owner clear, and otherwise says \"An app\". macOS shows its own indicator in the menu bar as well. While a call is on, the call app's own microphone and camera show with the call instead.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Camera & Microphone")
    }
}

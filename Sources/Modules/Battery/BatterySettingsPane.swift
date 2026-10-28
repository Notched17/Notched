// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Settings ▸ Modules ▸ Battery.
struct BatterySettingsPane: View {
    @Bindable var settings: BatterySettings

    var body: some View {
        Form {
            Section {
                Picker("First warning", selection: $settings.firstWarning) {
                    Text("Off").tag(0)
                    ForEach(BatterySettings.firstWarningChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("Second warning", selection: $settings.secondWarning) {
                    Text("Off").tag(0)
                    ForEach(BatterySettings.secondWarningChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
            } header: {
                Text("Low Battery")
            } footer: {
                Text("A banner shows once as the battery falls to each level, while it isn't charging.")
            }

            Section {
                Picker("Show on the island", selection: $settings.showWhileChargingUntil) {
                    Text("Never").tag(0)
                    Text("Until 80%").tag(80)
                    Text("Until Full").tag(100)
                }
            } header: {
                Text("While Charging")
            } footer: {
                Text("Plugging in and unplugging always show a short banner. You can also keep the charge level beside the notch while charging; whatever's playing stays first.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery")
    }
}
